// Tries the router step by step and shows what happened, so a problem can be
// copied and sent for help. The password never appears in the log.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../router/tplink_client.dart';
import '../version.dart';

class ConnectionTestScreen extends StatefulWidget {
  final String host;
  final String username;
  final String password;

  /// Called with the login method and user name that worked.
  final void Function(String variant, String user)? onConnected;

  const ConnectionTestScreen(
      {super.key, required this.host, required this.username, required this.password, this.onConnected});

  @override
  State<ConnectionTestScreen> createState() => _ConnectionTestScreenState();
}

class _ConnectionTestScreenState extends State<ConnectionTestScreen> {
  late final List<String> _lines = ['WiFi Watch build $appBuild, connection test, router ${widget.host}, user "${widget.username.trim().isEmpty ? '(automatic)' : widget.username}"'];
  bool _running = true;
  bool? _ok;

  /// The router has traffic statistics and they are off.
  bool _statsOff = false;
  TpVariant? _variant;
  String? _user;

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
      await client.describeHistoryTables();
      final snap = await client.fetch();
      _log('Devices online: ${snap.clients.length}');
      for (final c in snap.clients) {
        _log('  ${c.hostname.isEmpty ? '(no name)' : c.hostname} ${c.ip} ${c.link.name}${c.vendor.isEmpty ? '' : ' (${c.vendor})'}'
            '${c.downBps != null ? ' ↓${formatSpeed(c.downBps!)}' : ''}'
            '${c.totalDown != null ? ' total ${formatBytes(c.totalDown! + (c.totalUp ?? 0))}' : ''}');
      }
      final counted = snap.clients.where((c) => (c.totalDown ?? 0) + (c.totalUp ?? 0) > 0 || (c.downBps ?? 0) > 0);
      _log(counted.isEmpty
          ? 'Per-device traffic: not found. Device list works; send this log to add usage for this model.'
          : 'Per-device traffic for: ${counted.map((c) => c.hostname.isEmpty ? c.ip : c.hostname).join(', ')}');
      final stats = await client.trafficStatsEnabled();
      if (stats != null) _log('Router traffic statistics: ${stats ? 'on' : 'off'}');
      _statsOff = stats == false;
      _variant = client.variant;
      _user = client.user;
      _ok = true;
      widget.onConnected?.call(client.variant!.id, client.user ?? widget.username);
      _log('Works: ${client.variant} as "${client.user}". Go back and tap SAVE to keep it.');
    } catch (e) {
      _log('FAILED: $e');
      _ok = false;
    } finally {
      await client.close();
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _turnOnStats() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn on traffic statistics?'),
        content: const Text('This changes a setting on your router: it starts counting the data each device uses, '
            'wired devices too. It is the "Traffic Statistics" option of the router\'s own web page, and you can '
            'turn it off there again. Some routers run a little slower with it on.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Turn on')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _running = true;
      _statsOff = false;
    });
    final client = TplinkClient(
        host: widget.host, username: _user ?? widget.username, password: widget.password, variant: _variant, log: _log);
    try {
      await client.connect();
      await client.setTrafficStats(true);
      _log('Router traffic statistics: ${await client.trafficStatsEnabled() == true ? 'on' : 'still off'}');
      // Give the router one counting interval, then see what it reports.
      await Future<void>.delayed(const Duration(seconds: 12));
      await client.describeDeviceFields();
    } catch (e) {
      _log('Could not turn traffic statistics on: $e');
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
          if (_statsOff && !_running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _turnOnStats,
                  icon: const Icon(Icons.query_stats),
                  label: const Text('Turn on traffic statistics'),
                ),
              ),
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
