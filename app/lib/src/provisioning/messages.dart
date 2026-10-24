// ESP-IDF provisioning messages: session (security1), Wi-Fi scan and
// Wi-Fi config. Field numbers follow esp-idf v5.3 *.proto files.
import 'dart:convert';
import 'dart:typed_data';

import 'protobuf.dart';

/// protocomm Status enum (constants.proto).
const statusNames = {
  0: 'Success',
  1: 'InvalidSecScheme',
  2: 'InvalidProto',
  3: 'TooManySessions',
  4: 'InvalidArgument',
  5: 'InternalError',
  6: 'CryptoError',
  7: 'InvalidSession',
};

// ---- session.proto / sec1.proto -------------------------------------------

const _secScheme1 = 1;

Uint8List sessionCommand0(List<int> clientPubkey) {
  final sc0 = PbWriter()..bytes(1, clientPubkey);
  final sec1 = PbWriter()
    ..varint(1, 0) // Session_Command0
    ..message(20, sc0);
  return (PbWriter()
        ..varint(2, _secScheme1)
        ..message(11, sec1))
      .toBytes();
}

Uint8List sessionCommand1(List<int> clientVerifyData) {
  final sc1 = PbWriter()..bytes(2, clientVerifyData);
  final sec1 = PbWriter()
    ..varint(1, 2) // Session_Command1
    ..message(22, sc1);
  return (PbWriter()
        ..varint(2, _secScheme1)
        ..message(11, sec1))
      .toBytes();
}

class SessionResponse0 {
  final int status;
  final Uint8List devicePubkey;
  final Uint8List deviceRandom;
  SessionResponse0(this.status, this.devicePubkey, this.deviceRandom);

  factory SessionResponse0.parse(List<int> data) {
    final sr0 = _sec1Payload(data, expectType: 1).message(21);
    if (sr0 == null) throw PbFormatException('missing SessionResp0');
    return SessionResponse0(sr0.integer(1), sr0.bytes(2), sr0.bytes(3));
  }
}

class SessionResponse1 {
  final int status;
  final Uint8List deviceVerifyData;
  SessionResponse1(this.status, this.deviceVerifyData);

  factory SessionResponse1.parse(List<int> data) {
    final sr1 = _sec1Payload(data, expectType: 3).message(23);
    if (sr1 == null) throw PbFormatException('missing SessionResp1');
    return SessionResponse1(sr1.integer(1), sr1.bytes(3));
  }
}

PbMessage _sec1Payload(List<int> data, {required int expectType}) {
  final session = PbMessage.parse(data);
  if (session.integer(2) != _secScheme1) {
    throw PbFormatException('robot is not using security scheme 1');
  }
  final sec1 = session.message(11);
  if (sec1 == null || sec1.integer(1) != expectType) {
    throw PbFormatException('unexpected session message');
  }
  return sec1;
}

// ---- wifi_scan.proto --------------------------------------------------------

enum WifiAuth { open, wep, wpaPsk, wpa2Psk, wpaWpa2Psk, wpa2Enterprise, wpa3Psk, wpa2Wpa3Psk, unknown }

WifiAuth _auth(int v) => v >= 0 && v < WifiAuth.values.length - 1 ? WifiAuth.values[v] : WifiAuth.unknown;

class WifiNetwork {
  final String ssid;
  final int rssi;
  final int channel;
  final WifiAuth auth;
  const WifiNetwork({required this.ssid, required this.rssi, required this.channel, required this.auth});

  bool get needsPassword => auth != WifiAuth.open;

  /// 0..4 signal bars from RSSI.
  int get bars => rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : rssi >= -85 ? 1 : 0;

  @override
  String toString() => 'WifiNetwork($ssid, $rssi dBm, ch $channel, $auth)';
}

Uint8List scanStartCommand({bool blocking = true, bool passive = false, int groupChannels = 0, int periodMs = 120}) {
  final cmd = PbWriter()
    ..boolean(1, blocking)
    ..boolean(2, passive)
    ..varint(3, groupChannels)
    ..varint(4, periodMs);
  return (PbWriter()
        ..varint(1, 0) // TypeCmdScanStart
        ..message(10, cmd))
      .toBytes();
}

