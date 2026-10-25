// Talks to a Linksys Smart Wi-Fi router (EA, MR, MX and Velop models) through
// JNAP, the local JSON interface its own web page and app use: one POST to
// /JNAP/ per action, the action named in X-JNAP-Action and the admin login
// in X-JNAP-Authorization.
//
// JNAP lists devices and how they connect, but not how much data each used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'router_source.dart';
import 'tplink_client.dart' show RouterException;

class LinksysClient implements RouterSource {
  static const _jnap = 'http://linksys.com/jnap/';

  final String host;
  final String username;
  final String password;
  final Duration timeout;
  final void Function(String line)? log;

  /// The model, once read.
  String? model;

  final HttpClient _http = HttpClient();

  LinksysClient({
    required String host,
    this.username = 'admin',
    required this.password,
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
  String get name => model == null ? 'Linksys router' : 'Linksys $model';

  /// Calls one JNAP action and returns its `output`.
  Future<Map<String, Object?>> call(String action, [Map<String, Object?> input = const {}]) async {
    final req = await _http.postUrl(Uri.parse('$host/JNAP/')).timeout(timeout);
    final body = utf8.encode(jsonEncode(input));
    req.headers.set('X-JNAP-Action', '$_jnap$action');
    req.headers.set('X-JNAP-Authorization',
        'Basic ${base64.encode(utf8.encode('${username.trim().isEmpty ? 'admin' : username.trim()}:$password'))}');
    req.headers.contentType = ContentType.json;
    // With a length: small router web servers drop chunked bodies.
    req.contentLength = body.length;
    req.add(body);
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode != 200) throw RouterException('HTTP ${res.statusCode} from $action');
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw RouterException('$host did not answer like a Linksys Smart Wi-Fi router');
    }
    if (json is! Map) throw RouterException('Unexpected reply to $action');
    final result = '${json['result']}';
    if (result == '_ErrorUnauthorized') {
      throw RouterException('The Linksys router says the password is wrong.', wrongPassword: true);
    }
    if (result != 'OK') throw RouterException('Linksys $action: $result');
    return (json['output'] as Map?)?.cast<String, Object?>() ?? const {};
  }

  /// For the connection test, when JNAP is missing: what the web page at
  /// the address says about the router (server, login realm, title), to
  /// tell which kind of Linksys it is.
  Future<void> describeWebPage() async {
    try {
      final req = await _http.getUrl(Uri.parse('$host/')).timeout(timeout);
      final res = await req.close().timeout(timeout);
      final page = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
      final title = RegExp(r'<title>([^<]*)</title>', caseSensitive: false).firstMatch(page)?.group(1)?.trim();
      log?.call('Web page: HTTP ${res.statusCode}, server "${res.headers.value('server') ?? ''}", '
          'login "${res.headers.value('www-authenticate') ?? ''}", title "${title ?? ''}", ${page.length} characters');
      final scripts = [
        for (final m in RegExp(r'''(?:src|href|action)=["']([^"']+)["']''', caseSensitive: false).allMatches(page).take(12))
          m.group(1)!,
      ];
      if (scripts.isNotEmpty) log?.call('  links: ${scripts.join(' ')}');
    } catch (e) {
      log?.call('Web page: $e');
    }
  }

  /// Logs in by asking for the model, which needs the password.
  Future<void> connect() async {
    final info = await call('core/GetDeviceInfo');
    model = '${info['modelNumber'] ?? ''}'.trim();
    if (model!.isEmpty) model = null;
    log?.call('Linksys ${info['modelNumber']}, firmware ${info['firmwareVersion']}');
  }

  @override
  Future<RouterSnapshot> fetch() async {
    if (model == null) await connect();
    final devices = (await call('devicelist/GetDevices'))['devices'] as List? ?? const [];

    // How each device is connected: band for Wi-Fi, nothing for a cable.
    final links = <String, Link>{};
    try {
      final conns = (await call('networkconnections/GetNetworkConnections'))['connections'] as List? ?? const [];
      for (final c in conns.whereType<Map>()) {
        final mac = '${c['macAddress'] ?? ''}';
        final wireless = c['wireless'];
        links[normalizeMac(mac)] = wireless is Map ? _band('${wireless['band']}') : Link.wired;
      }
    } catch (e) {
      log?.call('No connection details: $e');
    }

    final clients = <ClientInfo>[];
    for (final d in devices.whereType<Map>()) {
      // The router lists itself and its mesh nodes as authorities.
      if (d['isAuthority'] == true) continue;
      final conns = (d['connections'] as List? ?? const []).whereType<Map>().toList();
      if (conns.isEmpty) continue; // known but offline
      final mac = normalizeMac('${conns.first['macAddress'] ?? ''}');
      if (mac.isEmpty) continue;
      final model = d['model'] is Map ? d['model'] as Map : const {};
      clients.add(ClientInfo(
        mac: mac,
        ip: '${conns.first['ipAddress'] ?? ''}',
        hostname: _name(d),
        vendor: '${model['manufacturer'] ?? ''}',
        link: links[mac] ?? Link.unknown,
      ));
    }
    return RouterSnapshot(DateTime.now(), clients);
  }

  /// The name set in the Linksys app, else the one the device gave.
  static String _name(Map d) {
    for (final p in (d['properties'] as List? ?? const []).whereType<Map>()) {
      if (p['name'] == 'userDeviceName' && '${p['value']}'.trim().isNotEmpty) return '${p['value']}'.trim();
    }
    return '${d['friendlyName'] ?? ''}'.trim();
  }

  static Link _band(String band) => switch (band.toLowerCase()) {
        '2.4ghz' => Link.wifi2g,
        '5ghz' || '5ghz-1' || '5ghz-2' => Link.wifi5g,
        '6ghz' => Link.wifi6g,
        _ => Link.unknown,
      };

  @override
  Future<void> close() async => _http.close(force: true);
}
