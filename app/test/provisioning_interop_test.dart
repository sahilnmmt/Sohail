// Runs the app's provisioning client against ESP-IDF's real device-side
// code (protocomm + security1 + wifi_config/wifi_scan handlers).
// Build the harness first: IDF_PATH=... tool/prov_harness/build.sh
import 'package:flutter_test/flutter_test.dart';
import 'package:sohail_app/src/provisioning/provisioner.dart';

import 'support/harness_transport.dart';

void main() {
  final harness = findHarness();
  final skip = harness == null ? 'prov_harness not built (see tool/prov_harness/build.sh)' : false;

  Future<(HarnessTransport, Provisioner)> robot({String code = '482913', String typedCode = '482913'}) async {
    final t = await HarnessTransport.start(harness!, code: code, wifiPassword: 'correct-horse');
    return (t, Provisioner(t, typedCode, pollInterval: Duration.zero));
  }

  test('full setup: session, scan, credentials, connected', () async {
    final (t, p) = await robot();
    await p.startSession();

    final nets = await p.scan(pageSize: 2); // forces two result pages
    expect(nets.map((n) => n.ssid), ['HomeWiFi', 'Neighbours-5G', 'Cafe Free WiFi']);
    expect(nets.first.rssi, -42);
    expect(nets.first.channel, 6);
    expect(nets.first.auth, WifiAuth.wpa2Psk);
    expect(nets[1].auth, WifiAuth.wpa2Wpa3Psk);
    expect(nets.last.needsPassword, isFalse);

    await p.sendWifi('HomeWiFi', 'correct-horse');
    expect(await t.state(), 'ssid=HomeWiFi;password=correct-horse;applied=1');
    final s = await p.waitForConnection();
    expect(s.state, WifiState.connected);
    expect(s.ipAddress, '192.168.1.57');
    await t.close();
  }, skip: skip);

  test('wrong 6-digit code is rejected and nothing is sent', () async {
    final (t, p) = await robot(typedCode: '000000');
    await expectLater(p.startSession(), throwsA(isA<ProvisioningException>()
        .having((e) => e.message, 'message', contains('code did not match'))));
    expect(await t.state(), 'ssid=;password=;applied=0');
    await t.close();
  }, skip: skip);

  test('wrong Wi-Fi password is reported', () async {
    final (t, p) = await robot();
    await p.startSession();
    await p.sendWifi('HomeWiFi', 'hunter2');
    await expectLater(p.waitForConnection(), throwsA(isA<ProvisioningException>()
        .having((e) => e.message, 'message', contains('password was wrong'))));
    // The user can retry on the same session.
    await p.sendWifi('HomeWiFi', 'correct-horse');
    expect((await p.waitForConnection()).state, WifiState.connected);
    await t.close();
  }, skip: skip);

  test('unknown network is reported', () async {
    final (t, p) = await robot();
    await p.startSession();
    await p.sendWifi('NotHere', 'whatever');
    await expectLater(p.waitForConnection(), throwsA(isA<ProvisioningException>()
        .having((e) => e.message, 'message', contains('could not find'))));
    await t.close();
  }, skip: skip);

  test('Unicode network names and passwords survive the trip', () async {
    final (t, p) = await robot();
    await p.startSession();
    await p.sendWifi('Café Ünïcode', 'pässwörd ✓');
    expect(await t.state(), 'ssid=Café Ünïcode;password=pässwörd ✓;applied=1');
    await t.close();
  }, skip: skip);

  test('requests before the session are refused by the robot', () async {
    final (t, p) = await robot();
    expect(() => p.status(), throwsStateError);
    await t.close();
  }, skip: skip);
}
