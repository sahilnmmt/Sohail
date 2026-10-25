// Polls the routers while the app is open and keeps the usage history.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_kind.dart';
import 'router/demo_source.dart';
import 'router/linksys_client.dart';
import 'router/router_source.dart';
import 'router/tplink_client.dart';
import 'settings.dart';
import 'usage.dart';

enum MonitorState { idle, connecting, ok, error }

/// One router's connection.
class RouterStatus {
  final RouterSetup config;
  final RouterSource source;
  MonitorState state = MonitorState.connecting;
  String? error;
  DateTime? updatedAt;
  int online = 0;

  /// After a wrong password: not asked again, so the router does not lock
  /// its login.
  bool stopped = false;

  RouterStatus(this.config, this.source);

  String get name => config.displayName;
}

class Monitor extends ChangeNotifier {
  static const _saveEvery = Duration(minutes: 1);

  final RouterSource Function(RouterSetup) _makeSource;

  /// Called when a TP-Link router's protocol variant and user name are
  /// found, to remember them.
  void Function(String routerId, String variant, String user)? onVariantFound;

  AppSettings _settings = const AppSettings();
  List<RouterStatus> routers = [];
  Timer? _timer;
  bool _polling = false;
  bool _running = false;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime? updatedAt;
  UsageData usage = UsageData();

  /// Online devices from the last poll of all routers, by MAC.
  Map<String, ClientInfo> live = {};

  Monitor({RouterSource Function(RouterSetup)? makeSource}) : _makeSource = makeSource ?? defaultSource;

  static RouterSource defaultSource(RouterSetup r) => switch (r.kind) {
        RouterKind.demo => DemoSource(),
        RouterKind.tplink => TplinkClient(
            host: r.host, username: r.username, password: r.password, variant: TpVariant.parse(r.variant)),
        RouterKind.linksys => LinksysClient(host: r.host, username: r.username, password: r.password),
      };

  bool get multipleRouters => routers.length > 1;

  /// All routers together: ok if any answered, error if none did.
  MonitorState get state {
    if (routers.isEmpty) return MonitorState.idle;
    if (routers.any((r) => r.state == MonitorState.ok)) return MonitorState.ok;
    if (routers.every((r) => r.state == MonitorState.error)) return MonitorState.error;
    return MonitorState.connecting;
  }

  /// The routers that failed, one line each.
  String? get error {
    final failed = routers.where((r) => r.state == MonitorState.error).toList();
    if (failed.isEmpty) return null;
    if (!multipleRouters) return failed.single.error;
    return failed.map((r) => '${r.name}: ${r.error}').join('\n');
  }

  String get sourceName {
    if (routers.isEmpty) return '';
    if (!multipleRouters) {
      final r = routers.single;
      return r.config.name.trim().isNotEmpty ? r.config.name.trim() : r.source.name;
    }
    return '${routers.length} routers';
  }

  static String _usageKey(AppSettings s) => 'wifiwatch.usage.${s.isDemo ? 'demo' : 'tplink'}';

  /// Starts (or restarts, for new settings) polling.
  Future<void> start(AppSettings s) async {
    if (routers.isNotEmpty && s.sameRouters(_settings)) {
      _settings = s;
      _schedule();
      notifyListeners();
      return;
    }
    // Saves the history under the old settings.
    await stop();
    _settings = s;
    usage = await _loadUsage(s);
    live = {};
    updatedAt = null;
    routers = [for (final r in s.routers) RouterStatus(r, _makeSource(r))];
    notifyListeners();
    _running = true;
    _schedule();
    await poll();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer.periodic(Duration(seconds: _settings.pollSeconds), (_) => poll());
  }

