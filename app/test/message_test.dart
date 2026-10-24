import 'package:flutter_test/flutter_test.dart';
import 'package:sohail_app/src/messaging/message.dart';

void main() {
  test('round-trips every message type', () {
    for (final type in MessageType.values) {
      final m = SohailMessage(
        id: 'abc123',
        from: 'app-1f2e3d',
        name: 'Mum',
        type: type,
        emoji: type == MessageType.emoji ? Emoji.wow : null,
        text: type == MessageType.text ? 'Dinner at 7 "sharp"\nlove you' : null,
        ts: 1792831587,
      );
      final back = SohailMessage.tryDecode(m.encode())!;
      expect(back.type, type);
      expect(back.name, 'Mum');
      expect(back.ts, 1792831587);
      expect(back.emoji, m.emoji);
      expect(back.text, m.text);
    }
  });

  test('decodes what the robot firmware sends', () {
    // Exact output format of sohail_msg_encode() in firmware protocol.c.
    const fromRobot = '{"v":1,"id":"6e6697d2febb3c06","from":"sohail-a1b2c3","name":"Grandma",'
        '"type":"emoji","emoji":"love","ts":0}';
    final m = SohailMessage.tryDecode(fromRobot)!;
    expect(m.sender, 'Grandma');
    expect(m.emoji, Emoji.love);
    expect(m.from, 'sohail-a1b2c3');
  });

  test('rejects messages the robot would reject', () {
    const bad = [
      'not json',
      '[1]',
      '{"v":2,"id":"a","from":"b","type":"nudge"}',
      '{"v":1,"id":"a","from":"b/#","type":"nudge"}',
      '{"v":1,"id":"a","from":"b","type":"call"}',
      '{"v":1,"id":"a","from":"b","type":"emoji","emoji":"angry"}',
      '{"v":1,"id":"a","from":"b","type":"text","text":""}',
      '{"v":1,"id":"a","from":"b","type":"text","text":"a\\u0007b"}',
      '{"v":1,"id":"a","from":"b","type":"nudge","ts":-1}',
      '{"v":1,"id":"a","from":"b","type":"nudge","name":"this name is far too long"}',
      '{"v":1,"id":7,"from":"b","type":"nudge"}',
    ];
    for (final b in bad) {
      expect(SohailMessage.tryDecode(b), isNull, reason: b);
    }
  });

  test('name and text limits are UTF-8 bytes', () {
    expect(isValidName('A' * 16), isTrue);
    expect(isValidName('A' * 17), isFalse);
    expect(isValidName('é' * 8), isTrue); // 16 bytes
    expect(isValidName('é' * 9), isFalse); // 18 bytes
    expect(isValidText('x' * 140), isTrue);
    expect(isValidText('x' * 141), isFalse);
    expect(isValidText('line one\nline two'), isTrue);
    expect(() => SohailMessage(id: 'a', from: 'b', type: MessageType.text, text: 'é' * 71), throwsArgumentError);
  });

  test('topics and ids', () {
    expect(groupInboxTopic('family'), 'sohail/v1/group/family/inbox');
    expect(deviceFromStatusTopic('sohail/v1/dev/sohail-a1b2c3/status'), 'sohail-a1b2c3');
    expect(deviceFromStatusTopic('sohail/v1/group/family/inbox'), isNull);
    expect(isValidId('a' * 24), isTrue);
    expect(isValidId('a' * 25), isFalse);
    expect(isValidId('fam ily'), isFalse);
    expect(randomMessageId(), matches(RegExp(r'^[0-9a-f]{16}$')));
  });
}
