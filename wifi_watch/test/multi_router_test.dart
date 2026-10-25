import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_watch/src/monitor.dart';
import 'package:wifi_watch/src/router/router_source.dart';
import 'package:wifi_watch/src/router/tplink_client.dart';
import 'package:wifi_watch/src/settings.dart';

class _Fixed implements RouterSource {
  final List<ClientInfo>? clients;
  final Object? error;
  int fetches = 0;
  _Fixed(this.clients, [this.error]);

  @override
  String get name => 'fixed';

  @override
  Future<RouterSnapshot> fetch() async {
    fetches++;
    if (error != null) throw error!;
    return RouterSnapshot(DateTime(2026, 10, 25, 12), clients!);
  }

  @override
  Future<void> close() async {}
}

ClientInfo _c(String mac, String name, {int? total}) =>
    ClientInfo(mac: mac, ip: '', hostname: name, link: Link.wired, totalDown: total);

void main() {
  test('merge: each device once, marked with its router; measured traffic wins', () {
    final merged = Monitor.mergeSnapshots([
      ('Upstairs', RouterSnapshot(DateTime(2026), [_c('A', 'Linksys'), _c('B', 'Phone', total: 10)])),
      ('Downstairs', RouterSnapshot(DateTime(2026), [_c('A', 'Linksys again', total: 5), _c('C', 'Tablet')])),
    ]);
    final byMac = {for (final c in merged.clients) c.mac: c};
    expect(byMac.keys, unorderedEquals(['A', 'B', 'C']));
    expect(byMac['A']!.via, 'Downstairs', reason: 'the copy with traffic');
    expect(byMac['B']!.via, 'Upstairs');
    expect(byMac['C']!.via, 'Downstairs');
  });

  test('one router failing: the others still count, with a warning', () async {
    SharedPreferences.setMockInitialValues({});
    final good = _Fixed([_c('A', 'Phone')]);
    final bad = _Fixed(null, RouterException('The Linksys router says the password is wrong.', wrongPassword: true));
    final sources = {'up': good, 'down': bad};
    final monitor = Monitor(makeSource: (r) => sources[r.id]!);
    const settings = AppSettings(pollSeconds: 3600, routers: [
      RouterSetup(id: 'up', name: 'Upstairs', kind: RouterKind.tplink),
      RouterSetup(id: 'down', name: 'Downstairs', kind: RouterKind.linksys),
    ]);
    await monitor.start(settings);
    expect(monitor.state, MonitorState.ok);
    expect(monitor.error, contains('Downstairs: The Linksys router says the password is wrong.'));
    expect(monitor.live.keys, ['A']);
    expect(monitor.usage.devices['A']!.via, 'Upstairs');
    expect(monitor.sourceName, '2 routers');

    // A wrong password is not tried again.
    await monitor.poll();
    expect(bad.fetches, 1);
    expect(good.fetches, 2);
    await monitor.stop();
  });

  group('settings', () {
    test('one router from before is carried over', () async {
      SharedPreferences.setMockInitialValues({
        'wifiwatch.source': 'tplink',
        'wifiwatch.host': '192.168.0.1',
        'wifiwatch.username': 'user',
        'wifiwatch.password': 'pw',
        'wifiwatch.variant': 'ex-cbc',
        'wifiwatch.poll': 30,
      });
      final s = await SettingsStore().load();
      expect(s.routers, hasLength(1));
      final r = s.routers.single;
      expect((r.kind, r.host, r.username, r.password, r.variant), (RouterKind.tplink, '192.168.0.1', 'user', 'pw', 'ex-cbc'));
      expect(s.pollSeconds, 30);
      expect(s.isDemo, isFalse);
    });

    test('several routers are saved and loaded', () async {
      SharedPreferences.setMockInitialValues({});
      const s = AppSettings(routers: [
        RouterSetup(id: 'a', name: 'Upstairs', kind: RouterKind.tplink, host: '192.168.0.1', variant: 'ex-cbc'),
        RouterSetup(id: 'b', name: 'Downstairs', kind: RouterKind.linksys, host: '192.168.1.1', password: 'x'),
      ]);
      await SettingsStore().save(s);
      final back = await SettingsStore().load();
      expect(back.routers.map((r) => (r.id, r.displayName, r.kind, r.variant)), [
        ('a', 'Upstairs', RouterKind.tplink, 'ex-cbc'),
        ('b', 'Downstairs', RouterKind.linksys, null),
      ]);
      expect(back.sameRouters(s), isTrue);
      expect(back.sameRouters(s.withRouter(s.routers[1].copyWith(password: 'y'))), isFalse);
    });

    test('a new install starts with the demo', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await SettingsStore().load()).isDemo, isTrue);
    });
  });
}
