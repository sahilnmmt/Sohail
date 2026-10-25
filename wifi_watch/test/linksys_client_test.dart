import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_watch/src/router/linksys_client.dart';
import 'package:wifi_watch/src/router/router_source.dart';
import 'package:wifi_watch/src/router/tplink_client.dart';

import 'support/fake_linksys_router.dart';

void main() {
  late FakeLinksysRouter router;
  setUp(() async {
    router = FakeLinksysRouter();
    await router.start();
  });
  tearDown(() => router.stop());

  test('lists the online devices, not the router or offline ones', () async {
    final client = LinksysClient(host: router.address, username: '', password: 'secret');
    final snap = await client.fetch();
    expect(client.name, 'Linksys EA6350');
    expect(snap.clients.map((c) => c.hostname), ['Kids tablet', 'Smart-TV']);
    final tablet = snap.clients.first;
    expect(tablet.mac, 'AA:BB:CC:00:00:01');
    expect(tablet.ip, '192.168.1.101');
    expect(tablet.vendor, 'Samsung');
    expect(tablet.link, Link.wifi5g);
    expect(snap.clients[1].link, Link.wired);
    expect(tablet.hasTraffic, isFalse);
    await client.close();
  });

  test('a wrong password says so', () async {
    final client = LinksysClient(host: router.address, password: 'wrong');
    await expectLater(
        client.fetch(), throwsA(isA<RouterException>().having((e) => e.wrongPassword, 'wrongPassword', isTrue)));
    expect(router.unauthorized, 1);
    await client.close();
  });
}
