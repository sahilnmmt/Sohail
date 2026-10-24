// Bluetooth IDs used by ESP-IDF's wifi_provisioning BLE scheme (v5.x).
// Kept free of Flutter imports so it can be unit-tested.

/// Robots advertise as "PROV_SOHAIL_XXXX" while in setup mode.
const provNamePrefix = 'PROV_';

/// Default service UUID from esp-idf scheme_ble.c (stored LSB first there).
const provServiceUuid = '1775244d-6b43-439b-877c-060f2d9bed07';

/// 16-bit endpoint IDs from esp-idf wifi_provisioning manager.c.
const provEndpointIds = {
  'prov-ctrl': 0xFF4F,
  'prov-scan': 0xFF50,
  'prov-session': 0xFF51,
  'prov-config': 0xFF52,
  'proto-ver': 0xFF53,
};

/// Characteristic UUID of an endpoint: the service UUID with bytes 12-13
/// (little-endian) replaced by the 16-bit ID, i.e. "1775xxxx-...".
String provEndpointUuid(String endpoint) {
  final id = provEndpointIds[endpoint];
  if (id == null) throw ArgumentError.value(endpoint, 'endpoint', 'unknown provisioning endpoint');
  return '${provServiceUuid.substring(0, 4)}${id.toRadixString(16).padLeft(4, '0')}${provServiceUuid.substring(8)}';
}
