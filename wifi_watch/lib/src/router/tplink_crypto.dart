// The encryption TP-Link's ISP and LTE routers (MR, VR, EX, XC, VX, XX...)
// put on their web interface. Every request body is AES encrypted with a key
// the app makes up, and signed with the router's RSA public key:
//   sign = RSA("key=..&iv=..&h=md5(user+pass)&s=seq+len(data)")  (login)
//   sign = RSA("h=..&s=..")                                       (after)
// RSA is raw (no padding), in key-sized blocks, the last one zero filled.
// Older firmware uses AES-128-CBC; newer uses AES-128-GCM with a separate tag.
//
// Worked out from the open-source tplinkrouterc6u library (GPL-3.0),
// https://github.com/AlexandrErohin/TP-Link-Archer-C6U.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;
import 'package:cryptography/cryptography.dart';

enum TpCipher { cbc, gcm }

class TpCrypto {
  final TpCipher cipher;

  /// 16 ASCII digits; the router expects printable keys.
  final String key;

  /// 16 ASCII digits for CBC, 12 for GCM.
  final String iv;

  TpCrypto._(this.cipher, this.key, this.iv);

  factory TpCrypto(TpCipher cipher, [Random? rng]) {
    final r = rng ?? Random.secure();
    String digits(int n) => List.generate(n, (_) => r.nextInt(10)).join();
    return TpCrypto._(cipher, digits(16), digits(cipher == TpCipher.gcm ? 12 : 16));
  }

  /// For tests: a fixed key and iv.
  TpCrypto.fixed(this.cipher, this.key, this.iv);

  SecretKey get _secret => SecretKey(utf8.encode(key));

  /// Returns base64 cipher text and, for GCM, the base64 tag.
  Future<({String data, String? tag})> encrypt(String plain) async {
    final bytes = utf8.encode(plain);
    if (cipher == TpCipher.cbc) {
      final box = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty)
          .encrypt(bytes, secretKey: _secret, nonce: utf8.encode(iv));
      return (data: base64.encode(box.cipherText), tag: null);
    }
    final box = await AesGcm.with128bits(nonceLength: 12).encrypt(bytes, secretKey: _secret, nonce: utf8.encode(iv));
    return (data: base64.encode(box.cipherText), tag: base64.encode(box.mac.bytes));
  }

  /// GCM replies carry the 16-byte tag as the last 24 base64 characters.
  Future<String> decrypt(String body) async {
    final text = body.trim();
    if (cipher == TpCipher.cbc) {
      final box = SecretBox(base64.decode(text), nonce: utf8.encode(iv), mac: Mac.empty);
      final plain = await AesCbc.with128bits(macAlgorithm: MacAlgorithm.empty).decrypt(box, secretKey: _secret);
      return utf8.decode(plain, allowMalformed: true);
    }
    final split = text.length - 24;
    final box = SecretBox(base64.decode(text.substring(0, split)),
        nonce: utf8.encode(iv), mac: Mac(base64.decode(text.substring(split))));
    final plain = await AesGcm.with128bits(nonceLength: 12).decrypt(box, secretKey: _secret);
    return utf8.decode(plain, allowMalformed: true);
  }

  /// The `sign=` field. [dataLength] is the length of the base64 body.
  String signature({
    required bool isLogin,
    required String hash,
    required int seq,
    required int dataLength,
    required String nn,
    required String ee,
  }) {
    final s = seq + dataLength;
    final String text;
    if (!isLogin) {
      text = 'h=$hash&s=$s';
    } else if (cipher == TpCipher.gcm) {
      text = 'key=${base64.encode(utf8.encode(key))}&iv=${base64.encode(utf8.encode(iv))}&h=$hash&s=$s';
    } else {
      text = 'key=$key&iv=$iv&h=$hash&s=$s';
    }
    return rsaNoPadding(utf8.encode(text), nn, ee);
  }

  static String loginHash(String username, String password) => md5.convert(utf8.encode('$username$password')).toString();
}

/// Raw RSA over [data] in blocks the size of the modulus, the last block
/// filled with zero bytes, each result as fixed-width hex.
String rsaNoPadding(List<int> data, String nn, String ee) {
  final n = BigInt.parse(nn, radix: 16);
  final e = BigInt.parse(ee, radix: 16);
  final blockLen = nn.length ~/ 2;
  final out = StringBuffer();
  for (var pos = 0; pos < data.length; pos += blockLen) {
    final block = Uint8List(blockLen)..setRange(0, min(blockLen, data.length - pos), data, pos);
    var m = BigInt.zero;
    for (final b in block) {
      m = (m << 8) | BigInt.from(b);
    }
    out.write(m.modPow(e, n).toRadixString(16).padLeft(nn.length, '0'));
  }
  return out.toString();
}
