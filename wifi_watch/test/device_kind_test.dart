import 'package:flutter_test/flutter_test.dart';
import 'package:wifi_watch/src/device_kind.dart';

void main() {
  test('guesses the kind from the host name', () {
    expect(guessKind('V2219'), DeviceKind.phone);
    expect(guessKind('Galaxy-A15'), DeviceKind.phone);
    expect(guessKind('iPhone'), DeviceKind.phone);
    expect(guessKind('Redmi-Note-12'), DeviceKind.phone);
    expect(guessKind('Linksys06204'), DeviceKind.router);
    expect(guessKind('Living-Room-TV'), DeviceKind.tv);
    expect(guessKind('Chromecast'), DeviceKind.tv);
    expect(guessKind('DESKTOP-4KQ2L1'), DeviceKind.computer);
    expect(guessKind('Galaxy-Tab-S9'), DeviceKind.tablet);
    expect(guessKind('Echo-Dot'), DeviceKind.speaker);
    expect(guessKind('ESP_3A1F20'), DeviceKind.smartHome);
    expect(guessKind('PS5-123'), DeviceKind.console);
    expect(guessKind(''), DeviceKind.other);
    expect(guessKind('xyz'), DeviceKind.other);
    expect(guessKind('', 'vivo Mobile Communication'), DeviceKind.phone);
    expect(guessKind('', 'Espressif Inc.'), DeviceKind.smartHome);
    expect(guessKind('Living-Room-TV', 'Xiaomi'), DeviceKind.tv);
  });

  test('private MAC addresses', () {
    expect(isPrivateMac('7A:11:42:8D:E0:07'), isTrue);
    expect(isPrivateMac('3C:2E:F9:10:22:01'), isFalse);
  });
}
