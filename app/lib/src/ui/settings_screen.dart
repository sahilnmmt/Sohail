import 'package:flutter/material.dart';

import '../messaging/message.dart';
import '../settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  const SettingsScreen({super.key, required this.settings, required this.onSave});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.settings.displayName);
  late final _group = TextEditingController(text: widget.settings.group);
  late final _host = TextEditingController(text: widget.settings.host);
  late final _port = TextEditingController(text: '${widget.settings.port}');
  late final _user = TextEditingController(text: widget.settings.username);
  late final _pass = TextEditingController(text: widget.settings.password);
  late bool _tls = widget.settings.tls;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _group, _host, _port, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    await widget.onSave(widget.settings.copyWith(
      displayName: _name.text.trim(),
      group: _group.text.trim(),
      host: _host.text.trim(),
      port: int.parse(_port.text.trim()),
      tls: _tls,
      username: _user.text.trim(),
      password: _pass.text,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('You', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Your name on the robots', helperText: 'Shown as the sender, up to 16 bytes'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a name'
                  : isValidName(v.trim())
                      ? null
                      : 'Too long (16 bytes max)',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _group,
              decoration: const InputDecoration(
                  labelText: 'Family group', helperText: 'Must match the Group id set on your robots'),
              validator: (v) => isValidId((v ?? '').trim()) ? null : 'Letters, digits, - and _ only (max 24)',
            ),
            const SizedBox(height: 24),
            Text('Message server', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Server address', hintText: '192.168.1.10', helperText: 'Same as the robots\' broker'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the server address' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
              validator: (v) {
                final p = int.tryParse((v ?? '').trim());
                return p == null || p < 1 || p > 65535 ? 'Enter a port from 1 to 65535' : null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use TLS'),
              subtitle: const Text('For servers outside your home network (usually port 8883)'),
              value: _tls,
              onChanged: (v) => setState(() {
                _tls = v;
                if (v && _port.text == '1883') _port.text = '8883';
                if (!v && _port.text == '8883') _port.text = '1883';
              }),
            ),
            TextFormField(controller: _user, decoration: const InputDecoration(labelText: 'Username (optional)')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 24),
            Text('This phone appears to the robots as ${widget.settings.clientId}.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Connecting...' : 'Save and connect'),
            ),
          ],
        ),
      ),
    );
  }
}
