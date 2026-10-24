// Talks to a TP-Link router's own web interface, the way its admin page does.
// There is no official API, so the client tries the known protocol variants
// and remembers which one worked:
//   mr  MR/Archer LTE routers: key from cgi/getParm, login in the URL.
//   vr  Archer VR DSL routers: key from cgi/getGDPRParm, login as a cgi act.
//   ex  EX/XC/VX/XX ISP routers: key from cgi/getGDPRParm, JSON acts.
// Each can use AES-CBC (older firmware) or AES-GCM (newer).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'router_source.dart';
import 'tplink_crypto.dart';

enum TpProtocol { mr, vr, ex }

class TpVariant {
  final TpProtocol protocol;
  final TpCipher cipher;
  const TpVariant(this.protocol, this.cipher);

  String get id => '${protocol.name}-${cipher.name}';

  static TpVariant? parse(String? id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }

  /// In the order they are tried. Newer ISP firmware first.
  static const all = [
    TpVariant(TpProtocol.ex, TpCipher.gcm),
    TpVariant(TpProtocol.ex, TpCipher.cbc),
    TpVariant(TpProtocol.vr, TpCipher.cbc),
    TpVariant(TpProtocol.mr, TpCipher.gcm),
    TpVariant(TpProtocol.mr, TpCipher.cbc),
  ];

  @override
  String toString() => id;
}

class RouterException implements Exception {
  final String message;

  /// The router said the password is wrong. Stop trying: routers lock the
  /// login after a few failures.
  final bool wrongPassword;
  RouterException(this.message, {this.wrongPassword = false});

  @override
  String toString() => message;
}

class _Act {
  final String oid;
  final String mrType;
  final String exType;
  final List<String> attrs;
  const _Act(this.oid, this.mrType, this.exType, [this.attrs = const []]);

  static _Act gl(String oid, [List<String> attrs = const []]) => _Act(oid, '5', 'gl', attrs);
  static _Act get(String oid, [List<String> attrs = const []]) => _Act(oid, '1', 'go', attrs);
}

class TplinkClient implements RouterSource {
  static const _okRet = 0;
  static const _wrongPasswordRet = 71233;
  static const _zeroStack = '0,0,0,0,0,0';

  final String host;
  final String username;
  final String password;
  final Duration timeout;

  /// Diagnostic lines, never containing the password.
  final void Function(String line)? log;

  TpVariant? variant;
  String? model;

  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies = {};
  TpCrypto? _crypto;
  String? _nn, _ee, _hash, _token;
  int _seq = 0;
  bool _statsSupported = true;

  TplinkClient({
    required String host,
    required this.username,
    required this.password,
    this.variant,
    this.log,
    this.timeout = const Duration(seconds: 10),
  }) : host = _baseUrl(host) {
    _http.connectionTimeout = timeout;
  }

