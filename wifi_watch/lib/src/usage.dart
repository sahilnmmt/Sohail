// Every device ever seen, when it was online, and the data each one used per
// day, built up from router snapshots. Saved on the phone as JSON.
import 'device_kind.dart';
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

/// A stretch of time a device was seen online without a break.
class Session {
  final DateTime start;
  DateTime end;
  Session(this.start, this.end);

  Duration get length => end.difference(start);
}

class KnownDevice {
  static const keepSessions = 200;

  final String mac;
  String? alias;
  String hostname;
  String vendor;
  String ip;
  Link link;

  /// The router it was last seen on.
  String via;
  final DateTime firstSeen;
  DateTime lastSeen;

  /// The kind you picked; null to guess from the host name.
  DeviceKind? chosenKind;

  /// You said you know this device. Devices there on the first day count as
  /// known; ones that join later are unknown until you say otherwise.
  bool known;

  /// Warn when this device uses more than this many bytes in a day.
  int? dailyLimit;

  /// Oldest first.
  final List<Session> sessions;

  KnownDevice({
    required this.mac,
    this.alias,
    required this.hostname,
    this.vendor = '',
    required this.ip,
    required this.link,
    this.via = '',
    required this.firstSeen,
    required this.lastSeen,
    this.chosenKind,
    this.known = true,
    this.dailyLimit,
    List<Session>? sessions,
  }) : sessions = sessions ?? [];

  DeviceKind get kind => chosenKind ?? guessKind(hostname, vendor);

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
        if (vendor.isNotEmpty) 'vendor': vendor,
        if (via.isNotEmpty) 'via': via,
        'ip': ip,
        'link': link.name,
        'first': firstSeen.millisecondsSinceEpoch,
        'last': lastSeen.millisecondsSinceEpoch,
        if (chosenKind != null) 'kind': chosenKind!.name,
        if (!known) 'known': false,
        if (dailyLimit != null) 'limit': dailyLimit,
        'sessions': [
          for (final x in sessions) [x.start.millisecondsSinceEpoch, x.end.millisecondsSinceEpoch],
        ],
      };

  static KnownDevice fromJson(Map<String, Object?> j) => KnownDevice(
        mac: j['mac'] as String,
        alias: j['alias'] as String?,
        hostname: j['host'] as String? ?? '',
        vendor: j['vendor'] as String? ?? '',
        via: j['via'] as String? ?? '',
        ip: j['ip'] as String? ?? '',
        link: Link.values.asNameMap()[j['link']] ?? Link.unknown,
        firstSeen: DateTime.fromMillisecondsSinceEpoch((j['first'] as num).toInt()),
        lastSeen: DateTime.fromMillisecondsSinceEpoch((j['last'] as num).toInt()),
        chosenKind: DeviceKind.values.asNameMap()[j['kind']],
        known: j['known'] != false,
        dailyLimit: (j['limit'] as num?)?.toInt(),
        sessions: [
          for (final x in (j['sessions'] as List? ?? const []))
            Session(DateTime.fromMillisecondsSinceEpoch(((x as List)[0] as num).toInt()),
                DateTime.fromMillisecondsSinceEpoch((x[1] as num).toInt())),
        ],
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
  /// A device unseen for longer than [presenceGap] starts a new session.
  List<KnownDevice> record(RouterSnapshot snap,
      {Duration maxGap = const Duration(seconds: 30), Duration presenceGap = const Duration(minutes: 5)}) {
    final joined = <KnownDevice>[];
    final seconds = _lastAt == null ? 0.0 : snap.at.difference(_lastAt!).inMilliseconds.clamp(0, maxGap.inMilliseconds) / 1000;
    final today = days.putIfAbsent(dayKey(snap.at), () => {});

    for (final c in snap.clients) {
      var d = devices[c.mac];
      if (d == null) {
        d = devices[c.mac] = KnownDevice(
            mac: c.mac, hostname: c.hostname, ip: c.ip, link: c.link, firstSeen: snap.at, lastSeen: snap.at);
        if (hasBaseline) {
          d.known = false;
          unseenNew.add(c.mac);
          joined.add(d);
        }
      }
      if (c.hostname.isNotEmpty) d.hostname = c.hostname;
      if (c.vendor.isNotEmpty) d.vendor = c.vendor;
      if (c.via.isNotEmpty) d.via = c.via;
      d
        ..ip = c.ip
        ..link = c.link
        ..lastSeen = snap.at;
      final last = d.sessions.isEmpty ? null : d.sessions.last;
      if (last != null && !snap.at.isBefore(last.end) && snap.at.difference(last.end) <= presenceGap) {
        last.end = snap.at;
      } else {
        d.sessions.add(Session(snap.at, snap.at));
        if (d.sessions.length > KnownDevice.keepSessions) d.sessions.removeAt(0);
      }

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

  /// Devices over their own daily limit today, and whether the whole network
  /// is over [networkLimit].
  ({List<KnownDevice> devices, bool network}) overLimit(DateTime now, int? networkLimit) {
    final today = days[dayKey(now)] ?? const {};
    final total = today.values.fold(0, (s, b) => s + b.total);
    return (
      devices: [
        for (final d in devices.values)
          if (d.dailyLimit != null && (today[d.mac]?.total ?? 0) > d.dailyLimit!) d,
      ],
      network: networkLimit != null && total > networkLimit,
    );
  }

  /// Time online per day for the [n] days ending with [lastDay], oldest first.
  List<(DateTime, Duration)> onlinePerDay(String mac, DateTime lastDay, int n) {
    final d = devices[mac];
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final from = DateTime(lastDay.year, lastDay.month, lastDay.day - i);
          final to = DateTime(from.year, from.month, from.day + 1);
          var total = Duration.zero;
          for (final s in d?.sessions ?? const <Session>[]) {
            final a = s.start.isAfter(from) ? s.start : from;
            final b = s.end.isBefore(to) ? s.end : to;
            if (b.isAfter(a)) total += b.difference(a);
          }
          return (from, total);
        }(),
    ];
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
