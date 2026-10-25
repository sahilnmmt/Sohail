// Which routers to read and how, stored on the phone.
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

enum RouterKind { demo, tplink, linksys }

String routerKindLabel(RouterKind k) => switch (k) {
      RouterKind.demo => 'Demo',
      RouterKind.tplink => 'TP-Link',
      RouterKind.linksys => 'Linksys',
    };

class RouterSetup {
  /// Stays the same when the router is edited.
  final String id;
  final String name;
  final RouterKind kind;
  final String host;
  final String username;
  final String password;

  /// The TP-Link protocol variant that worked last time, so we skip the
  /// search (and failed logins) next time. Cleared when the login changes.
  final String? variant;

  const RouterSetup({
    required this.id,
    this.name = '',
    this.kind = RouterKind.demo,
    this.host = '192.168.0.1',
    this.username = '',
    this.password = '',
    this.variant,
  });

  static String newId([Random? rng]) {
    final r = rng ?? Random.secure();
    return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  /// The name you gave it, else its kind and address.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    return kind == RouterKind.demo ? 'Demo network' : '${routerKindLabel(kind)} $host';
  }

  RouterSetup copyWith({
    String? name,
    RouterKind? kind,
    String? host,
    String? username,
    String? password,
    String? Function()? variant,
  }) =>
      RouterSetup(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        host: host ?? this.host,
        username: username ?? this.username,
        password: password ?? this.password,
        variant: variant != null ? variant() : this.variant,
      );

  /// Same router and login: no need to connect again.
  bool sameLogin(RouterSetup o) =>
      id == o.id && kind == o.kind && host == o.host && username == o.username && password == o.password;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'host': host,
        'user': username,
        'password': password,
        if (variant != null) 'variant': variant,
      };

  static RouterSetup fromJson(Map<String, Object?> j) => RouterSetup(
        id: j['id'] as String? ?? newId(),
        name: j['name'] as String? ?? '',
        kind: RouterKind.values.asNameMap()[j['kind']] ?? RouterKind.demo,
        host: j['host'] as String? ?? '',
        username: j['user'] as String? ?? '',
        password: j['password'] as String? ?? '',
        variant: j['variant'] as String?,
      );
}

class AppSettings {
  final List<RouterSetup> routers;
  final int pollSeconds;

  /// Warn when the whole network uses more than this in a day, in MB.
  final int? networkLimitMb;

  const AppSettings({
    this.routers = const [RouterSetup(id: 'demo')],
    this.pollSeconds = 10,
    this.networkLimitMb,
  });

  /// Only pretend routers: their history is kept apart from the real one.
  bool get isDemo => routers.every((r) => r.kind == RouterKind.demo);

  AppSettings copyWith({List<RouterSetup>? routers, int? pollSeconds, int? Function()? networkLimitMb}) =>
      AppSettings(
        routers: routers ?? this.routers,
        pollSeconds: pollSeconds ?? this.pollSeconds,
        networkLimitMb: networkLimitMb != null ? networkLimitMb() : this.networkLimitMb,
      );

  AppSettings withRouter(RouterSetup r) =>
      copyWith(routers: [for (final x in routers) x.id == r.id ? r : x]);

  /// Same routers with the same logins.
  bool sameRouters(AppSettings o) =>
      routers.length == o.routers.length &&
      [for (var i = 0; i < routers.length; i++) routers[i].sameLogin(o.routers[i])].every((same) => same);
}

class SettingsStore {
  static const _prefix = 'wifiwatch.';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    final raw = p.getString('${_prefix}routers');
    List<RouterSetup>? routers;
    if (raw != null) {
      try {
        routers = [
          for (final r in jsonDecode(raw) as List) RouterSetup.fromJson((r as Map).cast<String, Object?>()),
        ];
      } catch (_) {}
    }
    // Before several routers: one, in separate keys.
    if (routers == null && p.getString('${_prefix}source') == 'tplink') {
      routers = [
        RouterSetup(
          id: RouterSetup.newId(),
          kind: RouterKind.tplink,
          host: p.getString('${_prefix}host') ?? '192.168.0.1',
          username: p.getString('${_prefix}username') ?? '',
          password: p.getString('${_prefix}password') ?? '',
          variant: p.getString('${_prefix}variant'),
        ),
      ];
    }
    return AppSettings(
      routers: routers == null || routers.isEmpty ? d.routers : routers,
      pollSeconds: p.getInt('${_prefix}poll') ?? d.pollSeconds,
      networkLimitMb: p.getInt('${_prefix}netLimitMb'),
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_prefix}routers', jsonEncode([for (final r in s.routers) r.toJson()]));
    for (final old in ['source', 'host', 'username', 'password', 'variant']) {
      await p.remove('$_prefix$old');
    }
    await p.setInt('${_prefix}poll', s.pollSeconds);
    if (s.networkLimitMb == null) {
      await p.remove('${_prefix}netLimitMb');
    } else {
      await p.setInt('${_prefix}netLimitMb', s.networkLimitMb!);
    }
  }
}
