import 'package:flutter/material.dart';

import '../settings.dart';
import '../version.dart';
import 'router_screen.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSave;
  final Future<void> Function() onForgetHistory;

  const SettingsScreen({super.key, required this.settings, required this.onSave, required this.onForgetHistory});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late List<RouterSetup> _routers = [...widget.settings.routers];
  late int _poll = widget.settings.pollSeconds;
  late final _netLimit = TextEditingController(text: widget.settings.networkLimitMb?.toString() ?? '');

  AppSettings get _edited => widget.settings.copyWith(
        routers: _routers,
        pollSeconds: _poll,
        networkLimitMb: () {
          final mb = int.tryParse(_netLimit.text.trim());
          return mb == null || mb <= 0 ? null : mb;
        },
      );

  Future<void> _save() async {
    await widget.onSave(_edited);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _edit(RouterSetup router, {bool isNew = false}) async {
    final changed = await Navigator.of(context).push(MaterialPageRoute<RouterSetup>(
      builder: (_) => RouterScreen(
        router: router,
        isNew: isNew,
        onDelete: _routers.length > 1 ? () => setState(() => _routers.removeWhere((r) => r.id == router.id)) : null,
      ),
    ));
    if (changed == null || !mounted) return;
    setState(() {
      if (isNew) {
        // Pretend devices don't mix with real ones: a real router replaces
        // the demo.
        if (changed.kind != RouterKind.demo) _routers.removeWhere((r) => r.kind == RouterKind.demo);
        _routers = [..._routers, changed];
      } else {
        _routers = [for (final r in _routers) r.id == changed.id ? changed : r];
      }
    });
  }

  void _add() => _edit(
        RouterSetup(
          id: RouterSetup.newId(),
          kind: _routers.any((r) => r.kind == RouterKind.tplink) ? RouterKind.linksys : RouterKind.tplink,
          host: _routers.any((r) => r.kind == RouterKind.tplink) ? '192.168.1.1' : '192.168.0.1',
        ),
        isNew: true,
      );

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
    _netLimit.dispose();
    super.dispose();
  }

  static IconData _icon(RouterKind k) => switch (k) {
        RouterKind.demo => Icons.science_outlined,
        _ => Icons.router_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [TextButton(onPressed: _save, child: const Text('SAVE'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Routers', style: t.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Add each router on your network. Devices from all of them show in one list.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final r in _routers)
            Card(
              child: ListTile(
                leading: Icon(_icon(r.kind)),
                title: Text(r.displayName),
                subtitle: Text(r.kind == RouterKind.demo ? 'Pretend devices' : '${routerKindLabel(r.kind)} · ${r.host}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _edit(r),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add router')),
          ),
          const SizedBox(height: 16),
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
