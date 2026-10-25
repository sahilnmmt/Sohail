// Which router to read and how, stored on the phone.
import 'package:shared_preferences/shared_preferences.dart';

enum SourceKind { demo, tplink }

class AppSettings {
  final SourceKind source;
  final String host;
  final String username;
  final String password;

  /// The TP-Link protocol variant that worked last time, so we skip the
  /// search (and failed logins) next time. Cleared when the router changes.
  final String? variant;
  final int pollSeconds;

  /// Warn when the whole network uses more than this in a day, in MB.
  final int? networkLimitMb;

  const AppSettings({
    this.source = SourceKind.demo,
    this.host = '192.168.0.1',
    this.username = '',
    this.password = '',
    this.variant,
    this.pollSeconds = 10,
    this.networkLimitMb,
  });

  AppSettings copyWith({
    SourceKind? source,
    String? host,
    String? username,
    String? password,
    String? Function()? variant,
    int? pollSeconds,
    int? Function()? networkLimitMb,
  }) =>
      AppSettings(
        source: source ?? this.source,
        host: host ?? this.host,
        username: username ?? this.username,
        password: password ?? this.password,
        variant: variant != null ? variant() : this.variant,
        pollSeconds: pollSeconds ?? this.pollSeconds,
        networkLimitMb: networkLimitMb != null ? networkLimitMb() : this.networkLimitMb,
      );

  bool sameRouter(AppSettings o) => source == o.source && host == o.host && username == o.username && password == o.password;
}

class SettingsStore {
  static const _prefix = 'wifiwatch.';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    return AppSettings(
      source: SourceKind.values.asNameMap()[p.getString('${_prefix}source')] ?? d.source,
      host: p.getString('${_prefix}host') ?? d.host,
      username: p.getString('${_prefix}username') ?? d.username,
      password: p.getString('${_prefix}password') ?? d.password,
      variant: p.getString('${_prefix}variant'),
      pollSeconds: p.getInt('${_prefix}poll') ?? d.pollSeconds,
      networkLimitMb: p.getInt('${_prefix}netLimitMb'),
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_prefix}source', s.source.name);
    await p.setString('${_prefix}host', s.host);
    await p.setString('${_prefix}username', s.username);
    await p.setString('${_prefix}password', s.password);
    if (s.variant == null) {
      await p.remove('${_prefix}variant');
    } else {
      await p.setString('${_prefix}variant', s.variant!);
    }
    await p.setInt('${_prefix}poll', s.pollSeconds);
    if (s.networkLimitMb == null) {
      await p.remove('${_prefix}netLimitMb');
    } else {
      await p.setInt('${_prefix}netLimitMb', s.networkLimitMb!);
    }
  }
}
