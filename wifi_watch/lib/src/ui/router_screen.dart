// Add or change one router.
import 'package:flutter/material.dart';

import '../settings.dart';
import 'connection_test_screen.dart';

class RouterScreen extends StatefulWidget {
  final RouterSetup router;
  final bool isNew;

  /// Null when this router can't be removed (the only one).
  final VoidCallback? onDelete;

  const RouterScreen({super.key, required this.router, this.isNew = false, this.onDelete});

  @override
  State<RouterScreen> createState() => _RouterScreenState();
}

class _RouterScreenState extends State<RouterScreen> {
  late RouterKind _kind = widget.router.kind;
  late final _name = TextEditingController(text: widget.router.name);
  late final _host = TextEditingController(text: widget.router.host);
  late final _user = TextEditingController(text: widget.router.username);
  late final _password = TextEditingController(text: widget.router.password);
  bool _showPassword = false;

  /// What the connection test found, for that address and password.
  ({String host, String password, String variant, String user})? _tested;

  RouterSetup get _edited {
    final r = widget.router.copyWith(
      name: _name.text.trim(),
      kind: _kind,
      host: _host.text.trim(),
      username: _user.text.trim(),
      password: _password.text,
    );
    final t = _tested;
    if (_kind == RouterKind.tplink &&
        t != null &&
        t.host == r.host &&
        t.password == r.password &&
        (r.username.isEmpty || r.username == t.user)) {
      return r.copyWith(variant: () => t.variant, username: t.user);
    }
    // A different router may speak a different protocol: search again.
    return r.sameLogin(widget.router) ? r : r.copyWith(variant: () => null);
  }

  void _test() {
    final r = _edited;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConnectionTestScreen(
        host: r.host,
        username: r.username,
        password: r.password,
        kind: r.kind,
        onConnected: (variant, user) {
          _tested = (host: r.host, password: r.password, variant: variant, user: user);
          if (mounted) setState(() => _user.text = user);
        },
      ),
    ));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${widget.router.displayName}?'),
        content: const Text('The app stops reading this router. Devices and usage already recorded stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.onDelete!();
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final real = _kind != RouterKind.demo;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Add router' : 'Router'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, _edited), child: const Text('DONE'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Upstairs, Downstairs',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Type', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<RouterKind>(
            segments: const [
              ButtonSegment(value: RouterKind.tplink, label: Text('TP-Link')),
              ButtonSegment(value: RouterKind.linksys, label: Text('Linksys')),
              ButtonSegment(value: RouterKind.demo, label: Text('Demo')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.single),
          ),
          const SizedBox(height: 8),
          Text(
            switch (_kind) {
              RouterKind.tplink => 'Reads the router the way its web page does: devices and data used per device.',
              RouterKind.linksys => 'Linksys Smart Wi-Fi (EA, MR, MX, Velop): the devices on it. Linksys does not '
                  'report data used per device. In router mode the phone reaches it only from its own Wi-Fi.',
              RouterKind.demo => 'Pretend devices, to try the app without a router.',
            },
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (real) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'Router address',
                helperText: _kind == RouterKind.linksys
                    ? 'Usually 192.168.1.1 (myrouter.local)'
                    : 'Usually 192.168.0.1 or 192.168.1.1',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _user,
              decoration: InputDecoration(
                labelText: 'User name',
                hintText: _kind == RouterKind.linksys ? 'admin' : 'Leave empty if the router asks only for a password',
                helperText: _kind == RouterKind.linksys
                    ? 'Empty means admin.'
                    : 'Not your TP-Link ID email. Empty tries user, then admin.',
                border: const OutlineInputBorder(),
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
          if (widget.onDelete != null && !widget.isNew) ...[
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: scheme.error),
              label: Text('Remove this router', style: TextStyle(color: scheme.error)),
            ),
          ],
        ],
      ),
    );
  }
}
