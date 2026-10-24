// Checks the test router against tplinkrouterc6u, the Python library that is
// known to work with real TP-Link routers: if the library can log in to the
// test router and read devices from it, the test router behaves like a real
// one, and the app's own tests against it mean something.
// Needs TPLINK_PYTHON: a Python with tplinkrouterc6u installed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_watch/src/router/tplink_client.dart';

import 'support/fake_tplink_router.dart';

void main() {
  final python = Platform.environment['TPLINK_PYTHON'];
  final skip = python == null ? 'set TPLINK_PYTHON to a Python with tplinkrouterc6u' : null;

  // The library has no working MR + GCM login to compare against.
  for (final variant in TpVariant.all.where((v) => v.id != 'mr-gcm')) {
    test('tplinkrouterc6u logs in to the $variant test router', () async {
      final router = FakeTplinkRouter(variant: variant, hosts: const [
        FakeHost('3C:2E:F9:10:22:01', '192.168.0.101', 'V2219', 3),
        FakeHost('B8:27:EB:52:9A:04', '192.168.0.104', 'Linksys06204', 0),
      ]);
      await router.start();
      try {
        final r = await Process.run(
            python!, ['tool/tplink_reference_client.py', router.address, variant.id, 'admin', 'secret']);
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        expect((r.stdout as String).trim().split('\n'), ['V2219', 'Linksys06204']);
        expect(router.failedLogins, 0);
      } finally {
        await router.stop();
      }
    }, skip: skip);
  }
}
