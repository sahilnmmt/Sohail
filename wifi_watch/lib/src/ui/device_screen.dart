import 'package:flutter/material.dart';

import '../device_kind.dart';
import '../format.dart';
import '../monitor.dart';
import '../router/router_source.dart';
import 'bar_chart.dart';
import 'device_icons.dart';

class DeviceScreen extends StatelessWidget {
  final Monitor monitor;
  final String mac;
  const DeviceScreen({super.key, required this.monitor, required this.mac});

  Future<void> _rename(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "e.g. Mom's phone"),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) monitor.rename(mac, name);
  }

  Future<void> _pickKind(BuildContext context, DeviceKind current, bool chosen) async {
    final picked = await showDialog<(DeviceKind?,)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('What is this device?'),
        children: [
          for (final k in DeviceKind.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (k,)),
              child: Row(children: [
                Icon(kindIcon(k), size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(kindLabel(k))),
                if (k == current) const Icon(Icons.check, size: 18),
              ]),
            ),
          if (chosen)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (null,)),
              child: const Text('Guess from its name'),
            ),
        ],
      ),
    );
    if (picked != null) monitor.setKind(mac, picked.$1);
  }

  Future<void> _setLimit(BuildContext context, int? current) async {
    final controller = TextEditingController(text: current == null ? '' : '${current ~/ 1000000}');
    final result = await showDialog<(int?,)>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily data limit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'MB', helperText: 'Warns when this device uses more in a day. 1000 MB = 1 GB.'),
        ),
        actions: [
          if (current != null) TextButton(onPressed: () => Navigator.pop(context, (null,)), child: const Text('Turn off')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final mb = int.tryParse(controller.text.trim());
              Navigator.pop(context, (mb == null || mb <= 0 ? null : mb * 1000000,));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) monitor.setDailyLimit(mac, result.$1);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final d = monitor.usage.devices[mac];
        if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Device not found')));
        final t = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final now = DateTime.now();
        final live = monitor.live[mac];
        final today = monitor.usage.usage(mac, now);
        final month = monitor.usage.byDevice(now, 30)[mac];
        final week = monitor.usage.daily(now, 7, mac: mac);
        final online = monitor.usage.onlinePerDay(mac, now, 7);
        final recent = d.sessions.reversed.take(8).toList();

        return Scaffold(
          appBar: AppBar(
            title: Text(d.displayName),
            actions: [
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _rename(context, d.alias ?? d.hostname),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Icon(live != null ? Icons.circle : Icons.circle_outlined,
                      size: 12, color: live != null ? scheme.primary : scheme.outline),
                  const SizedBox(width: 8),
                  Text(live != null ? 'Online' : 'Offline · seen ${formatAgo(d.lastSeen, now)}', style: t.titleSmall),
                ],
              ),
              if (live?.downBps != null) ...[
                const SizedBox(height: 4),
                Text('Now: ↓ ${formatSpeed(live!.downBps!)} · ↑ ${formatSpeed(live.upBps ?? 0)}', style: t.bodyMedium),
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(kindIcon(d.kind)),
                title: Text(kindLabel(d.kind)),
                subtitle: Text(d.chosenKind == null ? 'Guessed from its name. Tap to change.' : 'Tap to change.'),
                onTap: () => _pickKind(context, d.kind, d.chosenKind != null),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.verified_user_outlined),
                title: const Text('I know this device'),
                subtitle: Text(d.known ? 'Shown as one of yours.' : 'Marked Unknown in the list.'),
                value: d.known,
                onChanged: (v) => monitor.setKnown(mac, v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.data_usage),
                title: Text(d.dailyLimit == null ? 'No daily limit' : 'Daily limit ${formatBytes(d.dailyLimit!)}'),
                subtitle: Text(d.dailyLimit != null && today.total > d.dailyLimit!
                    ? 'Over the limit today.'
                    : 'Warns when it uses more in a day.'),
                onTap: () => _setLimit(context, d.dailyLimit),
              ),
              const SizedBox(height: 12),
              Text('Today', style: t.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              Text(formatBytes(today.total), style: t.headlineMedium),
              Text('↓ ${formatBytes(today.down)} · ↑ ${formatBytes(today.up)}', style: t.bodyMedium),
              const SizedBox(height: 20),
              Text('Last 7 days', style: t.titleMedium),
              const SizedBox(height: 8),
              DailyBarChart(days: [for (final w in week) (w.$1, w.$2.total)], height: 120),
              const SizedBox(height: 8),
              Text('Last 30 days: ${formatBytes(month?.total ?? 0)}', style: t.bodyMedium),
              const SizedBox(height: 24),
              Text('Time online, last 7 days', style: t.titleMedium),
              const SizedBox(height: 8),
              DailyBarChart(
                days: [for (final o in online) (o.$1, o.$2.inMinutes)],
                height: 100,
                format: (m) => formatDuration(Duration(minutes: m)),
              ),
              const SizedBox(height: 16),
              Text('Recent visits', style: t.titleMedium),
              if (recent.isEmpty) const Text('None yet'),
              for (final s in recent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '${formatDate(s.start)}  ${formatTime(s.start)} – ${formatTime(s.end)}'
                    '${s.end.day != s.start.day ? ' (${formatDate(s.end)})' : ''}  ·  ${formatDuration(s.length)}',
                    style: t.bodyMedium,
                  ),
                ),
              Text('Only while the app was checking: time it was closed is not counted.',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Text('Details', style: t.titleMedium),
              _Row('Name on the network', d.hostname.isEmpty ? '(none)' : d.hostname),
              if (d.vendor.isNotEmpty) _Row('Maker', d.vendor),
              _Row('IP address', d.ip),
              _Row('MAC address', isPrivateMac(d.mac) ? '${d.mac}\n(private address: the device made it up for this network)' : d.mac),
              _Row('Connection', linkLabel(d.link)),
              if (monitor.multipleRouters && d.via.isNotEmpty) _Row('Router', d.via),
              _Row('First seen', formatDateTime(d.firstSeen)),
              _Row('Last seen', formatDateTime(d.lastSeen)),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: SelectableText(value, style: t.bodyMedium)),
        ],
      ),
    );
  }
}