  static String _baseUrl(String host) {
    var h = host.trim();
    if (!h.startsWith('http://') && !h.startsWith('https://')) h = 'http://$h';
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  @override
  String get name => model == null ? 'TP-Link router' : 'TP-Link $model';

  bool get isLoggedIn => _token != null;

  /// Logs in with [variant] if set, otherwise finds the variant that works.
  Future<void> connect() async {
    final known = variant;
    if (known != null) {
      await _login(known);
      return;
    }
    final gdpr = await _probeKey('cgi/getGDPRParm');
    final parm = await _probeKey('cgi/getParm');
    final candidates = TpVariant.all.where((v) => v.protocol == TpProtocol.mr ? parm : gdpr).toList();
    if (candidates.isEmpty) {
      throw RouterException('$host did not answer like a TP-Link router (no login key). '
          'Check the address, and that the phone is on the home Wi-Fi.');
    }
    final errors = <String>[];
    for (final v in candidates) {
      try {
        await _login(v);
        variant = v;
        return;
      } on RouterException catch (e) {
        if (e.wrongPassword) rethrow;
        errors.add('$v: ${e.message}');
      } catch (e) {
        errors.add('$v: $e');
      }
    }
    throw RouterException('Could not log in with any known method.\n${errors.join('\n')}');
  }

  Future<bool> _probeKey(String path) async {
    try {
      final (code, body) = await _send('POST', _url(path));
      final ok = code == 200 && body.contains('var nn=');
      log?.call('$path: HTTP $code, ${ok ? 'login key found' : 'no login key'}');
      return ok;
    } catch (e) {
      log?.call('$path: $e');
      return false;
    }
  }

  Future<void> _login(TpVariant v) async {
    log?.call('Trying $v as "$username"');
    _cookies.clear();
    _token = null;
    _crypto = TpCrypto(v.cipher);
    _hash = TpCrypto.loginHash(username, password);
    await _fetchKey(v.protocol == TpProtocol.mr ? 'cgi/getParm' : 'cgi/getGDPRParm');

    final String reply;
    switch (v.protocol) {
      case TpProtocol.mr:
        final enc = await _crypto!.encrypt('$username\n$password');
        final sign = _sign(enc.data, isLogin: true);
        final params = {
          'data': enc.data,
          'sign': sign,
          if (enc.tag != null) 'tag': enc.tag!,
          'Action': '1',
          'LoginStatus': '0',
          'isMobile': '0',
        };
        final (_, body) = await _send('POST', _url('cgi/login', params));
        reply = body;
      case TpProtocol.vr:
        final b64 = base64.encode(utf8.encode(password));
        final text = _mrActText([_Act('/cgi/login', '8', 'cgi', ['UserName=$username', 'Passwd=$b64'])]);
        reply = await _encryptedPost(_url('cgi_gdpr'), text, isLogin: true);
      case TpProtocol.ex:
        final text = jsonEncode({
          'data': {
            'UserName': base64.encode(utf8.encode(username)),
            'Passwd': base64.encode(utf8.encode(password)),
            'Action': '1',
            'stack': _zeroStack,
            'pstack': _zeroStack,
          },
          'operation': 'cgi',
          'oid': '/cgi/login',
        });
        reply = await _encryptedPost('$host/cgi_gdpr?9', text, isLogin: true);
    }

    final ret = _retCode(reply);
    if (ret == _wrongPasswordRet) {
      throw RouterException('The router says the user name or password is wrong.', wrongPassword: true);
    }
    if (ret != _okRet) {
      throw RouterException(ret == null ? 'Unexpected login reply' : 'Login refused, code $ret');
    }

    final (code, page) = await _send('GET', _url(''));
    final token = RegExp(r'var token="([^"]*)";').firstMatch(page)?.group(1);
    if (code != 200 || token == null || token.isEmpty) {
      throw RouterException('Logged in, but the router sent no session token (HTTP $code)');
    }
    _token = token;
    variant = v;
    log?.call('Logged in with $v');
    await _readModel();
  }

  Future<void> _fetchKey(String path) async {
    final (code, body) = await _send('POST', _url(path));
    String? field(String name) => RegExp('var $name="([^"]*)";').firstMatch(body)?.group(1);
    final nn = field('nn'), ee = field('ee'), seq = int.tryParse(field('seq') ?? '');
    if (code != 200 || nn == null || ee == null || seq == null) {
      throw RouterException('No login key at $path (HTTP $code)');
    }
    _nn = nn;
    _ee = ee;
    _seq = seq;
  }

  Future<void> _readModel() async {
    try {
      final rows = await _query([_Act.get(variant!.protocol == TpProtocol.ex ? 'DEV2_DEV_INFO' : 'IGD_DEV_INFO',
          ['modelName', 'hardwareVersion', 'softwareVersion'])]);
      final info = rows[0].isEmpty ? const <String, String>{} : rows[0].first;
      model = info['modelName'];
      log?.call('Model: ${info['modelName']}, hardware ${info['hardwareVersion']}, firmware ${info['softwareVersion']}');
    } catch (e) {
      log?.call('Could not read the model: $e');
    }
  }

  @override
  Future<RouterSnapshot> fetch() async {
    if (!isLoggedIn) await connect();
    try {
      return await _fetchClients();
    } catch (e) {
      if (e is RouterException && e.wrongPassword) rethrow;
      // Sessions expire, and someone opening the router's web page logs us
      // out. Log in again once.
      log?.call('Request failed ($e), logging in again');
      _token = null;
      await connect();
      return _fetchClients();
    }
  }

  Future<RouterSnapshot> _fetchClients() async {
    final ex = variant!.protocol == TpProtocol.ex;
    final rows = (await _query([
      ex
          ? _Act.gl('DEV2_HOST_ENTRY', ['active', 'X_TP_LanConnType', 'physAddress', 'IPAddress', 'hostName'])
          : _Act.gl('LAN_HOST_ENTRY', ['IPAddress', 'MACAddress', 'hostName', 'X_TP_ConnType', 'active']),
    ]))[0];

    final stats = <String, Map<String, String>>{};
    if (!ex && _statsSupported) {
      try {
        for (final s in (await _query([_Act.gl('STAT_ENTRY')]))[0]) {
          final mac = s['macAddress'];
          if (mac != null) stats[normalizeMac(mac)] = s;
        }
      } catch (e) {
        _statsSupported = false;
        log?.call('No traffic statistics: $e');
      }
    }

    final clients = <ClientInfo>[];
    for (final r in rows) {
      if (r['active'] == '0') continue;
      final mac = normalizeMac(r[ex ? 'physAddress' : 'MACAddress'] ?? '');
      if (mac.isEmpty) continue;
      final type = int.tryParse(r[ex ? 'X_TP_LanConnType' : 'X_TP_ConnType'] ?? '');
      final s = stats[mac];
      int? num(String k) => s == null ? null : int.tryParse(s[k] ?? '');
      final totalDown = num('totalBytesRx'), totalUp = num('totalBytesTx');
      clients.add(ClientInfo(
        mac: mac,
        ip: r['IPAddress'] ?? '',
        hostname: r['hostName'] ?? '',
        link: ex ? _exLink(type) : _mrLink(type),
        downBps: num('currBytesRx')?.toDouble(),
        upBps: num('currBytesTx')?.toDouble(),
        // Older firmware counts both directions together.
        totalDown: totalDown ?? (totalUp == null ? num('totalBytes') : null),
        totalUp: totalUp,
      ));
    }
    return RouterSnapshot(DateTime.now(), clients);
  }

  static Link _mrLink(int? t) => switch (t) {
        0 => Link.wired,
        1 => Link.wifi2g,
        3 => Link.wifi5g,
        2 || 4 => Link.guest,
        _ => Link.unknown,
      };

  static Link _exLink(int? t) => switch (t) {
        0 => Link.wired,
        1 || 8 => Link.wifi2g,
        3 || 9 => Link.wifi5g,
        5 => Link.wifi6g,
        2 || 4 || 6 => Link.guest,
        _ => Link.unknown,
      };

  /// For the connection test: every field the router keeps per device, so we
  /// can see whether this model reports traffic somewhere else.
  Future<void> describeDeviceFields() async {
    final ex = variant!.protocol == TpProtocol.ex;
    for (final oid in ex ? ['DEV2_HOST_ENTRY'] : ['LAN_HOST_ENTRY', 'STAT_ENTRY']) {
      try {
        final rows = (await _query([_Act.gl(oid)]))[0];
        final keys = <String>{for (final r in rows) ...r.keys};
        log?.call('$oid: ${rows.length} entries, fields: ${keys.join(', ')}');
      } catch (e) {
        log?.call('$oid: $e');
      }
    }
  }

  /// One result list per act, each a list of objects.
  Future<List<List<Map<String, String>>>> _query(List<_Act> acts) async {
    if (variant!.protocol != TpProtocol.ex) {
      final reply = await _encryptedPost(_url('cgi_gdpr'), _mrActText(acts));
      return parseMrReply(reply, acts.length);
    }
    final out = <List<Map<String, String>>>[];
    for (final a in acts) {
      final reply = await _encryptedPost('$host/cgi_gdpr?9', jsonEncode({
        'data': {
          'stack': _zeroStack,
          'pstack': _zeroStack,
          for (final attr in a.attrs) attr: '',
        },
        'operation': a.exType,
        'oid': a.oid,
      }));
      out.add(parseExReply(reply));
    }
    return out;
  }

  static String _mrActText(List<_Act> acts) {
    final b = StringBuffer(acts.map((a) => a.mrType).join('&'))..write('\r\n');
    for (var i = 0; i < acts.length; i++) {
      final a = acts[i];
      b.write('[${a.oid}#$_zeroStack#$_zeroStack]$i,${a.attrs.length}\r\n${a.attrs.join('\r\n')}\r\n');
    }
    return b.toString();
  }

  /// Parses `[0,0,0,0,0,0]0` headed blocks of `key=value` lines. Fails on a
  /// non-zero `[error]`.
  static List<List<Map<String, String>>> parseMrReply(String reply, int count) {
    final out = List.generate(count, (_) => <Map<String, String>>[]);
    Map<String, String>? obj;
    for (final raw in const LineSplitter().convert(reply)) {
      final line = raw.trim();
      final head = RegExp(r'^\[\d+(?:,\d+){5}\](\d+)').firstMatch(line);
      if (head != null) {
        final i = int.parse(head.group(1)!);
        obj = {};
        if (i < count) out[i].add(obj);
        continue;
      }
      final err = RegExp(r'^\[error\](\d+)').firstMatch(line);
      if (err != null) {
        if (err.group(1) != '0') throw RouterException('Router error ${err.group(1)}');
        continue;
      }
      final eq = line.indexOf('=');
      if (obj != null && eq > 0) obj[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return out;
  }

  static List<Map<String, String>> parseExReply(String reply) {
    final text = reply.trim();
    if (text.isEmpty) return [];
    final json = jsonDecode(text);
    if (json is! Map) return [];
    final err = json['errorcode'] ?? json['errorCode'];
    if (err != null && '$err' != '0') throw RouterException('Router error $err');
    final data = json['data'];
    final list = data is List ? data : (data is Map ? [data] : const []);
    return [
      for (final o in list)
        if (o is Map) {for (final e in o.entries) '${e.key}': '${e.value}'},
    ];
  }

  static int? _retCode(String text) => int.tryParse(RegExp(r'\$\.ret=(\d+);').firstMatch(text)?.group(1) ?? '');

  String _sign(String data, {required bool isLogin}) => _crypto!.signature(
      isLogin: isLogin, hash: _hash!, seq: _seq, dataLength: data.length, nn: _nn!, ee: _ee!);

  Future<String> _encryptedPost(String url, String plain, {bool isLogin = false}) async {
    final enc = await _crypto!.encrypt(plain);
    final sign = _sign(enc.data, isLogin: isLogin);
    final body = 'sign=$sign\r\ndata=${enc.data}\r\n${enc.tag == null ? '' : 'tag=${enc.tag}\r\n'}';
    final (code, reply) = await _send('POST', url, body: body);
    if (code != 200) throw RouterException('HTTP $code from ${Uri.parse(url).path}');
    if (reply.trim().isEmpty) return '';
    try {
      return await _crypto!.decrypt(reply);
    } catch (_) {
      // An unencrypted reply is usually an error page or "$.ret=..." text.
      if (reply.contains(r'$.ret=')) return reply;
      throw RouterException('Could not decrypt the reply from ${Uri.parse(url).path}');
    }
  }

  String _url(String path, [Map<String, String> params = const {}]) {
    final query = {...params, '_': '${DateTime.now().millisecondsSinceEpoch}'}
        .entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return '$host/$path?$query';
  }

  Future<(int, String)> _send(String method, String url, {String? body}) async {
    for (var attempt = 0;; attempt++) {
      final req = await _http.openUrl(method, Uri.parse(url)).timeout(timeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      req.headers.set(HttpHeaders.refererHeader, '$host/');
      if (_token != null) req.headers.set('TokenID', _token!);
      if (_cookies.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
      if (body != null) {
        req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
        req.write(body);
      }
      final res = await req.close().timeout(timeout);
      for (final c in res.headers[HttpHeaders.setCookieHeader] ?? const <String>[]) {
        final pair = c.split(';').first;
        final eq = pair.indexOf('=');
        if (eq > 0) _cookies[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
      }
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      // These routers sometimes answer 500 or 406 for no reason; retrying works.
      if ((res.statusCode == 500 || res.statusCode == 406) && attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      return (res.statusCode, text);
    }
  }

  @override
  Future<void> close() async {
    if (_token != null && variant != null) {
      try {
        if (variant!.protocol == TpProtocol.ex) {
          await _encryptedPost('$host/cgi_gdpr?9',
              jsonEncode({'data': {'stack': _zeroStack, 'pstack': _zeroStack}, 'operation': 'cgi', 'oid': '/cgi/logout'}));
        } else {
          await _encryptedPost(_url('cgi_gdpr'), _mrActText([const _Act('/cgi/logout', '8', 'cgi')]));
        }
      } catch (_) {}
    }
    _token = null;
    _http.close(force: true);
  }
}
