// What every router connection gives the app: the devices it can see right
// now, with live speed and byte counters when the router reports them.

enum Link { wired, wifi2g, wifi5g, wifi6g, guest, unknown }

String linkLabel(Link l) => switch (l) {
      Link.wired => 'Wired',
      Link.wifi2g => '2.4 GHz',
      Link.wifi5g => '5 GHz',
      Link.wifi6g => '6 GHz',
      Link.guest => 'Guest Wi-Fi',
      Link.unknown => 'Unknown',
    };

class ClientInfo {
  /// Upper case, colon separated, e.g. `AA:BB:CC:00:11:22`.
  final String mac;
  final String ip;
  final String hostname;

  /// The maker, if the router knows it, e.g. "vivo Mobile Communication".
  final String vendor;
  final Link link;

  /// Live speed in bytes per second, if the router reports it.
  final double? downBps;
  final double? upBps;

  /// Byte counters since the router started counting, if it reports them.
  /// Down is what the device received, up is what it sent.
  final int? totalDown;
  final int? totalUp;

  /// The router that reported it, when there are several.
  final String via;

  const ClientInfo({
    required this.mac,
    required this.ip,
    required this.hostname,
    this.vendor = '',
    required this.link,
    this.downBps,
    this.upBps,
    this.totalDown,
    this.totalUp,
    this.via = '',
  });

  ClientInfo withVia(String router) => ClientInfo(
        mac: mac,
        ip: ip,
        hostname: hostname,
        vendor: vendor,
        link: link,
        downBps: downBps,
        upBps: upBps,
        totalDown: totalDown,
        totalUp: totalUp,
        via: router,
      );

  /// Something the router measured: speed or byte counters.
  bool get hasTraffic => totalDown != null || totalUp != null || downBps != null;
}

class RouterSnapshot {
  final DateTime at;
  final List<ClientInfo> clients;
  const RouterSnapshot(this.at, this.clients);
}

abstract class RouterSource {
  /// Shown in the status bar, e.g. "TP-Link XX530v" or "Demo network".
  String get name;

  Future<RouterSnapshot> fetch();

  Future<void> close();
}

/// `aa-bb-cc-00-11-22` and `aabb.cc00.1122` both become `AA:BB:CC:00:11:22`.
String normalizeMac(String raw) {
  final hex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  if (hex.length != 12) return raw.trim().toUpperCase();
  return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
}
