// Minimal protobuf wire-format encoder/decoder for the handful of ESP-IDF
// provisioning messages the app exchanges (see esp-idf components/protocomm
// and wifi_provisioning *.proto). Avoids a protoc/codegen step.
import 'dart:typed_data';

class PbWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void _rawVarint(int value) {
    // Negative numbers are encoded as 64-bit two's complement (10 bytes).
    var v = value;
    for (var i = 0; i < 10; i++) {
      final byte = v & 0x7f;
      v = v >>> 7;
      if (v == 0) {
        _out.addByte(byte);
        return;
      }
      _out.addByte(byte | 0x80);
    }
  }

  void _tag(int field, int wireType) => _rawVarint((field << 3) | wireType);

  /// varint field (int32/uint32/enum/bool). Zero is skipped, as in proto3.
  void varint(int field, int value) {
    if (value == 0) return;
    _tag(field, 0);
    _rawVarint(value);
  }

  void boolean(int field, bool value) => varint(field, value ? 1 : 0);

  /// Length-delimited bytes/string field. Empty values are skipped.
  void bytes(int field, List<int> value) {
    if (value.isEmpty) return;
    _tag(field, 2);
    _rawVarint(value.length);
    _out.add(value);
  }

  /// Embedded message. Always written, even when empty, because an empty
  /// message still selects its branch of a `oneof`.
  void message(int field, PbWriter value) {
    final body = value.toBytes();
    _tag(field, 2);
    _rawVarint(body.length);
    _out.add(body);
  }

  Uint8List toBytes() => _out.toBytes();
}

class PbFormatException implements Exception {
  final String message;
  PbFormatException(this.message);
  @override
  String toString() => 'PbFormatException: $message';
}

/// Parsed message: field number -> values in wire order (int or Uint8List).
class PbMessage {
  final Map<int, List<Object>> _fields = {};

  PbMessage.parse(List<int> data) {
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    var pos = 0;

    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (pos >= bytes.length) throw PbFormatException('truncated varint');
        final b = bytes[pos++];
        if (shift < 64) result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
        if (shift >= 70) throw PbFormatException('varint too long');
      }
    }

    while (pos < bytes.length) {
      final key = readVarint();
      final field = key >>> 3;
      final wire = key & 7;
      Object value;
      switch (wire) {
        case 0:
          value = readVarint();
        case 2:
          final len = readVarint();
          if (len < 0 || pos + len > bytes.length) throw PbFormatException('truncated field $field');
          value = Uint8List.sublistView(bytes, pos, pos + len);
          pos += len;
        case 1:
          if (pos + 8 > bytes.length) throw PbFormatException('truncated fixed64');
          pos += 8;
          continue;
        case 5:
          if (pos + 4 > bytes.length) throw PbFormatException('truncated fixed32');
          pos += 4;
          continue;
        default:
          throw PbFormatException('unsupported wire type $wire');
      }
      (_fields[field] ??= []).add(value);
    }
  }

  bool has(int field) => _fields.containsKey(field);

  int integer(int field, [int fallback = 0]) {
    final v = _fields[field]?.last;
    return v is int ? v : fallback;
  }

  /// int32 fields arrive as 64-bit two's complement when negative.
  int int32(int field) => integer(field).toSigned(32);

  bool boolean(int field) => integer(field) != 0;

  Uint8List bytes(int field) {
    final v = _fields[field]?.last;
    return v is Uint8List ? v : Uint8List(0);
  }

  PbMessage? message(int field) => has(field) ? PbMessage.parse(bytes(field)) : null;

  List<PbMessage> messages(int field) =>
      (_fields[field] ?? const []).whereType<Uint8List>().map(PbMessage.parse).toList();
}
