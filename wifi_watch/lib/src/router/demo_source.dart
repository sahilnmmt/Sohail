// A pretend home network, so the app can be tried without a router.
import 'dart:math';

import 'router_source.dart';

class _DemoDevice {
  final String mac;
  final String ip;
  final String hostname;
  final Link link;

  /// Typical download speed in bytes per second while active.
  final double typicalDown;
  final double upShare;
  int totalDown = 0;
  int totalUp = 0;
  double down = 0;
  double up = 0;
  bool online = true;

  _DemoDevice(this.mac, this.ip, this.hostname, this.link, this.typicalDown, this.upShare);
}

class DemoSource implements RouterSource {
  final Random _rng;
  final DateTime Function() _now;
  DateTime? _last;
  int _polls = 0;

  final List<_DemoDevice> _devices = [
    _DemoDevice('3C:2E:F9:10:22:01', '192.168.0.101', 'V2219', Link.wifi5g, 400e3, 0.15),
    _DemoDevice('A4:5E:60:31:7B:02', '192.168.0.102', 'Living-Room-TV', Link.wifi5g, 1.6e6, 0.02),
    _DemoDevice('F0:18:98:44:0C:03', '192.168.0.103', 'Laptop', Link.wifi5g, 700e3, 0.3),
    _DemoDevice('B8:27:EB:52:9A:04', '192.168.0.104', 'Linksys06204', Link.wired, 50e3, 0.1),
    _DemoDevice('DC:A6:32:66:1D:05', '192.168.0.105', 'Tablet', Link.wifi2g, 250e3, 0.1),
    _DemoDevice('50:C7:BF:70:3E:06', '192.168.0.106', '', Link.wifi2g, 2e3, 0.5),
  ];

  /// Joins after a few polls, to show the new-device alert.
  final _visitor = _DemoDevice('7A:11:42:8D:E0:07', '192.168.0.120', 'Galaxy-A15', Link.wifi2g, 300e3, 0.2);

  DemoSource({Random? rng, DateTime Function()? now})
      : _rng = rng ?? Random(),
        _now = now ?? DateTime.now;

  @override
  String get name => 'Demo network';

  @override
  Future<RouterSnapshot> fetch() async {
    final now = _now();
    final dt = _last == null ? 0.0 : now.difference(_last!).inMilliseconds / 1000;
    _last = now;
    if (++_polls == 6) _devices.add(_visitor);

    final clients = <ClientInfo>[];
    for (final d in _devices) {
      // Devices come and go a little; the router and phone stay.
      if (d.link != Link.wired && d.hostname != 'V2219' && _rng.nextDouble() < 0.02) d.online = !d.online;
      if (!d.online) continue;
      // Bursty traffic: mostly idle, sometimes busy.
      final busy = _rng.nextDouble() < 0.6;
      d.down = busy ? d.typicalDown * (0.3 + _rng.nextDouble() * 1.4) : d.typicalDown * 0.02 * _rng.nextDouble();
      d.up = d.down * d.upShare * (0.5 + _rng.nextDouble());
      d.totalDown += (d.down * dt).round();
      d.totalUp += (d.up * dt).round();
      clients.add(ClientInfo(
        mac: d.mac,
        ip: d.ip,
        hostname: d.hostname,
        link: d.link,
        downBps: d.down,
        upBps: d.up,
        totalDown: d.totalDown,
        totalUp: d.totalUp,
      ));
    }
    return RouterSnapshot(now, clients);
  }

  @override
  Future<void> close() async {}
}
