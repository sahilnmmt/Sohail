// Talks to a real MQTT broker when MQTT_TEST_PORT is set, e.g.
//   amqtt (pip install amqtt) or mosquitto on localhost.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:sohail_app/src/messaging/message.dart';
import 'package:sohail_app/src/messaging/messaging_service.dart';
import 'package:sohail_app/src/settings.dart';

void main() {
  final port = int.tryParse(Platform.environment['MQTT_TEST_PORT'] ?? '');
  final skip = port == null ? 'set MQTT_TEST_PORT to run against a broker' : false;

  AppSettings settings(String id, String name) => AppSettings(
      displayName: name, group: 'testfam', host: '127.0.0.1', port: port ?? 1883, tls: false,
      username: '', password: '', clientId: id);

  Future<void> until(bool Function() cond) async {
    for (var i = 0; i < 100 && !cond(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('two phones see each other, a robot message and robot presence', () async {
    final mum = MessagingService();
    final dad = MessagingService();
    await mum.connect(settings('app-mum001', 'Mum'));
    await dad.connect(settings('app-dad001', 'Dad'));
    expect(mum.state, LinkState.connected, reason: mum.error);
    expect(dad.state, LinkState.connected, reason: dad.error);

    // A robot (raw client) announces itself and sends an emoji, as the firmware does.
    final robot = MqttServerClient.withPort('127.0.0.1', 'sohail-a1b2c3', port!)..logging(on: false);
    await robot.connect();
    robot.publishMessage('sohail/v1/dev/sohail-a1b2c3/status', MqttQos.atLeastOnce,
        (MqttClientPayloadBuilder()..addString('online')).payload!, retain: true);
    robot.publishMessage(groupInboxTopic('testfam'), MqttQos.atLeastOnce,
        (MqttClientPayloadBuilder()
              ..addUTF8String('{"v":1,"id":"r1","from":"sohail-a1b2c3","name":"Kitchen","type":"emoji","emoji":"wow","ts":0}'))
            .payload!);

    expect(mum.send(MessageType.text, text: 'Dinner is ready 🍲'), isNull);
    await until(() => dad.feed.length >= 2 && mum.robots.isNotEmpty);

    expect(dad.feed.map((f) => f.message.sender), containsAll(['Kitchen', 'Mum']));
    final fromMum = dad.feed.firstWhere((f) => f.message.sender == 'Mum');
    expect(fromMum.message.text, 'Dinner is ready 🍲');
    expect(fromMum.mine, isFalse);
    expect(mum.feed.where((f) => f.message.text == 'Dinner is ready 🍲').length, 1); // echo de-duplicated
    expect(mum.feed.firstWhere((f) => f.message.text != null).mine, isTrue);
    expect(mum.robots['sohail-a1b2c3'], isTrue);

    // Invalid traffic on the group topic is ignored.
    robot.publishMessage(groupInboxTopic('testfam'), MqttQos.atLeastOnce,
        (MqttClientPayloadBuilder()..addString(jsonEncode({'v': 1, 'type': 'nudge'}))).payload!);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(dad.feed.length, 2);

    robot.disconnect();
    await mum.disconnect();
    await dad.disconnect();
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('unreachable server gives a readable error', () async {
    final s = MessagingService();
    await s.connect(settings('app-x00001', 'X').copyWith(port: 1)); // nothing listens on port 1
    expect(s.state, LinkState.failed);
    expect(s.error, contains('Could not reach'));
  });
}
