// ESP-IDF protocomm "security 1": Curve25519 key exchange, AES-256-CTR, and a
// proof-of-possession code (the 6-digit code on the robot's screen).
//
// key   = X25519(client_private, device_public) XOR SHA-256(pop)
// nonce = 16 random bytes from the device; one CTR keystream is shared by
//         every message in both directions, in the order they are sent.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'messages.dart';

class ProvisioningException implements Exception {
  final String message;
  ProvisioningException(this.message);
  @override
  String toString() => message;
}

class Security1 {
  final String pop;
  final _x25519 = const DartX25519();
  final _aes = DartAesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);

  SimpleKeyPair? _keyPair;
  Uint8List? _clientPubkey;
  Uint8List? _devicePubkey;
  SecretKey? _key;
  Uint8List? _nonce;
  int _streamOffset = 0;

  Security1(this.pop);

  bool get isReady => _key != null && _streamOffset >= 64;

  /// SessionData carrying our public key.
  Future<Uint8List> command0() async {
    _keyPair = await _x25519.newKeyPair();
    _clientPubkey = Uint8List.fromList((await _keyPair!.extractPublicKey()).bytes);
    return sessionCommand0(_clientPubkey!);
  }

  /// Takes the robot's reply to command0, derives the session key and returns
  /// command1 (the robot's public key, encrypted, proving we know the code).
  Future<Uint8List> command1(List<int> response0) async {
    final r = SessionResponse0.parse(response0);
    if (r.status != 0) throw ProvisioningException('Robot refused the session (${statusNames[r.status]})');
    if (r.devicePubkey.length != 32 || r.deviceRandom.length != 16) {
      throw ProvisioningException('Robot sent an invalid session key');
    }
    _devicePubkey = r.devicePubkey;
    _nonce = r.deviceRandom;

    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: SimplePublicKey(r.devicePubkey, type: KeyPairType.x25519),
    );
    final sharedBytes = await shared.extractBytes();
    final popHash = (await Sha256().hash(utf8.encode(pop))).bytes;
    _key = SecretKey([for (var i = 0; i < 32; i++) sharedBytes[i] ^ popHash[i]]);
    _streamOffset = 0;

    return sessionCommand1(await _apply(_devicePubkey!));
  }

  /// Checks the robot's reply to command1: it must have encrypted our public
  /// key with the same key, which only works if both sides used the same code.
  Future<void> verify(List<int> response1) async {
    final r = SessionResponse1.parse(response1);
    if (r.status != 0 || r.deviceVerifyData.length != 32) throw wrongCode();
    final clear = await _apply(r.deviceVerifyData);
    for (var i = 0; i < 32; i++) {
      if (clear[i] != _clientPubkey![i]) throw wrongCode();
    }
  }

  static ProvisioningException wrongCode() =>
      ProvisioningException('That code did not match. Check the 6 digits on the robot\'s screen.');

  Future<Uint8List> encrypt(List<int> data) => _apply(data);
  Future<Uint8List> decrypt(List<int> data) => _apply(data);

  /// CTR is symmetric: encrypting and decrypting both XOR the next bytes of
  /// the shared keystream.
  Future<Uint8List> _apply(List<int> data) async {
    if (_key == null) throw StateError('session not established');
    final box = await _aes.encrypt(data, secretKey: _key!, nonce: _nonce!, keyStreamIndex: _streamOffset);
    _streamOffset += data.length;
    return Uint8List.fromList(box.cipherText);
  }
}
