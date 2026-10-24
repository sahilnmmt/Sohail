import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sohail_app/src/provisioning/ble_ids.dart';
import 'package:sohail_app/src/provisioning/messages.dart';
import 'package:sohail_app/src/provisioning/protobuf.dart';

void main() {
  test('negative int32 survives (RSSI)', () {
    final w = PbWriter()..varint(3, -71);
    final bytes = w.toBytes();
    expect(bytes.length, 11); // tag + 10-byte two's complement
    expect(PbMessage.parse(bytes).int32(3), -71);
  });

  test('empty sub-messages are still written so the oneof is selected', () {
    // TypeCmdGetStatus (0, omitted) + empty CmdGetStatus in field 10.
    expect(getStatusCommand(), Uint8List.fromList([0x52, 0x00]));
    expect(applyConfigCommand(), Uint8List.fromList([0x08, 0x04, 0x72, 0x00]));
  });

  test('truncated input is rejected, unknown wire types skipped', () {
    expect(() => PbMessage.parse([0x0a, 0x05, 0x01]), throwsA(isA<PbFormatException>()));
    expect(() => PbMessage.parse([0x08]), throwsA(isA<PbFormatException>()));
    final m = PbMessage.parse([0x0d, 1, 2, 3, 4, 0x10, 0x07]); // fixed32 then field 2 = 7
    expect(m.integer(2), 7);
  });

  test('Bluetooth IDs match ESP-IDF', () {
    expect(provEndpointUuid('prov-session'), '1775ff51-6b43-439b-877c-060f2d9bed07');
    expect(provEndpointUuid('prov-config'), '1775ff52-6b43-439b-877c-060f2d9bed07');
    expect(provEndpointUuid('prov-scan'), '1775ff50-6b43-439b-877c-060f2d9bed07');
    expect(() => provEndpointUuid('nope'), throwsArgumentError);
  });

  test('signal bars', () {
    const n = WifiNetwork(ssid: 'x', rssi: -60, channel: 1, auth: WifiAuth.wpa2Psk);
    expect(n.bars, 3);
    expect(n.needsPassword, isTrue);
  });
}
