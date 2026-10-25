// Polls the router while the app is open and keeps the usage history.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_kind.dart';
import 'router/demo_source.dart';
import 'router/router_source.dart';
import 'router/tplink_client.dart';
import 'settings.dart';
import 'usage.dart';

enum MonitorState { idle, connecting, ok, error }

class Monitor extends ChangeNotifier {
  static const _saveEvery = Duration(minutes: 1);

  final RouterSource Function(AppSettings) _makeSource;

  /// Called when a TP-Link router's protocol variant is found, to remember it.
  void Function(String variant)? onVariantFound;

  AppSettings _settings = const AppSettings();
  RouterSource? _source;
  Timer? _timer;
  bool _polling = false;
  bool _running = false;
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);

  MonitorState state = MonitorState.idle;
  String? error;
  String sourceName = '';
  DateTime? updatedAt;
  UsageData usage = UsageData();

  /// Online devices from the last snapshot, by MAC.
  Map<String, ClientInfo> live = {};

  Monitor({RouterSource Function(AppSettings)? makeSource}) : _makeSource = makeSource ?? defaultSource;

  static RouterSource defaultSource(AppSettings s) => switch (s.source) {
        SourceKind.demo => DemoSource(),
        SourceKind.tplink => TplinkClient(
            host: s.host, username: s.username, password: s.password, variant: TpVariant.parse(s.variant)),
      };

  static String _usageKey(SourceKind k) => 'wifiwatch.usage.${k.name}';

  /// Starts (or restarts, for new settings) polling.
  Future<void> start(AppSettings s) async {
    if (_source != null && s.sameRouter(_settings)) {
      _settings = s;
      _schedule();
      return;
    }
    // Saves the history under the old settings' source.
    await stop();
    _settings = s;
    usage = await _loadUsage(s.source);
    live = {};
    updatedAt = null;
    error = null;
    _source = _makeSource(s);
    sourceName = _source!.name;
    state = MonitorState.connecting;
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
    final source = _source;
    if (source == null) return;
    _source = null;
    await save();
    await source.close();
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
    final source = _source;
    if (source == null || _polling) return;
    _polling = true;
    try {
      final snap = await source.fetch();
      if (!identical(source, _source)) return;
      usage.record(snap,
          maxGap: Duration(seconds: _settings.pollSeconds * 3),
          presenceGap: Duration(seconds: max(300, _settings.pollSeconds * 3)));
      live = {for (final c in snap.clients) c.mac: c};
      updatedAt = snap.at;
      state = MonitorState.ok;
      error = null;
      sourceName = source.name;
      if (source is TplinkClient && source.variant != null && source.variant!.id != _settings.variant) {
        _settings = _settings.copyWith(variant: () => source.variant!.id);
        onVariantFound?.call(source.variant!.id);
      }
      if (snap.at.difference(_lastSave) > _saveEvery) await save();
    } catch (e) {
      if (!identical(source, _source)) return;
      state = MonitorState.error;
      error = '$e';
      live = {};
      // A wrong password stays wrong; don't lock the router's login.
      if (e is RouterException && e.wrongPassword) {
        _running = false;
        _timer?.cancel();
      }
    } finally {
      _polling = false;
      notifyListeners();
    }
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

  Future<UsageData> _loadUsage(SourceKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_usageKey(k));
      if (raw != null) return UsageData.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (e) {
      debugPrint('Usage history unreadable, starting again: $e');
    }
    return UsageData();
  }

  Future<void> save() async {
    _lastSave = DateTime.now();
    final p = await SharedPreferences.getInstance();
    await p.setString(_usageKey(_settings.source), jsonEncode(usage.toJson()));
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
