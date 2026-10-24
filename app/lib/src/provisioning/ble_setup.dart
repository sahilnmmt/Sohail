// Android/iOS Bluetooth pieces of the setup flow.
import 'dart:io';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import 'ble_ids.dart';
import 'ble_transport.dart';
import 'provisioner.dart';
import 'setup_controller.dart';

final _ble = FlutterReactiveBle();

Stream<FoundRobot> scanForRobots() => _ble
    .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency, requireLocationServicesEnabled: false)
    .where((d) => d.name.startsWith(provNamePrefix))
    .map((d) => FoundRobot(id: d.id, name: d.name, rssi: d.rssi));

Future<ProvTransport> connectToRobot(String id) => BleProvTransport.connect(_ble, id);

/// Asks for the Bluetooth permissions scanning needs. Returns a message to
/// show if something is missing, or null when ready.
Future<String?> ensureBluetoothReady() async {
  if (Platform.isAndroid) {
    // Android 12+: nearby-devices permissions. Android 11 and older: location
    // (the manifest only declares it up to API 30, so newer phones skip it).
    final results = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    final scan = results[Permission.bluetoothScan]!;
    final connect = results[Permission.bluetoothConnect]!;
    if (scan.isPermanentlyDenied || connect.isPermanentlyDenied) {
      return 'Bluetooth permission is turned off for Sohail. Allow "Nearby devices" in the app settings.';
    }
    if (!scan.isGranted || !connect.isGranted) {
      return 'Sohail needs the "Nearby devices" permission to find your robot.';
    }
  }
  final status = await _ble.statusStream.firstWhere((s) => s != BleStatus.unknown);
  switch (status) {
    case BleStatus.ready:
      return null;
    case BleStatus.poweredOff:
      return 'Turn on Bluetooth to find your robot.';
    case BleStatus.locationServicesDisabled:
      return 'Turn on Location: older Android versions need it for Bluetooth scanning.';
    case BleStatus.unauthorized:
      return 'Sohail is not allowed to use Bluetooth. Check the app permissions.';
    case BleStatus.unsupported:
      return 'This phone does not support Bluetooth Low Energy.';
    case BleStatus.unknown:
      return 'Bluetooth is not ready yet. Try again.';
  }
}
