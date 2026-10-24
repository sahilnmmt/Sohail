// The robot setup flow, independent of Bluetooth so it can be tested:
// find robot -> enter code -> pick Wi-Fi -> wait until it joins.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_ids.dart';
import 'provisioner.dart';

class FoundRobot {
  final String id;
  final String name;
  final int rssi;
  const FoundRobot({required this.id, required this.name, required this.rssi});

  /// "PROV_SOHAIL_A1B2" -> "Sohail A1B2".
  String get label {
    final rest = name.startsWith(provNamePrefix) ? name.substring(provNamePrefix.length) : name;
    final parts = rest.split('_').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return name;
    final first = parts.first;
    return [first[0] + first.substring(1).toLowerCase(), ...parts.skip(1)].join(' ');
  }
}

typedef RobotScanner = Stream<FoundRobot> Function();
typedef RobotConnector = Future<ProvTransport> Function(String robotId);
typedef PermissionCheck = Future<String?> Function();

enum SetupStep { permissions, scanning, code, connecting, chooseNetwork, joining, done }

class SetupController extends ChangeNotifier {
  final RobotScanner scanner;
  final RobotConnector connector;
  final PermissionCheck ensurePermissions;
  final Duration pollInterval;

  SetupController({
    required this.scanner,
    required this.connector,
    required this.ensurePermissions,
    this.pollInterval = const Duration(seconds: 1),
  });

  SetupStep step = SetupStep.permissions;
  String? error;
  final List<FoundRobot> robots = [];
  FoundRobot? robot;
  List<WifiNetwork> networks = const [];
  String? joinedNetwork;
  String? robotIp;

  StreamSubscription<FoundRobot>? _scan;
  ProvTransport? _transport;
  Provisioner? _provisioner;
  bool _disposed = false;

  void _set(SetupStep s, {String? err}) {
    step = s;
    error = err;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    _set(SetupStep.permissions);
    final problem = await ensurePermissions();
    if (problem != null) {
      _set(SetupStep.permissions, err: problem);
      return;
    }
    robots.clear();
    _set(SetupStep.scanning);
    _stopScan();
    _scan = scanner().listen((r) {
      final i = robots.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        robots[i] = r;
      } else {
        robots.add(r);
      }
      robots.sort((a, b) => b.rssi.compareTo(a.rssi));
      if (!_disposed) notifyListeners();
    }, onError: (Object e) => _set(SetupStep.scanning, err: 'Bluetooth scan failed: $e'));
  }

  void choose(FoundRobot r) {
    robot = r;
    _set(SetupStep.code);
  }

  Future<void> submitCode(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _set(SetupStep.code, err: 'Enter the 6 digits shown on the robot.');
      return;
    }
    _stopScan();
    _set(SetupStep.connecting);
    try {
      await _closeTransport();
      _transport = await connector(robot!.id);
      _provisioner = Provisioner(_transport!, code, pollInterval: pollInterval);
      await _provisioner!.startSession();
      networks = await _provisioner!.scan();
      _set(SetupStep.chooseNetwork);
    } on ProvisioningException catch (e) {
      await _closeTransport();
      _set(SetupStep.code, err: e.message);
    } catch (e) {
      await _closeTransport();
      _set(SetupStep.code, err: 'Something went wrong talking to the robot: $e');
    }
  }

  Future<void> refreshNetworks() async {
    final p = _provisioner;
    if (p == null) return;
    try {
      networks = await p.scan();
      _set(SetupStep.chooseNetwork);
    } on ProvisioningException catch (e) {
      _set(SetupStep.chooseNetwork, err: e.message);
    }
  }

  Future<void> join(String ssid, String password) async {
    final p = _provisioner;
    if (p == null) return;
    _set(SetupStep.joining);
    try {
      await p.sendWifi(ssid, password);
      final status = await p.waitForConnection();
      joinedNetwork = ssid;
      robotIp = status.ipAddress;
      await _closeTransport();
      _set(SetupStep.done);
    } on ProvisioningException catch (e) {
      _set(SetupStep.chooseNetwork, err: e.message);
    } catch (e) {
      _set(SetupStep.chooseNetwork, err: 'The robot stopped answering: $e');
    }
  }

  /// Stops scanning without waiting: a slow stop-scan on the phone must not
  /// hold up connecting to the robot.
  void _stopScan() {
    final scan = _scan;
    _scan = null;
    if (scan != null) unawaited(scan.cancel());
  }

  Future<void> _closeTransport() async {
    final t = _transport;
    _transport = null;
    _provisioner = null;
    if (t != null) {
      try {
        await t.close();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopScan();
    _closeTransport();
    super.dispose();
  }
}
