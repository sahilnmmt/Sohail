// The setup flow driven against ESP-IDF's device code (tool/prov_harness).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sohail_app/src/provisioning/provisioner.dart';
import 'package:sohail_app/src/provisioning/setup_controller.dart';

import 'support/harness_transport.dart';

void main() {
  final harness = findHarness();
  final skip = harness == null ? 'prov_harness not built (see tool/prov_harness/build.sh)' : false;
  const robot = FoundRobot(id: 'AA:BB:CC:DD:EE:FF', name: 'PROV_SOHAIL_A1B2', rssi: -48);

  SetupController controller(List<HarnessTransport> opened) => SetupController(
        scanner: () => Stream.fromIterable([robot]),
        connector: (id) async {
          final t = await HarnessTransport.start(harness!, code: '482913', wifiPassword: 'correct-horse');
          opened.add(t);
          return t;
        },
        ensurePermissions: () async => null,
        pollInterval: Duration.zero,
      );

  test('robot label', () {
    expect(robot.label, 'Sohail A1B2');
    expect(const FoundRobot(id: 'x', name: 'PROV_123', rssi: 0).label, '123');
  });

  test('wrong code, then right code, wrong password, then right password', () async {
    final opened = <HarnessTransport>[];
    final c = controller(opened);
    await c.start();
    await pumpEventQueue();
    expect(c.step, SetupStep.scanning);
    expect(c.robots.single.label, 'Sohail A1B2');

    c.choose(c.robots.single);
    await c.submitCode('12345');
    expect(c.error, contains('6 digits'));

    await c.submitCode('000000');
    expect(c.step, SetupStep.code);
    expect(c.error, contains('did not match'));

    await c.submitCode('482913');
    expect(c.step, SetupStep.chooseNetwork, reason: c.error);
    expect(c.networks.first.ssid, 'HomeWiFi');

    await c.join('HomeWiFi', 'wrong');
    expect(c.step, SetupStep.chooseNetwork);
    expect(c.error, contains('password was wrong'));

    await c.join('HomeWiFi', 'correct-horse');
    expect(c.step, SetupStep.done, reason: c.error);
    expect(c.robotIp, '192.168.1.57');
    expect(opened.length, 2); // a fresh connection after the wrong code
    c.dispose();
  }, skip: skip);

  test('permission problems are shown and nothing is scanned', () async {
    var scanned = false;
    final c = SetupController(
      scanner: () {
        scanned = true;
        return const Stream.empty();
      },
      connector: (_) => throw UnimplementedError(),
      ensurePermissions: () async => 'Turn on Bluetooth to find your robot.',
    );
    await c.start();
    expect(c.step, SetupStep.permissions);
    expect(c.error, 'Turn on Bluetooth to find your robot.');
    expect(scanned, isFalse);
    c.dispose();
  });

  test('connection failures go back to the code step with a message', () async {
    final c = SetupController(
      scanner: () => Stream.fromIterable([robot]),
      connector: (_) async => throw ProvisioningException('Could not connect to the robot. Move closer and try again.'),
      ensurePermissions: () async => null,
    );
    await c.start();
    await pumpEventQueue();
    c.choose(robot);
    await c.submitCode('482913');
    expect(c.step, SetupStep.code);
    expect(c.error, contains('Move closer'));
    c.dispose();
  });
}
