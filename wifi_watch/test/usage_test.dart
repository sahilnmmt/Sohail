import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_watch/src/device_kind.dart';
import 'package:wifi_watch/src/router/router_source.dart';
import 'package:wifi_watch/src/usage.dart';

ClientInfo _c(String mac, {int? down, int? up, double? downBps, double? upBps}) => ClientInfo(
    mac: mac, ip: '10.0.0.2', hostname: 'h-$mac', link: Link.wifi5g,
    totalDown: down, totalUp: up, downBps: downBps, upBps: upBps);

void main() {
  final t0 = DateTime(2026, 10, 24, 12);

  test('router counters: the difference between snapshots is counted', () {
    final u = UsageData();
    u.record(RouterSnapshot(t0, [_c('A', down: 1000, up: 100)]));
    u.record(RouterSnapshot(t0.add(const Duration(seconds: 10)), [_c('A', down: 5000, up: 300)]));
    // Counters keep going while the app is closed; that is counted too.
    u.record(RouterSnapshot(t0.add(const Duration(hours: 1)), [_c('A', down: 9000, up: 400)]));
    expect(u.usage('A', t0).down, 8000);
    expect(u.usage('A', t0).up, 300);
  });

  test('a counter that goes down means the router restarted counting', () {
    final u = UsageData();
    u.record(RouterSnapshot(t0, [_c('A', down: 5000, up: 0)]));
    u.record(RouterSnapshot(t0.add(const Duration(seconds: 10)), [_c('A', down: 300, up: 0)]));
    expect(u.usage('A', t0).down, 300);
  });

  test('live speeds: speed times time, with long gaps capped', () {
    final u = UsageData();
    u.record(RouterSnapshot(t0, [_c('A', downBps: 100, upBps: 10)]));
    u.record(RouterSnapshot(t0.add(const Duration(seconds: 10)), [_c('A', downBps: 100, upBps: 10)]));
    expect(u.usage('A', t0), isA<Bytes>().having((b) => b.down, 'down', 1000).having((b) => b.up, 'up', 100));
    // The app was closed for an hour: only maxGap is counted.
    u.record(RouterSnapshot(t0.add(const Duration(hours: 1)), [_c('A', downBps: 100)]), maxGap: const Duration(seconds: 30));
    expect(u.usage('A', t0).down, 4000);
  });

  test('devices in the first snapshot are not new; later ones are', () {
    final u = UsageData();
    expect(u.record(RouterSnapshot(t0, [_c('A'), _c('B')])), isEmpty);
    expect(u.unseenNew, isEmpty);
    final joined = u.record(RouterSnapshot(t0.add(const Duration(minutes: 1)), [_c('A'), _c('C')]));
    expect(joined.map((d) => d.mac), ['C']);
    expect(u.unseenNew, {'C'});
    expect(u.devices['A']!.known, isTrue);
    expect(u.devices['C']!.known, isFalse);
    expect(u.devices['B']!.lastSeen, t0);
    expect(u.devices['A']!.lastSeen, t0.add(const Duration(minutes: 1)));
  });

  test('usage by day and by device', () {
    final u = UsageData(hasBaseline: true);
    u.days['2026-10-23'] = {'A': const Bytes(100, 1), 'B': const Bytes(50, 0)};
    u.days['2026-10-24'] = {'A': const Bytes(10, 0)};
    final days = u.daily(t0, 3);
    expect(days.map((d) => d.$2.total), [0, 151, 10]);
    expect(days.first.$1, DateTime(2026, 10, 22));
    expect(u.daily(t0, 2, mac: 'B').map((d) => d.$2.total), [50, 0]);
    expect(u.byDevice(t0, 2)['A']!.total, 111);
    expect(u.byDevice(t0, 1)['B'], isNull);
  });

  test('old days are dropped', () {
    final u = UsageData();
    u.days['2026-01-01'] = {'A': const Bytes(1, 1)};
    u.record(RouterSnapshot(t0, [_c('A')]));
    expect(u.days.containsKey('2026-01-01'), isFalse);
  });

  test('saves and loads', () {
    final u = UsageData();
    u.record(RouterSnapshot(t0, [_c('A', down: 0, up: 0)]));
    u.record(RouterSnapshot(t0.add(const Duration(seconds: 5)), [_c('A', down: 70, up: 7), _c('B')]));
    u.devices['A']!
      ..alias = "Mom's phone"
      ..chosenKind = DeviceKind.tablet
      ..dailyLimit = 5000;
    final back = UsageData.fromJson(u.toJson());
    expect(back.devices['A']!.displayName, "Mom's phone");
    expect(back.devices['B']!.displayName, 'h-B');
    expect(back.devices['A']!.link, Link.wifi5g);
    expect(back.usage('A', t0).total, 77);
    expect(back.unseenNew, {'B'});
    expect(back.hasBaseline, isTrue);
    expect(back.devices['A']!.kind, DeviceKind.tablet);
    expect(back.devices['A']!.dailyLimit, 5000);
    expect(back.devices['B']!.known, isFalse);
    expect(back.devices['A']!.sessions.single.length, const Duration(seconds: 5));
  });

  test('visits: seen again soon continues, after a gap starts a new one', () {
    final u = UsageData();
    for (final m in [0, 1, 2, 3]) {
      u.record(RouterSnapshot(t0.add(Duration(minutes: m)), [_c('A')]));
    }
    u.record(RouterSnapshot(t0.add(const Duration(minutes: 30)), [_c('A')]));
    final s = u.devices['A']!.sessions;
    expect(s, hasLength(2));
    expect(s[0].length, const Duration(minutes: 3));
    expect(s[1].start, t0.add(const Duration(minutes: 30)));
    expect(u.onlinePerDay('A', t0, 2).map((d) => d.$2), [Duration.zero, const Duration(minutes: 3)]);
  });

  test('time online is split at midnight', () {
    final u = UsageData();
    final late = DateTime(2026, 10, 23, 23, 50);
    for (var m = 0; m <= 20; m += 2) {
      u.record(RouterSnapshot(late.add(Duration(minutes: m)), [_c('A')]));
    }
    expect(u.onlinePerDay('A', DateTime(2026, 10, 24), 2).map((d) => d.$2),
        [const Duration(minutes: 10), const Duration(minutes: 10)]);
  });

  test('daily limits', () {
    final u = UsageData(hasBaseline: true);
    u.days[dayKey(t0)] = {'A': const Bytes(900, 200), 'B': const Bytes(10, 0)};
    u.devices['A'] = KnownDevice(mac: 'A', hostname: '', ip: '', link: Link.wired, firstSeen: t0, lastSeen: t0, dailyLimit: 1000);
    u.devices['B'] = KnownDevice(mac: 'B', hostname: '', ip: '', link: Link.wired, firstSeen: t0, lastSeen: t0, dailyLimit: 1000);
    final over = u.overLimit(t0, 2000);
    expect(over.devices.map((d) => d.mac), ['A']);
    expect(over.network, isFalse);
    expect(u.overLimit(t0, 1000).network, isTrue);
    expect(u.overLimit(t0, null).network, isFalse);
  });
}
