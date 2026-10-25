// A pretend TP-Link router web interface for tests: the router side of the
// login and data protocol, in any of the variants the app supports. It
// checks every signature and session detail a real router checks.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:cryptography/cryptography.dart';
import 'package:wifi_watch/src/router/tplink_client.dart';
import 'package:wifi_watch/src/router/tplink_crypto.dart';

// A 512-bit test key pair, like the routers use.
const testNn =
    'c57c0504bc34093e42f3adc3da53c7ae4e64a067d2296aa2823854c078c33c406b0cd7c217c88a138ec9d672007f1873a634c1494d2418deb1eab2d68118bc15';
const _testD =
    '7c043a12932e0a6ff3139c17d64faea223d0c57aed5bdcff58cf8f499f8cdb946d41f30451b2b1d279822075928d147810296e36e5fda398721b4c6f818b1f01';
const testEe = '010001';

enum TokenStyle { varToken, property, cookieOnly }

class FakeHost {
  final String mac, ip, name;
  final int connType;
  final bool active;
  final int? totalRx, totalTx, currRx, currTx;
  const FakeHost(this.mac, this.ip, this.name, this.connType,
      {this.active = true, this.totalRx, this.totalTx, this.currRx, this.currTx});
}

class FakeTplinkRouter {
  final TpVariant variant;
  final String username;
  final String password;
  final String model;

  /// How the start page gives the session token.
  final TokenStyle tokenStyle;
  List<FakeHost> hosts;
  final int seq = 581063244;

  /// The first login key request takes this long, like a busy router.
  Duration slowFirstKey = Duration.zero;
  bool _keyAsked = false;

  /// How many logins were refused, like the router's lockout counter.
  int failedLogins = 0;
  int logins = 0;
  final List<String> requests = [];

  late HttpServer _server;
  String? _key, _iv, _session, _token;

  FakeTplinkRouter({
    required this.variant,
    this.username = 'admin',
    this.password = 'secret',
    this.model = 'Archer XX530v',
    this.tokenStyle = TokenStyle.varToken,
    this.hosts = const [],
  });

  String get address => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  /// Forgets the session, as when someone else logs in to the router.
  void expireSession() {
    _session = null;
    _token = null;
  }

