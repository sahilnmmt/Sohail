// ProvTransport over Bluetooth LE: each protocomm request is a GATT write to
// the endpoint's characteristic followed by a read of the reply.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble_ids.dart';
import 'provisioner.dart';

class BleProvTransport implements ProvTransport {
  final FlutterReactiveBle _ble;
  final String deviceId;
  final StreamSubscription<ConnectionStateUpdate> _connection;
  bool _lost = false;

  BleProvTransport._(this._ble, this.deviceId, this._connection);

  static Future<BleProvTransport> connect(FlutterReactiveBle ble, String deviceId,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final connected = Completer<void>();
    late BleProvTransport transport;
    final sub = ble.connectToDevice(id: deviceId, connectionTimeout: timeout).listen((u) {
      if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) {
        connected.complete();
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        if (!connected.isCompleted) {
          connected.completeError(ProvisioningException('Could not connect to the robot. Move closer and try again.'));
        } else {
          transport._lost = true;
        }
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) {
        connected.completeError(ProvisioningException('Could not connect to the robot ($e).'));
      }
    });
    transport = BleProvTransport._(ble, deviceId, sub);
    try {
      await connected.future.timeout(timeout + const Duration(seconds: 2));
      // Bigger packets: session and scan replies are larger than the default 20 bytes.
      try {
        await ble.requestMtu(deviceId: deviceId, mtu: 512);
      } catch (_) {/* iOS negotiates by itself */}
      await ble.discoverAllServices(deviceId);
      final services = await ble.getDiscoveredServices(deviceId);
      final svc = Uuid.parse(provServiceUuid);
      if (!services.any((s) => s.id == svc)) {
        throw ProvisioningException('This device is not a Sohail robot in setup mode.');
      }
      return transport;
    } catch (e) {
      await sub.cancel();
      if (e is ProvisioningException) rethrow;
      throw ProvisioningException('Could not connect to the robot ($e).');
    }
  }

  QualifiedCharacteristic _characteristic(String endpoint) => QualifiedCharacteristic(
        serviceId: Uuid.parse(provServiceUuid),
        characteristicId: Uuid.parse(provEndpointUuid(endpoint)),
        deviceId: deviceId,
      );

  @override
  Future<Uint8List> send(String endpoint, Uint8List data) async {
    if (_lost) throw ProvisioningException('The Bluetooth connection to the robot was lost.');
    final c = _characteristic(endpoint);
    try {
      await _ble.writeCharacteristicWithResponse(c, value: data);
      return Uint8List.fromList(await _ble.readCharacteristic(c));
    } on Exception catch (e) {
      // A GATT error here usually means the robot rejected the request.
      throw TransportRejected('$endpoint: $e');
    }
  }

  @override
  Future<void> close() => _connection.cancel();
}
