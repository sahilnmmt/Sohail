import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import '../router/router_source.dart';
import 'bar_chart.dart';

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
              const SizedBox(height: 20),
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
              Text('Details', style: t.titleMedium),
              _Row('Name on the network', d.hostname.isEmpty ? '(none)' : d.hostname),
              _Row('IP address', d.ip),
              _Row('MAC address', d.mac),
              _Row('Connection', linkLabel(d.link)),
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
