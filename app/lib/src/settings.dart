// The user's profile and message-server settings, stored on the phone.
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'messaging/message.dart';

class AppSettings {
  final String displayName;
  final String group;
  final String host;
  final int port;
  final bool tls;
  final String username;
  final String password;
  final String clientId;

  const AppSettings({
    required this.displayName,
    required this.group,
    required this.host,
    required this.port,
    required this.tls,
    required this.username,
    required this.password,
    required this.clientId,
  });

  bool get isComplete => host.trim().isNotEmpty && isValidId(group) && port > 0 && port < 65536;

  AppSettings copyWith({
    String? displayName,
    String? group,
    String? host,
    int? port,
    bool? tls,
    String? username,
    String? password,
  }) =>
      AppSettings(
        displayName: displayName ?? this.displayName,
        group: group ?? this.group,
        host: host ?? this.host,
        port: port ?? this.port,
        tls: tls ?? this.tls,
        username: username ?? this.username,
        password: password ?? this.password,
        clientId: clientId,
      );
}

class SettingsStore {
  static const _prefix = 'sohail.';

  static String newClientId([Random? rng]) {
    final r = rng ?? Random.secure();
    return 'app-${List.generate(6, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    var clientId = p.getString('${_prefix}clientId');
    if (clientId == null || !isValidId(clientId)) {
      clientId = newClientId();
      await p.setString('${_prefix}clientId', clientId);
    }
    return AppSettings(
      displayName: p.getString('${_prefix}name') ?? 'Me',
      group: p.getString('${_prefix}group') ?? 'family',
      host: p.getString('${_prefix}host') ?? '',
      port: p.getInt('${_prefix}port') ?? 1883,
      tls: p.getBool('${_prefix}tls') ?? false,
      username: p.getString('${_prefix}username') ?? '',
      password: p.getString('${_prefix}password') ?? '',
      clientId: clientId,
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('${_prefix}name', s.displayName);
    await p.setString('${_prefix}group', s.group);
    await p.setString('${_prefix}host', s.host.trim());
    await p.setInt('${_prefix}port', s.port);
    await p.setBool('${_prefix}tls', s.tls);
    await p.setString('${_prefix}username', s.username);
    await p.setString('${_prefix}password', s.password);
  }
}
