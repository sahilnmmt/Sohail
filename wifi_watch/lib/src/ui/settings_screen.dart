import 'package:flutter/material.dart';

import '../settings.dart';
import '../version.dart';
import 'connection_test_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  final Future<void> Function() onForgetHistory;

  const SettingsScreen({super.key, required this.settings, required this.onSave, required this.onForgetHistory});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SourceKind _source = widget.settings.source;
  late int _poll = widget.settings.pollSeconds;
  late final _host = TextEditingController(text: widget.settings.host);
  late final _user = TextEditingController(text: widget.settings.username);
  late final _password = TextEditingController(text: widget.settings.password);
  late final _netLimit = TextEditingController(text: widget.settings.networkLimitMb?.toString() ?? '');
  bool _showPassword = false;

  AppSettings get _edited {
    final s = widget.settings.copyWith(
      source: _source,
      host: _host.text.trim(),
      username: _user.text.trim(),
      password: _password.text,
      pollSeconds: _poll,
      networkLimitMb: () {
        final mb = int.tryParse(_netLimit.text.trim());
        return mb == null || mb <= 0 ? null : mb;
      },
    );
    // A different router may speak a different protocol: search again.
    return s.sameRouter(widget.settings) ? s : s.copyWith(variant: () => null);
  }

  Future<void> _save() async {
    await widget.onSave(_edited);
    if (mounted) Navigator.pop(context);
  }

  void _test() {
    final s = _edited;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConnectionTestScreen(host: s.host, username: s.username, password: s.password),
    ));
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear usage history?'),
        content: const Text('Removes every device and all usage recorded so far. Names you gave devices are lost too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await widget.onForgetHistory();
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _password.dispose();
    _netLimit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final router = _source == SourceKind.tplink;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Where devices come from', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<SourceKind>(
            segments: const [
              ButtonSegment(value: SourceKind.tplink, icon: Icon(Icons.router_outlined), label: Text('My router')),
              ButtonSegment(value: SourceKind.demo, icon: Icon(Icons.science_outlined), label: Text('Demo')),
            ],
            selected: {_source},
            onSelectionChanged: (s) => setState(() => _source = s.single),
          ),
          const SizedBox(height: 8),
          Text(
            router
                ? 'Reads your TP-Link router the way its web page does. The phone must be on your home Wi-Fi.'
                : 'Pretend devices, to try the app without a router.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (router) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Router address',
                helperText: 'Usually 192.168.0.1 or 192.168.1.1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'User name',
                helperText: 'Usually admin. Some ISP routers use user.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Router admin password',
                helperText: 'The one for the router web page, not the Wi-Fi password.',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _test,
              icon: const Icon(Icons.network_check),
              label: const Text('Test connection'),
            ),
          ],
          const SizedBox(height: 24),
          Text('Check every', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 5, label: Text('5 s')),
              ButtonSegment(value: 10, label: Text('10 s')),
              ButtonSegment(value: 30, label: Text('30 s')),
              ButtonSegment(value: 60, label: Text('1 min')),
            ],
            selected: {_poll},
            onSelectionChanged: (s) => setState(() => _poll = s.single),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _netLimit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Daily limit for the whole network',
              suffixText: 'MB',
              helperText: 'Optional. Warns when all devices together use more in a day. 1000 MB = 1 GB.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 32),
          TextButton.icon(
            onPressed: _forget,
            icon: Icon(Icons.delete_outline, color: scheme.error),
            label: Text('Clear usage history', style: TextStyle(color: scheme.error)),
          ),
          const SizedBox(height: 16),
          Text('WiFi Watch build $appBuild', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
