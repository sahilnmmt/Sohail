// Tries the router step by step and shows what happened, so a problem can be
// copied and sent for help. The password never appears in the log.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../router/tplink_client.dart';

class ConnectionTestScreen extends StatefulWidget {
  final String host;
  final String username;
  final String password;
  const ConnectionTestScreen({super.key, required this.host, required this.username, required this.password});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  late final List<String> _lines = ['WiFi Watch connection test, router ${widget.host}, user "${widget.username}"'];
  bool _running = true;
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _log(String line) {
    if (!mounted) return;
    final pw = widget.password;
    setState(() => _lines.add(pw.isEmpty ? line : line.replaceAll(pw, '***')));
  }

  Future<void> _run() async {
    final client = TplinkClient(host: widget.host, username: widget.username, password: widget.password, log: _log);
    try {
      await client.connect();
      await client.describeDeviceFields();
      final snap = await client.fetch();
      _log('Devices online: ${snap.clients.length}');
      for (final c in snap.clients) {
        _log('  ${c.hostname.isEmpty ? '(no name)' : c.hostname} ${c.ip} ${c.link.name}'
            '${c.downBps != null ? ' ↓${formatSpeed(c.downBps!)}' : ''}'
            '${c.totalDown != null ? ' total ${formatBytes(c.totalDown! + (c.totalUp ?? 0))}' : ''}');
      }
      final hasTraffic = snap.clients.any((c) => c.downBps != null || c.totalDown != null);
      _log(hasTraffic
          ? 'Per-device traffic: yes'
          : 'Per-device traffic: not found. Device list works; send this log to add usage for this model.');
      _ok = true;
    } catch (e) {
      _log('FAILED: $e');
      _ok = false;
    } finally {
      await client.close();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection test'),
        actions: [
          IconButton(
            tooltip: 'Copy log',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _lines.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Log copied')));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_running) const LinearProgressIndicator(),
          if (_ok != null)
            ListTile(
              leading: Icon(_ok! ? Icons.check_circle : Icons.error, color: _ok! ? scheme.primary : scheme.error),
              title: Text(_ok! ? 'Connected' : 'Could not connect'),
              subtitle: Text(_ok! ? 'Save the settings to start watching.' : 'Copy the log and send it for help.'),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SelectableText(_lines.join('\n'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
