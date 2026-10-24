// Sohail device protocol v1 (docs/04-device-protocol.md). Validation rules
// match firmware/components/sohail_core/src/protocol.c so the app never sends
// something a robot would drop.
import 'dart:convert';
import 'dart:math';

const protoVersion = 1;
const idMax = 24;
const nameMax = 16; // bytes
const textMax = 140; // bytes

enum MessageType { nudge, emoji, text }

enum Emoji { happy, love, laugh, sad, wow, sleepy }

const emojiGlyphs = {
  Emoji.happy: '😊',
  Emoji.love: '😍',
  Emoji.laugh: '😂',
  Emoji.sad: '😢',
  Emoji.wow: '😮',
  Emoji.sleepy: '😴',
};

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,24}$');

bool isValidId(String id) => _idPattern.hasMatch(id);

bool isValidName(String name) =>
    utf8.encode(name).length <= nameMax && !name.runes.any((r) => r < 0x20 || r == 0x7f);

bool isValidText(String text) {
  final n = utf8.encode(text).length;
  return n > 0 && n <= textMax && !text.runes.any((r) => r < 0x20 && r != 0x0a);
}

String randomMessageId([Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
}

String groupInboxTopic(String group) => 'sohail/v1/group/$group/inbox';
String deviceInboxTopic(String device) => 'sohail/v1/dev/$device/inbox';
const statusTopicFilter = 'sohail/v1/dev/+/status';

/// Device id from a status topic, or null if it is not one.
String? deviceFromStatusTopic(String topic) {
  final parts = topic.split('/');
  if (parts.length == 5 && parts[0] == 'sohail' && parts[1] == 'v1' && parts[2] == 'dev' && parts[4] == 'status') {
    return parts[3];
  }
  return null;
}

class SohailMessage {
  final String id;
  final String from;
  final String name;
  final MessageType type;
  final Emoji? emoji;
  final String? text;
  final int ts;

  SohailMessage({
    required this.id,
    required this.from,
    this.name = '',
    required this.type,
    this.emoji,
    this.text,
    this.ts = 0,
  }) {
    if (!isValidId(id)) throw ArgumentError.value(id, 'id');
    if (!isValidId(from)) throw ArgumentError.value(from, 'from');
    if (!isValidName(name)) throw ArgumentError.value(name, 'name', 'at most $nameMax bytes, no control characters');
    if (type == MessageType.emoji && emoji == null) throw ArgumentError('emoji message needs an emoji');
    if (type == MessageType.text && (text == null || !isValidText(text!))) {
      throw ArgumentError.value(text, 'text', '1-$textMax bytes');
    }
  }

  String get sender => name.isNotEmpty ? name : from;

  Map<String, Object> toJson() => {
        'v': protoVersion,
        'id': id,
        'from': from,
        if (name.isNotEmpty) 'name': name,
        'type': type.name,
        if (type == MessageType.emoji) 'emoji': emoji!.name,
        if (type == MessageType.text) 'text': text!,
        'ts': ts,
      };

  String encode() => jsonEncode(toJson());

  /// Parses a message, or returns null if it breaks the protocol rules.
  static SohailMessage? tryDecode(String json) {
    try {
      final m = jsonDecode(json);
      if (m is! Map<String, dynamic> || m['v'] != protoVersion) return null;
      final type = MessageType.values.where((t) => t.name == m['type']).firstOrNull;
      if (type == null) return null;
      final emoji = type == MessageType.emoji ? Emoji.values.where((e) => e.name == m['emoji']).firstOrNull : null;
      if (type == MessageType.emoji && emoji == null) return null;
      final ts = m['ts'];
      if (ts != null && (ts is! int || ts < 0 || ts > 0xffffffff)) return null;
      final name = m['name'];
      if (name != null && name is! String) return null;
      final text = m['text'];
      if (type == MessageType.text && text is! String) return null;
      final id = m['id'], from = m['from'];
      if (id is! String || from is! String) return null;
      return SohailMessage(
        id: id,
        from: from,
        name: (name as String?) ?? '',
        type: type,
        emoji: emoji,
        text: type == MessageType.text ? text as String : null,
        ts: (ts as int?) ?? 0,
      );
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
