// Drives Wi-Fi setup of a robot over any transport (BLE on phones, the
// ESP-IDF harness in tests): secure session, network scan, credentials,
// and waiting for the robot to join the network.
import 'dart:async';
import 'dart:typed_data';

import 'messages.dart';
import 'protobuf.dart';
import 'security1.dart';

export 'messages.dart' show WifiNetwork, WifiAuth, WifiStatus, WifiState, WifiFailReason;
export 'security1.dart' show ProvisioningException;

/// Sends a request to a named protocomm endpoint and returns the reply.
abstract class ProvTransport {
  Future<Uint8List> send(String endpoint, Uint8List data);
  Future<void> close();
}

/// Thrown by a transport when the robot rejects a request outright.
class TransportRejected implements Exception {
  final String reason;
  TransportRejected(this.reason);
  @override
  String toString() => 'TransportRejected($reason)';
}

class Provisioner {
  final ProvTransport transport;
  final Security1 _security;
  final Duration pollInterval;

  Provisioner(this.transport, String code, {this.pollInterval = const Duration(seconds: 1)})
      : _security = Security1(code);

  /// Establishes the encrypted session using the code on the robot's screen.
  Future<void> startSession() async {
    try {
      final r0 = await transport.send('prov-session', await _security.command0());
      final r1 = await transport.send('prov-session', await _security.command1(r0));
      await _security.verify(r1);
    } on TransportRejected {
      // The robot drops the session when the verify data does not decrypt.
      throw Security1.wrongCode();
    } on PbFormatException catch (e) {
      throw ProvisioningException('The robot sent an unexpected reply (${e.message}).');
    }
  }

  Future<Uint8List> _request(String endpoint, Uint8List plain) async {
    if (!_security.isReady) throw StateError('call startSession() first');
    final reply = await transport.send(endpoint, await _security.encrypt(plain));
    return _security.decrypt(reply);
  }

  /// Networks the robot can see, strongest first, without duplicates.
  Future<List<WifiNetwork>> scan({int pageSize = 4}) async {
    parseScanStartResponse(await _request('prov-scan', scanStartCommand()));
    var status = parseScanStatusResponse(await _request('prov-scan', scanStatusCommand()));
    for (var i = 0; !status.finished && i < 10; i++) {
      await Future<void>.delayed(pollInterval);
      status = parseScanStatusResponse(await _request('prov-scan', scanStatusCommand()));
    }
    final all = <WifiNetwork>[];
    for (var start = 0; start < status.count; start += pageSize) {
      final n = (status.count - start).clamp(0, pageSize);
      all.addAll(parseScanResultResponse(await _request('prov-scan', scanResultCommand(start, n))));
    }
    final best = <String, WifiNetwork>{};
    for (final net in all.where((n) => n.ssid.isNotEmpty)) {
      final seen = best[net.ssid];
      if (seen == null || net.rssi > seen.rssi) best[net.ssid] = net;
    }
    return best.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  /// Sends the network name and password and tells the robot to connect.
  Future<void> sendWifi(String ssid, String password) async {
    if (ssid.isEmpty || ssid.length > 32) throw ProvisioningException('Network names are 1 to 32 characters.');
    if (password.length > 63) throw ProvisioningException('Wi-Fi passwords are at most 63 characters.');
    parseSetConfigResponse(await _request('prov-config', setConfigCommand(ssid, password)));
    parseApplyConfigResponse(await _request('prov-config', applyConfigCommand()));
  }

  Future<WifiStatus> status() async => parseGetStatusResponse(await _request('prov-config', getStatusCommand()));

  /// Polls until the robot is on the network or reports why it is not.
  Future<WifiStatus> waitForConnection({Duration timeout = const Duration(seconds: 30)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final s = await status();
      if (s.state == WifiState.connected) return s;
      if (s.state == WifiState.connectionFailed ||
          (s.state == WifiState.disconnected && s.failReason != WifiFailReason.none)) {
        throw ProvisioningException(s.failReason == WifiFailReason.networkNotFound
            ? 'The robot could not find that network. Is it 2.4 GHz and in range?'
            : 'The Wi-Fi password was wrong. Try again.');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw ProvisioningException('The robot did not join the network in time.');
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