Uint8List scanStatusCommand() => (PbWriter()
      ..varint(1, 2) // TypeCmdScanStatus
      ..message(12, PbWriter()))
    .toBytes();

Uint8List scanResultCommand(int startIndex, int count) {
  final cmd = PbWriter()
    ..varint(1, startIndex)
    ..varint(2, count);
  return (PbWriter()
        ..varint(1, 4) // TypeCmdScanResult
        ..message(14, cmd))
      .toBytes();
}

PbMessage _scanPayload(List<int> data, int expectType) {
  final p = PbMessage.parse(data);
  if (p.integer(1) != expectType) throw PbFormatException('unexpected scan response');
  final status = p.integer(2);
  if (status != 0) throw PbFormatException('scan failed: ${statusNames[status] ?? status}');
  return p;
}

void parseScanStartResponse(List<int> data) => _scanPayload(data, 1);

({bool finished, int count}) parseScanStatusResponse(List<int> data) {
  final r = _scanPayload(data, 3).message(13);
  return (finished: r?.boolean(1) ?? false, count: r?.integer(2) ?? 0);
}

List<WifiNetwork> parseScanResultResponse(List<int> data) {
  final r = _scanPayload(data, 5).message(15);
  if (r == null) return const [];
  return [
    for (final e in r.messages(1))
      WifiNetwork(
        ssid: utf8.decode(e.bytes(1), allowMalformed: true),
        channel: e.integer(2),
        rssi: e.int32(3),
        auth: _auth(e.integer(5)),
      ),
  ];
}

// ---- wifi_config.proto ------------------------------------------------------

enum WifiState { connected, connecting, disconnected, connectionFailed }

enum WifiFailReason { authError, networkNotFound, none }

class WifiStatus {
  final WifiState state;
  final WifiFailReason failReason;
  final String ipAddress;
  const WifiStatus(this.state, {this.failReason = WifiFailReason.none, this.ipAddress = ''});

  @override
  String toString() => 'WifiStatus($state, $failReason, $ipAddress)';
}

Uint8List getStatusCommand() => (PbWriter()
      ..varint(1, 0) // TypeCmdGetStatus
      ..message(10, PbWriter()))
    .toBytes();

Uint8List setConfigCommand(String ssid, String passphrase) {
  final cmd = PbWriter()
    ..bytes(1, utf8.encode(ssid))
    ..bytes(2, utf8.encode(passphrase));
  return (PbWriter()
        ..varint(1, 2) // TypeCmdSetConfig
        ..message(12, cmd))
      .toBytes();
}

Uint8List applyConfigCommand() => (PbWriter()
      ..varint(1, 4) // TypeCmdApplyConfig
      ..message(14, PbWriter()))
    .toBytes();

int _respStatus(List<int> data, int expectType, int field) {
  final p = PbMessage.parse(data);
  if (p.integer(1) != expectType) throw PbFormatException('unexpected config response');
  return p.message(field)?.integer(1) ?? 0;
}

void parseSetConfigResponse(List<int> data) {
  final s = _respStatus(data, 3, 13);
  if (s != 0) throw PbFormatException('robot rejected the Wi-Fi settings (${statusNames[s] ?? s})');
}

void parseApplyConfigResponse(List<int> data) {
  final s = _respStatus(data, 5, 15);
  if (s != 0) throw PbFormatException('robot could not apply the Wi-Fi settings (${statusNames[s] ?? s})');
}

WifiStatus parseGetStatusResponse(List<int> data) {
  final p = PbMessage.parse(data);
  if (p.integer(1) != 1) throw PbFormatException('unexpected status response');
  final r = p.message(11);
  if (r == null) return const WifiStatus(WifiState.disconnected);
  final stateIndex = r.integer(2);
  final state = stateIndex < WifiState.values.length ? WifiState.values[stateIndex] : WifiState.disconnected;
  final reason = r.has(10)
      ? (r.integer(10) == 1 ? WifiFailReason.networkNotFound : WifiFailReason.authError)
      : WifiFailReason.none;
  final ip = r.message(11)?.bytes(1);
  return WifiStatus(state, failReason: reason, ipAddress: ip == null ? '' : utf8.decode(ip, allowMalformed: true));
}
