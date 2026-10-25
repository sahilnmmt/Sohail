import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_watch/src/router/router_source.dart';
import 'package:wifi_watch/src/router/tplink_client.dart';
import 'package:wifi_watch/src/router/tplink_crypto.dart';

import 'support/fake_tplink_router.dart';

const _hosts = [
  FakeHost('3C:2E:F9:10:22:01', '192.168.0.101', 'V2219', 3, totalRx: 5000, totalTx: 700, currRx: 120, currTx: 30),
  FakeHost('B8:27:EB:52:9A:04', '192.168.0.104', 'Linksys06204', 0),
  FakeHost('DC:A6:32:66:1D:05', '192.168.0.105', 'Old-Tablet', 1, active: false),
];

void main() {
  for (final variant in TpVariant.all) {
    group('$variant router', () {
      late FakeTplinkRouter router;

      setUp(() async {
        router = FakeTplinkRouter(variant: variant, hosts: _hosts);
        await router.start();
      });
      tearDown(() => router.stop());

      test('finds the protocol, logs in and lists the online devices', () async {
        final client = TplinkClient(host: router.address, username: 'admin', password: 'secret');
        final snap = await client.fetch();
        expect(client.variant?.id, variant.id);
        expect(client.name, 'TP-Link Archer XX530v');
        expect(router.failedLogins, 0);

        expect(snap.clients.map((c) => c.hostname), ['V2219', 'Linksys06204']);
        final phone = snap.clients.first;
        expect(phone.mac, '3C:2E:F9:10:22:01');
        expect(phone.ip, '192.168.0.101');
        expect(snap.clients[1].link, Link.wired);
        if (variant.protocol == TpProtocol.ex) {
          expect(phone.link, Link.wifi5g);
          expect(phone.totalDown, isNull);
        } else {
          expect(phone.link, Link.wifi5g);
          expect(phone.totalDown, 5000);
          expect(phone.totalUp, 700);
          expect(phone.downBps, 120);
        }
        await client.close();
      });

      test('a known protocol logs in without searching', () async {
        final client = TplinkClient(host: router.address, username: 'admin', password: 'secret', variant: variant);
        await client.fetch();
        final other = variant.protocol == TpProtocol.mr ? 'POST /cgi/getGDPRParm' : 'POST /cgi/getParm';
        expect(router.requests, isNot(contains(other)));
        expect(router.logins, 1);
        await client.close();
      });

      test('logs in again when the session is taken over', () async {
        final client = TplinkClient(host: router.address, username: 'admin', password: 'secret', variant: variant);
        await client.fetch();
        router.expireSession();
        final snap = await client.fetch();
        expect(snap.clients, hasLength(2));
        expect(router.logins, 2);
        await client.close();
      });

      test('a wrong password stops after one refused login', () async {
        final client = TplinkClient(host: router.address, username: 'admin', password: 'wrong');
        await expectLater(
          client.connect(),
          throwsA(isA<RouterException>().having((e) => e.wrongPassword, 'wrongPassword', isTrue)),
        );
        expect(router.failedLogins, 1);
        await client.close();
      });
    });
  }

  for (final style in TokenStyle.values) {
    test('finds the session with token style ${style.name}', () async {
      final router = FakeTplinkRouter(variant: const TpVariant(TpProtocol.ex, TpCipher.cbc), tokenStyle: style, hosts: _hosts);
      await router.start();
      final lines = <String>[];
      final client = TplinkClient(host: router.address, username: 'admin', password: 'secret', log: lines.add);
      final snap = await client.fetch();
      expect(snap.clients, hasLength(2));
      expect(client.name, 'TP-Link Archer XX530v');
      expect(router.logins, 1);
      if (style == TokenStyle.cookieOnly) expect(lines, contains('Requests work without a session token'));
      await client.close();
      await router.stop();
    });
  }

  group('password-only routers (empty user name)', () {
    const ex = TpVariant(TpProtocol.ex, TpCipher.cbc);

    test('logs in as "user"', () async {
      final router = FakeTplinkRouter(variant: ex, username: 'user', hosts: _hosts);
      await router.start();
      final client = TplinkClient(host: router.address, username: '', password: 'secret');
      expect((await client.fetch()).clients, hasLength(2));
      expect(client.user, 'user');
      expect(router.failedLogins, 0);
      await client.close();
      await router.stop();
    });

    test('falls back to "admin" after one refused login', () async {
      final router = FakeTplinkRouter(variant: ex, username: 'admin', hosts: _hosts);
      await router.start();
      final client = TplinkClient(host: router.address, username: '', password: 'secret');
      expect((await client.fetch()).clients, hasLength(2));
      expect(client.user, 'admin');
      expect(router.failedLogins, 1);
      await client.close();
      await router.stop();
    });

    test('a wrong password stops after one try per name', () async {
      final router = FakeTplinkRouter(variant: ex, username: 'user', hosts: _hosts);
      await router.start();
      final client = TplinkClient(host: router.address, username: '', password: 'wrong');
      await expectLater(
          client.connect(), throwsA(isA<RouterException>().having((e) => e.wrongPassword, 'wrongPassword', isTrue)));
      expect(router.failedLogins, 2);
      await client.close();
      await router.stop();
    });
  });

  test('connection test looks for traffic tables and reports the maker', () async {
    final router = FakeTplinkRouter(variant: const TpVariant(TpProtocol.ex, TpCipher.cbc), hosts: _hosts);
    await router.start();
    final lines = <String>[];
    final client = TplinkClient(host: router.address, username: 'admin', password: 'secret', log: lines.add);
    await client.connect();
    await client.describeDeviceFields();
    expect(lines, contains(startsWith('js/oid_str.js: HTTP 200, 4 tables; maybe traffic: DEV2_WIFI_ASSOC_STATS')));
    expect(lines, contains(startsWith('DEV2_WIFI_ASSOC_STATS:')));
    expect(lines.where((l) => l.contains('LTE_SMS')), hasLength(0));
    expect((await client.fetch()).clients.first.vendor, 'vivo Mobile Communication');
    await client.close();
    await router.stop();
  });

  test('a slow first answer does not rule the login method out', () async {
    final router = FakeTplinkRouter(variant: const TpVariant(TpProtocol.ex, TpCipher.cbc), hosts: _hosts)
      ..slowFirstKey = const Duration(seconds: 2);
    await router.start();
    final client = TplinkClient(
        host: router.address, username: 'admin', password: 'secret', timeout: const Duration(milliseconds: 500));
    expect((await client.fetch()).clients, hasLength(2));
    expect(client.variant?.id, 'ex-cbc');
    await client.close();
    await router.stop();
  });

  test('findToken ignores variable names', () {
    expect(TplinkClient.findToken('var token="abc123";'), 'abc123');
    expect(TplinkClient.findToken("var token = 'abc123';"), 'abc123');
    expect(TplinkClient.findToken('tmpcount.Token=0a1b2c3d4e5f;'), '0a1b2c3d4e5f');
    expect(TplinkClient.findToken('var token;\ntmpcount.Token=token;\nx.token = tokenValue;'), isNull);
  });

  test('an address that is not a TP-Link router says so', () async {
    final router = FakeTplinkRouter(variant: TpVariant.all.first);
    await router.start();
    final address = router.address;
    await router.stop();
    final client = TplinkClient(host: address, username: 'admin', password: 'x', timeout: const Duration(seconds: 2));
    await expectLater(client.connect(), throwsA(isA<RouterException>()));
    await client.close();
  });

  group('parseMrReply', () {
    test('groups objects by act index', () {
      final r = TplinkClient.parseMrReply(
          '[1,1,0,0,0,0]0\nIPAddress=1.2.3.4\nMACAddress=aa\n[1,2,0,0,0,0]0\nIPAddress=1.2.3.5\n'
          '[0,0,0,0,0,0]1\nmodelName=X=Y\n[error]0\n',
          2);
      expect(r[0], [
        {'IPAddress': '1.2.3.4', 'MACAddress': 'aa'},
        {'IPAddress': '1.2.3.5'},
      ]);
      expect(r[1], [
        {'modelName': 'X=Y'},
      ]);
    });

    test('a router error fails', () {
      expect(() => TplinkClient.parseMrReply('[error]9003\n', 1), throwsA(isA<RouterException>()));
    });
  });

  test('normalizeMac', () {
    expect(normalizeMac('aa-bb-cc-00-11-22'), 'AA:BB:CC:00:11:22');
    expect(normalizeMac('aabb.cc00.1122'), 'AA:BB:CC:00:11:22');
  });
}
