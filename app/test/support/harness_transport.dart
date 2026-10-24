// ProvTransport that talks to tool/prov_harness: ESP-IDF's own provisioning
// code running on the host, standing in for a robot.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sohail_app/src/provisioning/provisioner.dart';

String? findHarness() {
  final candidates = [
    Platform.environment['PROV_HARNESS'],
    'tool/prov_harness/build/prov_harness',
  ];
  for (final c in candidates) {
    if (c != null && c.isNotEmpty && File(c).existsSync()) return c;
  }
  return null;
}

class HarnessTransport implements ProvTransport {
  final Process _process;
  final StreamIterator<String> _lines;

  HarnessTransport._(this._process)
      : _lines = StreamIterator(_process.stdout.transform(utf8.decoder).transform(const LineSplitter()));

  static Future<HarnessTransport> start(String path, {required String code, required String wifiPassword}) async {
    final p = await Process.start(path, [code, wifiPassword]);
    p.stderr.drain<void>();
    return HarnessTransport._(p);
  }

  String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _unhex(String s) =>
      Uint8List.fromList([for (var i = 0; i + 1 < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

  @override
  Future<Uint8List> send(String endpoint, Uint8List data) async {
    _process.stdin.writeln('$endpoint ${_hex(data)}');
    await _process.stdin.flush();
    if (!await _lines.moveNext()) throw StateError('harness exited');
    final line = _lines.current;
    if (line.startsWith('ERR')) throw TransportRejected(line);
    return _unhex(line.substring(3));
  }

  /// What the fake radio was told: "ssid=...;password=...;applied=1".
  Future<String> state() async => utf8.decode(await send('harness-state', Uint8List(0)));

  @override
  Future<void> close() async {
    await _process.stdin.close();
    await _process.exitCode;
  }
}
