// What sort of device something is, guessed from the name it gives the
// router, unless you pick it yourself.

enum DeviceKind { phone, tablet, computer, tv, speaker, console, smartHome, camera, printer, router, other }

String kindLabel(DeviceKind k) => switch (k) {
      DeviceKind.phone => 'Phone',
      DeviceKind.tablet => 'Tablet',
      DeviceKind.computer => 'Computer',
      DeviceKind.tv => 'TV / streaming',
      DeviceKind.speaker => 'Smart speaker',
      DeviceKind.console => 'Game console',
      DeviceKind.smartHome => 'Smart home',
      DeviceKind.camera => 'Camera',
      DeviceKind.printer => 'Printer',
      DeviceKind.router => 'Router / extender',
      DeviceKind.other => 'Other',
    };

// Checked in order; the first match wins.
final _patterns = <(DeviceKind, RegExp)>[
  (DeviceKind.router, RegExp(r'linksys|tp-?link|router|extender|repeater|deco|mesh|netgear|asus-?rt|archer|velop|orbi')),
  (DeviceKind.tablet, RegExp(r'ipad|tablet|\btab\b|galaxy-?tab|kindle|lenovo-?tb|mipad|matepad')),
  (DeviceKind.tv, RegExp(r'\btv\b|-tv|tv-|bravia|roku|fire-?tv|firestick|chromecast|mibox|mi-?box|shield|appletv|apple-tv|webos|tizen|smarttv|hisense|tcl')),
  (DeviceKind.speaker, RegExp(r'echo|alexa|nest-?(mini|hub|audio)|google-?home|homepod|sonos')),
  (DeviceKind.console, RegExp(r'playstation|\bps[345]\b|xbox|nintendo')),
  (DeviceKind.camera, RegExp(r'cam\b|camera|ipcam|tapo-?c|ezviz|imou|ring-|arlo|wyze')),
  (DeviceKind.printer, RegExp(r'printer|epson|canon|brother|hp[0-9a-f]{6}|laserjet|deskjet|officejet')),
  (DeviceKind.smartHome,
      RegExp(r'esp[-_]?(32|8266)?|tasmota|shelly|tuya|sonoff|smart-?plug|plug|bulb|lamp|wiz|hue|switchbot|meross|tapo-?[pl]|kasa|fridge|washer|vacuum|roborock')),
  (DeviceKind.computer, RegExp(r'laptop|desktop|macbook|imac|mac-?mini|\bpc\b|-pc|pc-|thinkpad|surface|ubuntu|linux|windows|chromebook')),
  (DeviceKind.phone,
      RegExp(r'iphone|android|galaxy|\bsm-|redmi|poco|xiaomi|vivo|oppo|realme|oneplus|pixel|moto|nokia|huawei|honor|infinix|tecno|iqoo|nothing|^v\d{4}$|^cph\d{4}$|^rmx\d{4}$')),
];

DeviceKind guessKind(String hostname) {
  final h = hostname.trim().toLowerCase();
  if (h.isEmpty) return DeviceKind.other;
  for (final (kind, re) in _patterns) {
    if (re.hasMatch(h)) return kind;
  }
  return DeviceKind.other;
}

/// Phones and computers make up a "private" MAC address per network. Such a
/// device is the same each visit on that network, but its maker can't be
/// told from the address. Marked by the second bit of the first byte.
bool isPrivateMac(String mac) {
  final first = int.tryParse(mac.length >= 2 ? mac.substring(0, 2) : '', radix: 16);
  return first != null && first & 0x02 != 0;
}