  bool get _ex => variant.protocol == TpProtocol.ex;
  String get _keyPath => variant.protocol == TpProtocol.mr ? '/cgi/getParm' : '/cgi/getGDPRParm';

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    requests.add('${req.method} $path');
    final res = req.response;
    // Like the routers' small web servers: no chunked bodies, no Dart agent.
    if (req.method == 'POST' && req.headers.contentLength < 0 ||
        (req.headers.value(HttpHeaders.userAgentHeader) ?? '').startsWith('Dart')) {
      final socket = await res.detachSocket(writeHeaders: false);
      socket.destroy();
      return;
    }
    try {
      if (path == _keyPath && req.method == 'POST' && !_keyAsked && slowFirstKey > Duration.zero) {
        _keyAsked = true;
        await Future<void>.delayed(slowFirstKey);
        res.write('too late');
      } else if (path == _keyPath && req.method == 'POST') {
        res.write('var ee="$testEe";\nvar nn="$testNn";\nvar seq="$seq";\n\$.ret=0;\n');
      } else if (path == '/' && req.method == 'GET') {
        final sessionOk = _session != null && req.cookies.any((c) => c.name == 'JSESSIONID' && c.value == _session);
        res.write(!sessionOk
            ? '<html>login page</html>'
            : switch (tokenStyle) {
                TokenStyle.varToken => '<script>var token="$_token";</script>',
                TokenStyle.property =>
                  '<script>var token;\nvar tmpcount = {};\ntmpcount.Token=$_token;\nfunction f(username,token) {}</script>',
                TokenStyle.cookieOnly => '<script>var token;\n\$.Iencryptor.setHash(username, token);</script>',
              });
      } else if (path == '/js/oid_str.js') {
        res.write('var DEV2_HOST_ENTRY="DEV2_HOST_ENTRY";\nvar DEV2_DEV_INFO="x";\nvar DEV2_WIFI_ASSOC_STATS="x";\nvar DEV2_LTE_SMS_STAT="x";\n');
      } else if (path == '/cgi/login' && variant.protocol == TpProtocol.mr) {
        await _mrLogin(req);
      } else if (path == '/cgi_gdpr') {
        await _gdpr(req, body);
      } else {
        res.statusCode = 404;
      }
    } catch (e) {
      res.statusCode = 500;
      res.write('$e');
    }
    await res.close();
  }

  /// Decrypts a signature; returns its fields.
  Map<String, String> _openSign(String sign) {
    final n = BigInt.parse(testNn, radix: 16), d = BigInt.parse(_testD, radix: 16);
    final bytes = <int>[];
    for (var i = 0; i < sign.length; i += testNn.length) {
      final m = BigInt.parse(sign.substring(i, i + testNn.length), radix: 16).modPow(d, n);
      final block = m.toRadixString(16).padLeft(testNn.length, '0');
      for (var j = 0; j < block.length; j += 2) {
        bytes.add(int.parse(block.substring(j, j + 2), radix: 16));
      }
    }
    final text = utf8.decode(bytes.where((b) => b != 0).toList());
    return Uri.splitQueryString(text, encoding: latin1);
  }

  void _checkSign(Map<String, String> f, String data) {
    final hash = md5.convert(utf8.encode('$username$password')).toString();
    if (f['h'] != hash) throw StateError('wrong-password');
    if (f['s'] != '${seq + data.length}') throw StateError('bad sequence ${f['s']}');
  }

  void _takeKey(Map<String, String> f) {
    if (variant.cipher == TpCipher.gcm) {
      _key = utf8.decode(base64.decode(f['key']!));
      _iv = utf8.decode(base64.decode(f['iv']!));
      if (_iv!.length != 12) throw StateError('GCM iv must be 12 characters');
    } else {
      _key = f['key'];
      _iv = f['iv'];
      if (_iv!.length != 16) throw StateError('CBC iv must be 16 characters');
    }
  }

  Future<void> _mrLogin(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final data = q['data']!;
    final f = _openSign(q['sign']!);
    if (f['h'] != md5.convert(utf8.encode('$username$password')).toString()) {
      failedLogins++;
      req.response.write('\$.ret=71233;\nvar currAuthTimes=$failedLogins;\nvar currForbidTime=0;\n');
      return;
    }
    _checkSign(f, data);
    _takeKey(f);
    final plain = await _decrypt(data, q['tag']);
    if (plain != '$username\n$password') throw StateError('bad credentials text');
    _newSession(req);
    req.response.write('\$.ret=0;\n');
  }

  void _newSession(HttpRequest req) {
    logins++;
    _session = 'S${DateTime.now().microsecondsSinceEpoch}';
    _token = 'a3f${logins}c9e0b17d24f68a9c1e3b5d7f02';
    req.response.headers.add(HttpHeaders.setCookieHeader, 'JSESSIONID=$_session; Path=/; HttpOnly');
  }

  Future<void> _gdpr(HttpRequest req, String body) async {
    if (_ex != req.uri.query.startsWith('9')) throw StateError('wrong cgi_gdpr form for $variant');
    final fields = <String, String>{};
    for (final line in body.split('\r\n')) {
      final eq = line.indexOf('=');
      if (eq > 0) fields[line.substring(0, eq)] = line.substring(eq + 1);
    }
    final data = fields['data']!;
    if ((variant.cipher == TpCipher.gcm) != fields.containsKey('tag')) throw StateError('tag field mismatch');
    final f = _openSign(fields['sign']!);

    if (f.containsKey('key')) {
      // Login.
      try {
        _checkSign(f, data);
      } on StateError catch (e) {
        if (e.message != 'wrong-password') rethrow;
        failedLogins++;
        _takeKey(f);
        req.response.write(await _encrypt('\$.ret=71233;\n'));
        return;
      }
      _takeKey(f);
      final plain = await _decrypt(data, fields['tag']);
      final String user, pass;
      if (_ex) {
        final j = jsonDecode(plain) as Map;
        if (j['oid'] != '/cgi/login') throw StateError('not a login');
        final d = j['data'] as Map;
        user = utf8.decode(base64.decode(d['UserName'] as String));
        pass = utf8.decode(base64.decode(d['Passwd'] as String));
      } else {
        final lines = plain.split('\r\n');
        if (lines[0] != '8' || !lines[1].startsWith('[/cgi/login#')) throw StateError('not a login: $plain');
        user = lines[2].substring('UserName='.length);
        pass = utf8.decode(base64.decode(lines[3].substring('Passwd='.length)));
      }
      if (user != username || pass != password) {
        failedLogins++;
        req.response.write(await _encrypt('\$.ret=71233;\n'));
        return;
      }
      _newSession(req);
      req.response.write(await _encrypt('\$.ret=0;\n'));
      return;
    }

    // A data request: needs the session cookie and token.
    final sessionOk = _session != null &&
        req.cookies.any((c) => c.name == 'JSESSIONID' && c.value == _session) &&
        (tokenStyle == TokenStyle.cookieOnly || req.headers.value('TokenID') == _token);
    if (!sessionOk) {
      req.response.statusCode = 403;
      return;
    }
    _checkSign(f, data);
    final plain = await _decrypt(data, fields['tag']);
    req.response.write(await _encrypt(_ex ? _exReply(plain) : _mrReply(plain)));
  }

  String _exReply(String plain) {
    final j = jsonDecode(plain) as Map;
    final oid = j['oid'];
    final Object? data = switch (oid) {
      'DEV2_HOST_ENTRY' => [
          for (final h in hosts)
            {
              'active': h.active ? '1' : '0',
              'X_TP_LanConnType': '${h.connType}',
              'physAddress': h.mac.toLowerCase(),
              'IPAddress': h.ip,
              'hostName': h.name,
              'X_TP_Vendor': 'vivo Mobile Communication',
              'stack': '1,0,0,0,0,0',
            },
        ],
      'DEV2_DEV_INFO' => {'modelName': model, 'hardwareVersion': '$model v1', 'softwareVersion': '1.1.0'},
      '/cgi/logout' => null,
      _ => throw StateError('unknown oid $oid'),
    };
    return jsonEncode({'data': data, 'errorcode': 0, 'success': true});
  }

  String _mrReply(String plain) {
    final lines = plain.split('\r\n');
    final types = lines.first.split('&');
    final out = StringBuffer();
    var index = 0;
    for (final line in lines.skip(1)) {
      final m = RegExp(r'^\[([^#]+)#').firstMatch(line);
      if (m == null) continue;
      final oid = m.group(1)!;
      final type = types[index];
      switch (oid) {
        case 'LAN_HOST_ENTRY':
          for (final (i, h) in hosts.indexed) {
            out.write('[1,${i + 1},0,0,0,0]$index\nIPAddress=${h.ip}\nMACAddress=${h.mac}\nhostName=${h.name}\n'
                'X_TP_ConnType=${h.connType}\nactive=${h.active ? 1 : 0}\n');
          }
        case 'STAT_ENTRY':
          for (final (i, h) in hosts.indexed) {
            if (h.totalRx == null) continue;
            out.write('[${i + 1},0,0,0,0,0]$index\nipAddress=${h.ip}\nmacAddress=${h.mac}\n'
                'totalBytesRx=${h.totalRx}\ntotalBytesTx=${h.totalTx}\ncurrBytesRx=${h.currRx}\ncurrBytesTx=${h.currTx}\n');
          }
        case 'IGD_DEV_INFO':
          out.write('[0,0,0,0,0,0]$index\nhardwareVersion=$model v1\nmodelName=$model\nsoftwareVersion=1.1.0\n');
        case '/cgi/logout':
          if (type != '8') throw StateError('logout is a cgi act');
          out.write('[cgi]$index\n\$.ret=0;\n');
        default:
          throw StateError('unknown oid $oid');
      }
      index++;
    }
    out.write('[error]0\n');
    return out.toString();
  }

  Future<String> _decrypt(String data, String? tag) async {
    final key = SecretKey(utf8.encode(_key!));
    final List<int> plain;
    if (variant.cipher == TpCipher.cbc) {
      plain = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
          .decrypt(SecretBox(base64.decode(data), nonce: utf8.encode(_iv!), mac: Mac.empty), secretKey: key);
    } else {
      plain = await AesGcm.with128bits(nonceLength: 12).decrypt(
          SecretBox(base64.decode(data), nonce: utf8.encode(_iv!), mac: Mac(base64.decode(tag!))),
          secretKey: key);
    }
    return utf8.decode(plain);
  }

  Future<String> _encrypt(String text) async {
    final key = SecretKey(utf8.encode(_key!));
    if (variant.cipher == TpCipher.cbc) {
      final box = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
          .encrypt(utf8.encode(text), secretKey: key, nonce: utf8.encode(_iv!));
      return base64.encode(box.cipherText);
    }
    final box = await AesGcm.with128bits(nonceLength: 12)
        .encrypt(utf8.encode(text), secretKey: key, nonce: utf8.encode(_iv!));
    return base64.encode(box.cipherText) + base64.encode(Uint8List.fromList(box.mac.bytes));
  }
}
