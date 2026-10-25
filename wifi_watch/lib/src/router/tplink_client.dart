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

  /// In the order they are tried. ISP firmware (the XX530v is ex-cbc) first.
  static const all = [
    TpVariant(TpProtocol.ex, TpCipher.cbc),
    TpVariant(TpProtocol.ex, TpCipher.gcm),
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

  /// Values to set (EX firmware only).
  final Map<String, String> values;

  /// Which instance: for a table inside another, the parent's stack.
  final String stack;
  const _Act(this.oid, this.mrType, this.exType,
      [this.attrs = const [], this.values = const {}, this.stack = TplinkClient._zeroStack]);

  static _Act gl(String oid, [List<String> attrs = const [], String stack = TplinkClient._zeroStack]) =>
      _Act(oid, '5', 'gl', attrs, const {}, stack);
  static _Act get(String oid, [List<String> attrs = const []]) => _Act(oid, '1', 'go', attrs);
}

class TplinkClient implements RouterSource {
  static const _okRet = 0;
  static const _wrongPasswordRet = 71233;
  static const _zeroStack = '0,0,0,0,0,0';
  static const _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:90.0) Gecko/20100101 Firefox/90.0';

  final String host;
  /// Empty for routers whose login page asks only for a password: they log
  /// in with a fixed user name, tried in [autoUsers] order.
  final String username;
  static const autoUsers = ['user', 'admin'];

  /// The user name that worked.
  String? user;
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
  bool _exStatsSupported = true;
  bool _exAssocSupported = true;
  bool _exApDevSupported = true;
  bool _exPortsSupported = true;

  /// Last byte counters per MAC, to work out speed when the router reports
  /// only totals.
  final Map<String, (DateTime, int?, int?)> _lastCounters = {};

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

  /// False only when the router answered without a key. A router that is
  /// slow to answer may still have one, so an error counts as maybe.
  Future<bool> _probeKey(String path) async {
    for (var attempt = 1;; attempt++) {
      try {
        final (code, body) = await _send('POST', _url(path));
        final ok = code == 200 && body.contains('var nn=');
        log?.call('$path: HTTP $code, ${ok ? 'login key found' : 'no login key'}');
        return ok;
      } catch (e) {
        log?.call('$path: $e');
        if (attempt == 2) return true;
      }
    }
  }

  Future<void> _login(TpVariant v) async {
    final names = username.trim().isEmpty ? autoUsers : [username.trim()];
    for (final (i, name) in names.indexed) {
      try {
        await _loginAs(v, name);
        user = name;
        return;
      } on RouterException catch (e) {
        // A wrong user name looks like a wrong password; one failed attempt
        // per name is safe. Stop at the last.
        if (i == names.length - 1) rethrow;
        log?.call('As "$name": ${e.message}');
      }
    }
  }

  Future<void> _loginAs(TpVariant v, String username) async {
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
    log?.call('Login reply code: ${ret ?? 'none'}, cookies: ${_cookies.keys.join(', ')}, '
        'reply: ${_hideTokens(reply.replaceAll(RegExp(r'\s+'), ' ').trim())}');
    if (ret == _wrongPasswordRet) {
      throw RouterException('The router says the user name or password is wrong.', wrongPassword: true);
    }
    if (ret != _okRet) {
      throw RouterException(ret == null ? 'Unexpected login reply' : 'Login refused, code $ret');
    }

    final (code, page) = await _send('GET', _url(''));
    final found = code == 200 ? findToken(page) : null;
    variant = v;
    if (found == null) {
      final loginPage = RegExp(r'var\s+token\s*;').hasMatch(page) || page.contains('getBindStatus');
      log?.call('No session token found. Start page (HTTP $code): ${describePage(page)}');
      if (loginPage) {
        log?.call('This is the login page: the router did not keep the session. Usually the wrong login '
            'method for this router; otherwise the user name (use the local login, not a TP-Link ID email).');
      }
    }
    // Check the token with a real request. Some firmware checks only the
    // session cookie, so also try without one.
    Object? lastError;
    for (final token in [?found, '']) {
      _token = token;
      try {
        await _query([_hostsAct()]);
        lastError = null;
        if (token.isEmpty) log?.call('Requests work without a session token');
        break;
      } catch (e) {
        lastError = e;
        if (token.isNotEmpty) log?.call('Requests with the token from the start page fail: $e');
      }
    }
    if (lastError != null) {
      _token = null;
      throw RouterException('Logged in, but requests are refused ($lastError)');
    }
    log?.call('Logged in with $v');
    await _readModel();
  }

  /// The session token in the router's start page. Firmware writes it as
  /// `var token="..."`, `token = '...'` or `xxx.Token=...`.
  static String? findToken(String page) {
    for (final re in [
      RegExp(r'''var\s+token\s*=\s*["']([^"']+)["']'''),
      RegExp(r'''\btoken\s*[:=]\s*["']([0-9A-Za-z]{8,})["']''', caseSensitive: false),
      RegExp(r'''\.token\s*=\s*["']?([0-9A-Za-z]{8,})''', caseSensitive: false),
    ]) {
      final t = re.firstMatch(page)?.group(1);
      // Real tokens are random hex; a variable name has no digits.
      if (t != null && RegExp(r'\d').hasMatch(t)) return t;
    }
    return null;
  }

  _Act _hostsAct() => variant!.protocol == TpProtocol.ex
      ? _Act.gl('DEV2_HOST_ENTRY',
          ['active', 'X_TP_LanConnType', 'physAddress', 'IPAddress', 'hostName', 'X_TP_Vendor', 'layer1Interface'])
      : _Act.gl('LAN_HOST_ENTRY', ['IPAddress', 'MACAddress', 'hostName', 'X_TP_ConnType', 'active']);

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
    final rows = (await _query([_hostsAct()]))[0];
    final now = DateTime.now();

    final stats = ex ? await _exTraffic(rows) : <String, Map<String, String>>{};
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
      final s = {...?stats['ip:${r['IPAddress']}'], ...?stats[mac]};
      int? num(String k) => int.tryParse(s[k] ?? '');
      // Traffic statistics first, then Wi-Fi counters, then the device's
      // own Ethernet port. Bytes the router sends a device are its download.
      var totalDown = num('totalBytesRx') ?? num('wifiBytesDown') ?? num('portBytesDown');
      final totalUp = num('totalBytesTx') ?? num('wifiBytesUp') ?? num('portBytesUp');
      // Some statistics count both directions together; shown as download.
      totalDown ??= totalUp == null ? num('totalBytes') : null;
      var downBps = num('currBytesRx')?.toDouble();
      var upBps = num('currBytesTx')?.toDouble();
      if (totalDown != null || totalUp != null) {
        final last = _lastCounters[mac];
        if (downBps == null && last != null) {
          final secs = now.difference(last.$1).inMilliseconds / 1000;
          double? rate(int? a, int? b) => a == null || b == null || a < b || secs <= 0 ? null : (a - b) / secs;
          downBps = rate(totalDown, last.$2);
          upBps = rate(totalUp, last.$3);
        }
        _lastCounters[mac] = (now, totalDown, totalUp);
      }
      clients.add(ClientInfo(
        mac: mac,
        ip: r['IPAddress'] ?? '',
        hostname: r['hostName'] ?? '',
        vendor: r['X_TP_Vendor'] ?? '',
        link: ex ? _exLink(type) : _mrLink(type),
        downBps: downBps,
        upBps: upBps,
        totalDown: totalDown,
        totalUp: totalUp,
      ));
    }
    return RouterSnapshot(now, clients);
  }

  /// Per-device traffic fields on EX firmware, by MAC (or `ip:` address),
  /// from whichever source this router fills in:
  /// - DEV2_STAT_ENTRY: the router's traffic statistics, when turned on.
  /// - DEV2_WIFI_APDEV_ASSOCDEV + _STATS: Wi-Fi clients with byte counts
  ///   (the XX530v counts here).
  /// - DEV2_WIFI_ASSOC_DEV + _STAT: Wi-Fi clients; the XX530v leaves the
  ///   bytes at 0 while counting packets, which means "not counted".
  /// - DEV2_ETH_INTF_STATS: Ethernet ports, used for a wired device that has
  ///   its port to itself.
  /// A table the router refuses is not asked for again.
  Future<Map<String, Map<String, String>>> _exTraffic(List<Map<String, String>> hosts) async {
    final out = <String, Map<String, String>>{};
    String? macOf(Map<String, String> r) => r['macAddress'] ?? r['MACAddress'] ?? r['physAddress'];

    if (_exStatsSupported) {
      try {
        // The XX530v gives the IP as a number and counts both directions
        // in one totalBytes. Kept under both keys: the MAC here can differ
        // from the device list's (a router reports its other port).
        for (final r in (await _query([_Act.gl('DEV2_STAT_ENTRY')]))[0]) {
          final mac = macOf(r);
          final ip = ipFromStat(r['ipAddress'] ?? r['IPAddress'] ?? '');
          if (mac != null) out[normalizeMac(mac)] = {...?out[normalizeMac(mac)], ...r};
          if (ip != null) out['ip:$ip'] = {...?out['ip:$ip'], ...r};
        }
      } catch (e) {
        _exStatsSupported = false;
        log?.call('No DEV2_STAT_ENTRY: $e');
      }
    }

    Future<void> wifi(String devOid, String statOid) async {
      final devs = (await _query([_Act.gl(devOid)]))[0];
      final stats = (await _query([_Act.gl(statOid)]))[0];
      // A Stats object sits at its device's stack; else match by order.
      final byStack = {for (final x in stats) x['stack']: x};
      for (final (i, d) in devs.indexed) {
        final mac = macOf(d);
        if (mac == null) continue;
        final st = byStack[d['stack']] ?? (stats.length == devs.length ? stats[i] : const <String, String>{});
        final down = int.tryParse(st['bytesSent'] ?? ''), up = int.tryParse(st['bytesReceived'] ?? '');
        final packets = (int.tryParse(st['packetsSent'] ?? '') ?? 0) + (int.tryParse(st['packetsReceived'] ?? '') ?? 0);
        if (down == null && up == null) continue;
        if ((down ?? 0) + (up ?? 0) == 0 && packets > 0) continue;
        final entry = out.putIfAbsent(normalizeMac(mac), () => {});
        if (entry.containsKey('wifiBytesDown')) continue;
        entry.addAll({'wifiBytesDown': '${down ?? 0}', 'wifiBytesUp': '${up ?? 0}'});
      }
    }

    if (_exApDevSupported) {
      try {
        await wifi('DEV2_WIFI_APDEV_ASSOCDEV', 'DEV2_WIFI_APDEV_STATS');
      } catch (e) {
        _exApDevSupported = false;
        log?.call('No access point client counters: $e');
      }
    }
    if (_exAssocSupported) {
      try {
        await wifi('DEV2_WIFI_ASSOC_DEV', 'DEV2_WIFI_ASSOC_DEV_STAT');
      } catch (e) {
        _exAssocSupported = false;
        log?.call('No Wi-Fi association counters: $e');
      }
    }

    // Wired devices: the counters of their Ethernet port, if nothing else
    // shares that port. (A second router in router mode is one device on
    // its port, so this is all the traffic behind it.)
    final byPort = <int, List<Map<String, String>>>{};
    for (final h in hosts) {
      if (h['active'] == '0' || h['X_TP_LanConnType'] != '0') continue;
      final port = ethernetPort(h['layer1Interface'] ?? '');
      if (port != null) byPort.putIfAbsent(port, () => []).add(h);
    }
    if (_exPortsSupported && byPort.values.any((l) => l.length == 1)) {
      try {
        final ports = {
          for (final p in (await _query([_Act.gl('DEV2_ETH_INTF_STATS')]))[0])
            int.tryParse((p['stack'] ?? '').split(',').first): p,
        };
        byPort.forEach((port, hs) {
          final p = ports[port];
          final mac = macOf(hs.first);
          if (hs.length != 1 || p == null || mac == null) return;
          out.putIfAbsent(normalizeMac(mac), () => {}).addAll({
            'portBytesDown': ?p['bytesSent'],
            'portBytesUp': ?p['bytesReceived'],
          });
        });
      } catch (e) {
        _exPortsSupported = false;
        log?.call('No Ethernet port counters: $e');
      }
    }
    return out;
  }

  /// `3232235522` or `192.168.0.2` -> `192.168.0.2`.
  static String? ipFromStat(String v) {
    if (v.contains('.')) return v;
    final n = int.tryParse(v);
    if (n == null || n < 0 || n > 0xFFFFFFFF) return null;
    return [24, 16, 8, 0].map((s) => (n >> s) & 0xFF).join('.');
  }

  /// `Device.Ethernet.Interface.3.` -> 3.
  static int? ethernetPort(String layer1Interface) =>
      int.tryParse(RegExp(r'Ethernet\.Interface\.(\d+)').firstMatch(layer1Interface)?.group(1) ?? '');

  /// Whether the router's own traffic statistics are on, or null if this
  /// router has no such switch.
  Future<bool?> trafficStatsEnabled() async {
    if (variant?.protocol != TpProtocol.ex) return null;
    try {
      final rows = (await _query([_Act.get('DEV2_STAT_CFG')]))[0];
      return rows.isEmpty ? null : rows.first['enable'] == '1';
    } catch (_) {
      return null;
    }
  }

  /// Turns the router's traffic statistics on or off. Changes a router
  /// setting: only when the user asks.
  Future<void> setTrafficStats(bool on) async {
    await _query([_Act('DEV2_STAT_CFG', '2', 'so', const [], {'enable': on ? '1' : '0'})]);
    _exStatsSupported = true;
    log?.call('Router traffic statistics turned ${on ? 'on' : 'off'}');
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
  /// For EX firmware it also reads the router's list of data tables
  /// (js/oid_str.js) and looks into the ones that may hold traffic. Reads
  /// only.
  Future<void> describeDeviceFields() async {
    final ex = variant!.protocol == TpProtocol.ex;
    final oids = ex ? ['DEV2_HOST_ENTRY'] : ['LAN_HOST_ENTRY', 'STAT_ENTRY'];
    if (ex) oids.addAll(await _trafficTables());
    for (final oid in oids) {
      await _describeTable(oid);
    }
  }

  static final _historyName = RegExp(
      r'HISTORY|URL|PARENT|HOMECARE|SHIELD|BLOCK|INSIGHT|FILTER|KID|PC_PROFILE|FAMILY|AVIRA|TREND|ANTIVIRUS|'
      r'ONLINE_TIME|TIME_LIMIT');
  // Never look into tables that hold passwords or keys.
  static final _notHistory =
      RegExp(r'LTE|SMS|VOIP|VOICE|USSD|_MAX_INST$|^DEV2_(STAT|QOS|HW_QOS|IQOS)|SECURITY|USER|PASS|CERT|AUTH|DDNS|DNS_CFG');

  /// For the connection test: does this router keep any record of the
  /// sites or apps each device used (parental controls, HomeShield,
  /// DNS or URL logs)? Logs every table whose name suggests it, with a
  /// sample entry. Read operations only.
  Future<void> describeHistoryTables() async {
    if (variant!.protocol != TpProtocol.ex) return;
    final all = await _allTables();
    final pick = (all.where((n) => _historyName.hasMatch(n) && !_notHistory.hasMatch(n)).toList()..sort());
    log?.call('Looking for browsing history: ${pick.length} tables might hold it');
    for (final oid in pick.take(80)) {
      await _describeTable(oid, sample: 3);
    }
    final visits = await visitHistory();
    log?.call('Visit history entries: ${visits.length}');
    for (final v in visits.take(10)) {
      log?.call('  visit: ${describeEntry(v)}');
    }
  }

  /// Sites visited by devices in the router's parental-control profiles.
  /// The router keeps one history per profile (DEV2_PC_VISITHISTORY) and
  /// its entries one level down, read with the profile's stack. Devices in
  /// no profile have no history. Each entry is returned as the router gives
  /// it, with `profile` added.
  Future<List<Map<String, String>>> visitHistory() async {
    if (variant?.protocol != TpProtocol.ex) return const [];
    final out = <Map<String, String>>[];
    try {
      for (final h in (await _query([_Act.gl('DEV2_PC_VISITHISTORY')]))[0]) {
        if ((int.tryParse(h['entryNumberOfEntries'] ?? '') ?? 0) == 0) continue;
        final stack = h['stack'] ?? _zeroStack;
        for (final e in (await _query([_Act.gl('DEV2_PC_VISITHISTORY_ENTRY', const [], stack)]))[0]) {
          out.add({...e, 'profile': stack.split(',').first});
        }
      }
    } catch (e) {
      log?.call('Visit history: $e');
    }
    return out;
  }

  Set<String>? _tableNames;

  Future<Set<String>> _allTables() async {
    if (_tableNames != null) return _tableNames!;
    try {
      final (code, js) = await _send('GET', '$host/js/oid_str.js');
      final all = {for (final m in RegExp(r'DEV2_[A-Z0-9_]+').allMatches(js)) m[0]!};
      log?.call('js/oid_str.js: HTTP $code, ${all.length} tables');
      return _tableNames = all;
    } catch (e) {
      log?.call('js/oid_str.js: $e');
      return const {};
    }
  }

  /// The tables known to hold traffic on EX firmware. The rest were looked
  /// at on the XX530v and hold none.
  Future<List<String>> _trafficTables() async {
    final all = await _allTables();
    return [for (final n in _likelyTraffic) if (all.contains(n)) n];
  }

  /// Looked at first, with a sample of their values.
  static const _likelyTraffic = [
    'DEV2_STAT_CFG',
    'DEV2_ETH_INTF_STATS',
    'DEV2_STAT_ENTRY',
    'DEV2_WIFI_ASSOC_DEV',
    'DEV2_WIFI_ASSOC_DEV_STAT',
    'DEV2_WIFI_APDEV_ASSOCDEV',
    'DEV2_WIFI_APDEV_STATS',
    'DEV2_WIFI_APDEV_STESTATS',
    'DEV2_X_TP_ONEMESH_CLIENT',
    'DEV2_ADT_WIFI_CLIENT',
  ];

  static final _secretField = RegExp(r'pass|psk|key|secret|token|auth|cert|serial|pin', caseSensitive: false);

  /// One table entry for the log: secrets (passwords, keys...) are never
  /// shown, and long values are cut.
  static String describeEntry(Map<String, String> r) => r.entries.take(25).map((e) {
        final v = e.value;
        if (v.isNotEmpty && _secretField.hasMatch(e.key)) return '${e.key}=<hidden>';
        return '${e.key}=${v.length > 40 ? '${v.substring(0, 40)}…' : v}';
      }).join(', ');

  /// [sample]: also log this many entries' values.
  Future<void> _describeTable(String oid, {int sample = 0}) async {
    for (final act in [_Act.gl(oid), _Act.get(oid)]) {
      try {
        final rows = (await _query([act]))[0];
        final keys = <String>{for (final r in rows) ...r.keys}..remove('stack');
        log?.call('$oid (${act.exType}): ${rows.length} entries, fields: ${keys.take(40).join(', ')}');
        if (oid == 'DEV2_HOST_ENTRY' || oid == 'DEV2_ETH_INTF_STATS') {
          for (final r in rows.where((r) => r['active'] != '0').take(8)) {
            log?.call('  ${r['hostName'] ?? ''} ${r['layer1Interface'] ?? ''} ${r['X_TP_LanConnDev'] ?? ''} '
                '${r['bytesSent'] != null ? 'sent=${r['bytesSent']} received=${r['bytesReceived']} ' : ''}stack=${r['stack']}');
          }
        } else {
          final n = sample > 0 ? sample : (_likelyTraffic.contains(oid) ? 1 : 0);
          for (final r in rows.take(n)) {
            log?.call('  entry: ${describeEntry(r)}');
          }
        }
        return;
      } catch (e) {
        if (act.exType == 'go') log?.call('$oid: $e');
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
          'stack': a.stack,
          'pstack': _zeroStack,
          for (final attr in a.attrs) attr: '',
          ...a.values,
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
      b.write('[${a.oid}#${a.stack}#$_zeroStack]$i,${a.attrs.length}\r\n${a.attrs.join('\r\n')}\r\n');
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

  /// What the router's start page looks like, for the connection test, with
  /// anything after "token" hidden.
  static String _hideTokens(String t) {
    final cut = t.length > 160 ? '${t.substring(0, 160)}…' : t;
    return cut.replaceAllMapped(
        RegExp(r'[0-9A-Za-z+/=]{12,}'), (m) => RegExp(r'\d').hasMatch(m[0]!) ? '<${m[0]!.length} chars>' : m[0]!);
  }

  static String describePage(String page) {
    final title = RegExp(r'<title>([^<]*)</title>', caseSensitive: false).firstMatch(page)?.group(1)?.trim();
    // Values that look like tokens (long, with a digit) are hidden.
    String hide(String t) => _hideTokens(t);
    final hints = <String>{
      for (final m in RegExp(r'[^\n;{}]*token[^\n;{}]*', caseSensitive: false).allMatches(page))
        hide(m[0]!.trim().length > 100 ? m[0]!.trim().substring(0, 100) : m[0]!.trim()),
    }.take(15).toList();
    final scripts = [
      for (final m in RegExp(r'<script[^>]*src="([^"]+)"', caseSensitive: false).allMatches(page).take(8)) m.group(1)!,
    ];
    return '${page.length} characters, title "${title ?? ''}"'
        '${hints.isEmpty ? ', no "token" text' : ', token lines:\n    ${hints.join('\n    ')}'}'
        '${scripts.isEmpty ? '' : '\n  scripts: ${scripts.join(' ')}'}';
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
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      req.headers.set(HttpHeaders.refererHeader, '$host/');
      if (_token?.isNotEmpty ?? false) req.headers.set('TokenID', _token!);
      if (_cookies.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
      // Always with a length: router web servers drop the connection on a
      // chunked body, which is what HttpClient sends otherwise.
      final bytes = utf8.encode(body ?? '');
      req.contentLength = bytes.length;
      if (bytes.isNotEmpty) req.add(bytes);
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
