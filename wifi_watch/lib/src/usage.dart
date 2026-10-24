// Every device ever seen and the data each one used per day, built up from
// router snapshots. Saved on the phone as JSON.
import 'router/router_source.dart';

class Bytes {
  final int down;
  final int up;
  const Bytes(this.down, this.up);
  static const zero = Bytes(0, 0);

  int get total => down + up;
  Bytes operator +(Bytes o) => Bytes(down + o.down, up + o.up);

  List<int> toJson() => [down, up];
  static Bytes fromJson(Object? j) => j is List && j.length == 2 ? Bytes((j[0] as num).toInt(), (j[1] as num).toInt()) : zero;
}

class KnownDevice {
  final String mac;
  String? alias;
  String hostname;
  String ip;
  Link link;
  final DateTime firstSeen;
  DateTime lastSeen;

  KnownDevice({
    required this.mac,
    this.alias,
    required this.hostname,
    required this.ip,
    required this.link,
    required this.firstSeen,
    required this.lastSeen,
  });

  /// The name you gave it, else the name it gave the router, else its MAC.
  String get displayName {
    final a = alias?.trim() ?? '';
    if (a.isNotEmpty) return a;
    return hostname.trim().isNotEmpty ? hostname : mac;
  }

  Map<String, Object?> toJson() => {
        'mac': mac,
        if (alias != null) 'alias': alias,
        'host': hostname,
        'ip': ip,
        'link': link.name,
        'first': firstSeen.millisecondsSinceEpoch,
        'last': lastSeen.millisecondsSinceEpoch,
      };

  static KnownDevice fromJson(Map<String, Object?> j) => KnownDevice(
        mac: j['mac'] as String,
        alias: j['alias'] as String?,
        hostname: j['host'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        link: Link.values.asNameMap()[j['link']] ?? Link.unknown,
        firstSeen: DateTime.fromMillisecondsSinceEpoch((j['first'] as num).toInt()),
        lastSeen: DateTime.fromMillisecondsSinceEpoch((j['last'] as num).toInt()),
      );
}

String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

class UsageData {
  static const keepDays = 62;

  final Map<String, KnownDevice> devices;

  /// Day key -> MAC -> bytes used that day.
  final Map<String, Map<String, Bytes>> days;

  /// Devices that joined since you last looked.
  final Set<String> unseenNew;

  /// False until the first snapshot. Devices in the first snapshot are not
  /// "new": they were already there.
  bool hasBaseline;

  // Last counters and time, to turn the next snapshot into a difference.
  final Map<String, (int?, int?)> _lastTotals = {};
  DateTime? _lastAt;

  UsageData({Map<String, KnownDevice>? devices, Map<String, Map<String, Bytes>>? days, Set<String>? unseenNew, this.hasBaseline = false})
      : devices = devices ?? {},
        days = days ?? {},
        unseenNew = unseenNew ?? {};

  /// Adds a snapshot. Byte counters from the router are exact. Without them
  /// the live speed is multiplied by the time since the last snapshot, capped
  /// at [maxGap] so time the app was closed is not guessed at.
  /// Returns the devices seen for the first time.
  List<KnownDevice> record(RouterSnapshot snap, {Duration maxGap = const Duration(seconds: 30)}) {
    final joined = <KnownDevice>[];
    final seconds = _lastAt == null ? 0.0 : snap.at.difference(_lastAt!).inMilliseconds.clamp(0, maxGap.inMilliseconds) / 1000;
    final today = days.putIfAbsent(dayKey(snap.at), () => {});

    for (final c in snap.clients) {
      var d = devices[c.mac];
      if (d == null) {
        d = devices[c.mac] = KnownDevice(
            mac: c.mac, hostname: c.hostname, ip: c.ip, link: c.link, firstSeen: snap.at, lastSeen: snap.at);
        if (hasBaseline) {
          unseenNew.add(c.mac);
          joined.add(d);
        }
      }
      if (c.hostname.isNotEmpty) d.hostname = c.hostname;
      d
        ..ip = c.ip
        ..link = c.link
        ..lastSeen = snap.at;

      final used = _used(c, seconds);
      if (used.total > 0) today[c.mac] = (today[c.mac] ?? Bytes.zero) + used;
      _lastTotals[c.mac] = (c.totalDown, c.totalUp);
    }
    _lastAt = snap.at;
    hasBaseline = true;
    _prune(snap.at);
    return joined;
  }

  Bytes _used(ClientInfo c, double seconds) {
    final last = _lastTotals[c.mac];
    int counted(int? now, int? before) {
      if (now == null || before == null) return 0;
      // A smaller counter means the router restarted counting.
      return now >= before ? now - before : now;
    }

    if (c.totalDown != null || c.totalUp != null) {
      return last == null ? Bytes.zero : Bytes(counted(c.totalDown, last.$1), counted(c.totalUp, last.$2));
    }
    return Bytes(((c.downBps ?? 0) * seconds).round(), ((c.upBps ?? 0) * seconds).round());
  }

  void _prune(DateTime now) {
    final oldest = dayKey(now.subtract(const Duration(days: keepDays)));
    days.removeWhere((k, _) => k.compareTo(oldest) < 0);
  }

  Bytes usage(String mac, DateTime day) => days[dayKey(day)]?[mac] ?? Bytes.zero;

  /// Per device, summed over the [n] days ending with [lastDay].
  Map<String, Bytes> byDevice(DateTime lastDay, int n) {
    final out = <String, Bytes>{};
    for (var i = 0; i < n; i++) {
      final day = days[dayKey(DateTime(lastDay.year, lastDay.month, lastDay.day - i))];
      day?.forEach((mac, b) => out[mac] = (out[mac] ?? Bytes.zero) + b);
    }
    return out;
  }

  /// Oldest first: the [n] days ending with [lastDay], for one device or all.
  List<(DateTime, Bytes)> daily(DateTime lastDay, int n, {String? mac}) => [
        for (var i = n - 1; i >= 0; i--)
          () {
            final day = DateTime(lastDay.year, lastDay.month, lastDay.day - i);
            final m = days[dayKey(day)] ?? const {};
            final b = mac != null ? (m[mac] ?? Bytes.zero) : m.values.fold(Bytes.zero, (a, b) => a + b);
            return (day, b);
          }(),
      ];

  Map<String, Object?> toJson() => {
        'v': 1,
        'baseline': hasBaseline,
        'devices': [for (final d in devices.values) d.toJson()],
        'days': {
          for (final e in days.entries) e.key: {for (final u in e.value.entries) u.key: u.value.toJson()},
        },
        'new': unseenNew.toList(),
      };

  static UsageData fromJson(Map<String, Object?> j) {
    final devices = <String, KnownDevice>{};
    for (final d in (j['devices'] as List? ?? const [])) {
      final k = KnownDevice.fromJson((d as Map).cast<String, Object?>());
      devices[k.mac] = k;
    }
    final days = <String, Map<String, Bytes>>{};
    (j['days'] as Map? ?? const {}).forEach((day, m) {
      days['$day'] = {for (final e in (m as Map).entries) '${e.key}': Bytes.fromJson(e.value)};
    });
    return UsageData(
      devices: devices,
      days: days,
      unseenNew: {for (final m in (j['new'] as List? ?? const [])) '$m'},
      hasBaseline: j['baseline'] == true,
    );
  }
}