  /// Pauses polling, e.g. while the app is in the background.
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    final old = routers;
    if (old.isEmpty) return;
    routers = [];
    await save();
    for (final r in old) {
      await r.source.close();
    }
  }

  /// Connects again from scratch, e.g. after an error.
  Future<void> retry() async {
    await stop();
    await start(_settings);
  }

  Future<void> resume() async {
    if (_running) return;
    await start(_settings.copyWith());
  }

  Future<void> poll() async {
    final current = routers;
    if (current.isEmpty || _polling) return;
    _polling = true;
    try {
      final results = await Future.wait([
        for (final r in current)
          if (r.stopped) Future<RouterSnapshot?>.value(null) else _fetch(r),
      ]);
      if (!identical(current, routers)) return;
      final snaps = results.whereType<RouterSnapshot>().toList();
      if (snaps.isEmpty) {
        live = {};
        return;
      }
      final merged = mergeSnapshots([
        for (final (i, s) in results.indexed)
          if (s != null) (current[i].name, s),
      ]);
      usage.record(merged,
          maxGap: Duration(seconds: _settings.pollSeconds * 3),
          presenceGap: Duration(seconds: max(300, _settings.pollSeconds * 3)));
      live = {for (final c in merged.clients) c.mac: c};
      updatedAt = merged.at;
      if (merged.at.difference(_lastSave) > _saveEvery) await save();
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<RouterSnapshot?> _fetch(RouterStatus r) async {
    try {
      final snap = await r.source.fetch();
      r
        ..state = MonitorState.ok
        ..error = null
        ..updatedAt = snap.at
        ..online = snap.clients.length;
      final s = r.source;
      if (s is TplinkClient &&
          s.variant != null &&
          (s.variant!.id != r.config.variant || r.config.username.trim().isEmpty)) {
        // Remember the user name too, so an automatic search does not cost
        // a failed login every time.
        final found = r.config.copyWith(variant: () => s.variant!.id, username: s.user);
        _settings = _settings.withRouter(found);
        onVariantFound?.call(r.config.id, s.variant!.id, s.user ?? r.config.username);
      }
      return snap;
    } catch (e) {
      r
        ..state = MonitorState.error
        ..error = '$e';
      if (e is RouterException && e.wrongPassword) r.stopped = true;
      return null;
    }
  }

  /// One list from several routers, each device once and marked with the
  /// router it came from. A device two routers see (a second router is a
  /// device of the first) is taken from the one that measures its traffic,
  /// else from the first router.
  static RouterSnapshot mergeSnapshots(List<(String, RouterSnapshot)> snaps) {
    final byMac = <String, ClientInfo>{};
    for (final (router, snap) in snaps) {
      for (final c in snap.clients) {
        final seen = byMac[c.mac];
        if (seen == null || (!seen.hasTraffic && c.hasTraffic)) byMac[c.mac] = c.withVia(router);
      }
    }
    final at = snaps.map((s) => s.$2.at).reduce((a, b) => a.isAfter(b) ? a : b);
    return RouterSnapshot(at, byMac.values.toList());
  }

  void rename(String mac, String alias) {
    final d = usage.devices[mac];
    if (d == null) return;
    d.alias = alias.trim().isEmpty ? null : alias.trim();
    notifyListeners();
    save();
  }

  void _changeDevice(String mac, void Function(KnownDevice d) change) {
    final d = usage.devices[mac];
    if (d == null) return;
    change(d);
    notifyListeners();
    save();
  }

  void setKind(String mac, DeviceKind? kind) => _changeDevice(mac, (d) => d.chosenKind = kind);

  void setKnown(String mac, bool known) => _changeDevice(mac, (d) {
        d.known = known;
        if (known) usage.unseenNew.remove(mac);
      });

  void setDailyLimit(String mac, int? bytes) => _changeDevice(mac, (d) => d.dailyLimit = bytes);

  /// Marks every new device as known.
  void markNewKnown() {
    for (final mac in usage.unseenNew) {
      usage.devices[mac]?.known = true;
    }
    markNewSeen();
  }

  int? get networkLimitBytes => _settings.networkLimitMb == null ? null : _settings.networkLimitMb! * 1000000;

  void markNewSeen() {
    if (usage.unseenNew.isEmpty) return;
    usage.unseenNew.clear();
    notifyListeners();
    save();
  }

  Future<void> forgetHistory() async {
    usage = UsageData();
    notifyListeners();
    await save();
  }

  Future<UsageData> _loadUsage(AppSettings s) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_usageKey(s));
      if (raw != null) return UsageData.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (e) {
      debugPrint('Usage history unreadable, starting again: $e');
    }
    return UsageData();
  }

  Future<void> save() async {
    _lastSave = DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setString(_usageKey(_settings), jsonEncode(usage.toJson()));
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
