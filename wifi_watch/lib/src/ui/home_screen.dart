import 'package:flutter/material.dart';

import '../format.dart';
import '../monitor.dart';
import '../device_kind.dart';
import '../router/router_source.dart';
import '../settings.dart';
import '../usage.dart';
import 'bar_chart.dart';
import 'device_icons.dart';
import 'device_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Monitor monitor;
  final AppSettings settings;
  final Future<void> Function(AppSettings) onSettingsChanged;

  const HomeScreen({super.key, required this.monitor, required this.settings, required this.onSettingsChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        settings: widget.settings,
        onSave: widget.onSettingsChanged,
        onForgetHistory: widget.monitor.forgetHistory,
      ),
    ));
  }

  void _openDevice(String mac) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeviceScreen(monitor: widget.monitor, mac: mac),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.monitor;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('WiFi Watch'),
          actions: [
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: m.retry),
            IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
          ],
        ),
        body: Column(
          children: [
            _StatusBanner(monitor: m, onOpenSettings: _openSettings),
            if (m.usage.unseenNew.isNotEmpty) _NewDevicesBanner(monitor: m, onOpen: _openDevice),
            _LimitBanner(monitor: m, onOpen: _openDevice),
            Expanded(
              child: _tab == 0
                  ? _DevicesTab(monitor: m, onOpen: _openDevice)
                  : _UsageTab(monitor: m, onOpen: _openDevice),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'Devices'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Usage'),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Monitor monitor;
  final VoidCallback onOpenSettings;
  const _StatusBanner({required this.monitor, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = monitor;
    final (IconData icon, String text, Color bg, Color fg) = switch (m.state) {
      MonitorState.ok => (
          Icons.router_outlined,
          '${m.sourceName} · updated ${m.updatedAt == null ? '' : formatAgo(m.updatedAt!, DateTime.now())}',
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      MonitorState.error => (Icons.error_outline, m.error ?? 'Error', scheme.errorContainer, scheme.onErrorContainer),
      _ => (Icons.sync, 'Connecting to ${m.sourceName}…', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Material(
      color: bg,
      child: InkWell(
        onTap: m.state == MonitorState.error ? onOpenSettings : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13)),
              ),
              if (m.state == MonitorState.error) Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitBanner extends StatelessWidget {
  final Monitor monitor;
  final void Function(String mac) onOpen;
  const _LimitBanner({required this.monitor, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = monitor.usage.overLimit(DateTime.now(), monitor.networkLimitBytes);
    if (over.devices.isEmpty && !over.network) return const SizedBox.shrink();
    final parts = [
      if (over.network) 'Your network went over its daily limit.',
      if (over.devices.isNotEmpty) 'Over their daily limit: ${over.devices.map((d) => d.displayName).join(', ')}.',
    ];
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: over.devices.length == 1 ? () => onOpen(over.devices.single.mac) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.data_usage, size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(parts.join(' '), style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewDevicesBanner extends StatelessWidget {
  final Monitor monitor;
  final void Function(String mac) onOpen;
  const _NewDevicesBanner({required this.monitor, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = [
      for (final mac in monitor.usage.unseenNew)
        if (monitor.usage.devices[mac] != null) monitor.usage.devices[mac]!,
    ];
    if (devices.isEmpty) return const SizedBox.shrink();
    final names = devices.map((d) => d.displayName).join(', ');
    return MaterialBanner(
      backgroundColor: scheme.tertiaryContainer,
      leading: Icon(Icons.fiber_new_outlined, color: scheme.onTertiaryContainer),
      content: Text(
        devices.length == 1 ? 'New device joined your Wi-Fi: $names' : '${devices.length} new devices joined: $names',
        style: TextStyle(color: scheme.onTertiaryContainer),
      ),
      actions: [
        if (devices.length == 1)
          TextButton(
            onPressed: () {
              onOpen(devices.single.mac);
              monitor.markNewSeen();
            },
            child: const Text('VIEW'),
          ),
        TextButton(onPressed: monitor.markNewKnown, child: Text(devices.length == 1 ? "IT'S OURS" : 'ALL OURS')),
        TextButton(onPressed: monitor.markNewSeen, child: const Text('LATER')),
      ],
    );
  }
}

enum _Filter { all, online, unknown }

class _DevicesTab extends StatefulWidget {
  final Monitor monitor;
  final void Function(String mac) onOpen;
  const _DevicesTab({required this.monitor, required this.onOpen});

  @override
  State<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<_DevicesTab> {
  _Filter _filter = _Filter.all;
  String _query = '';

  bool _matches(KnownDevice d) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [d.displayName, d.hostname, d.vendor, d.ip, d.mac, kindLabel(d.kind)].any((t) => t.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.monitor;
    final now = DateTime.now();
    final today = m.usage.byDevice(now, 1);
    final over = {for (final d in m.usage.overLimit(now, m.networkLimitBytes).devices) d.mac};
    final unknownCount = m.usage.devices.values.where((d) => !d.known).length;
    final devices = m.usage.devices.values
        .where((d) => switch (_filter) {
              _Filter.all => true,
              _Filter.online => m.live.containsKey(d.mac),
              _Filter.unknown => !d.known,
            })
        .where(_matches)
        .toList()
      ..sort((a, b) {
        final online = (m.live.containsKey(b.mac) ? 1 : 0) - (m.live.containsKey(a.mac) ? 1 : 0);
        if (online != 0) return online;
        if (m.live.containsKey(a.mac)) {
          return (today[b.mac]?.total ?? 0).compareTo(today[a.mac]?.total ?? 0);
        }
        return b.lastSeen.compareTo(a.lastSeen);
      });

    if (m.usage.devices.isEmpty) {
      return Center(
        child: m.state == MonitorState.connecting
            ? const CircularProgressIndicator()
            : const Text('No devices yet'),
      );
    }

    final down = m.live.values.fold<double>(0, (s, c) => s + (c.downBps ?? 0));
    final up = m.live.values.fold<double>(0, (s, c) => s + (c.upBps ?? 0));
    final hasSpeed = m.live.values.any((c) => c.downBps != null);
    final todayTotal = today.values.fold(Bytes.zero, (a, b) => a + b);

    return RefreshIndicator(
      onRefresh: m.poll,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(child: _Stat(label: 'Online now', value: '${m.live.length}')),
                Expanded(child: _Stat(label: 'Used today', value: formatBytes(todayTotal.total))),
                if (hasSpeed)
                  Expanded(child: _Stat(label: 'Live ↓ / ↑', value: '${formatSpeed(down)}\n${formatSpeed(up)}')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name, maker, IP or MAC',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(switch (f) {
                      _Filter.all => 'All ${m.usage.devices.length}',
                      _Filter.online => 'Online ${m.live.length}',
                      _Filter.unknown => 'Unknown $unknownCount',
                    }),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
              ],
            ),
          ),
          if (devices.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No devices match'))),
          for (final d in devices)
            _DeviceTile(
              device: d,
              live: m.live[d.mac],
              today: today[d.mac],
              overLimit: over.contains(d.mac),
              onTap: () => widget.onOpen(d.mac),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value, style: t.titleMedium),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final KnownDevice device;
  final ClientInfo? live;
  final Bytes? today;
  final bool overLimit;
  final VoidCallback onTap;
  const _DeviceTile(
      {required this.device, required this.live, required this.today, required this.overLimit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final online = live != null;
    final details = <String>[
      if (online) device.ip,
      if (online) linkLabel(device.link) else 'Seen ${formatAgo(device.lastSeen, DateTime.now())}',
      if ((today?.total ?? 0) > 0) 'today ${formatBytes(today!.total)}',
    ];
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: online ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        foregroundColor: online ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        child: Icon(kindIcon(device.kind)),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(device.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: online ? null : TextStyle(color: scheme.onSurfaceVariant)),
          ),
          if (!device.known) ...[
            const SizedBox(width: 6),
            _Tag(text: 'Unknown', bg: scheme.tertiaryContainer, fg: scheme.onTertiaryContainer),
          ],
          if (overLimit) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error, semanticLabel: 'Over its daily limit'),
          ],
        ],
      ),
      subtitle: Text(details.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: online && live!.downBps != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('↓ ${formatSpeed(live!.downBps!)}', style: t.bodySmall),
                Text('↑ ${formatSpeed(live!.upBps ?? 0)}', style: t.bodySmall),
              ],
            )
          : null,
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Tag({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
      );
}

class _UsageTab extends StatefulWidget {
  final Monitor monitor;
  final void Function(String mac) onOpen;
  const _UsageTab({required this.monitor, required this.onOpen});

  @override
  State<_UsageTab> createState() => _UsageTabState();
}

class _UsageTabState extends State<_UsageTab> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final m = widget.monitor;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final perDevice = m.usage.byDevice(now, _days).entries.where((e) => e.value.total > 0).toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final total = perDevice.fold(Bytes.zero, (s, e) => s + e.value);
    final daily = m.usage.daily(now, _days);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('Today')),
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 30, label: Text('30 days')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.single),
          ),
        ),
        const SizedBox(height: 20),
        Text(formatBytes(total.total), style: t.displaySmall),
        Text('↓ ${formatBytes(total.down)} downloaded · ↑ ${formatBytes(total.up)} uploaded',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        if (_days > 1) ...[
          const SizedBox(height: 20),
          DailyBarChart(days: [for (final d in daily) (d.$1, d.$2.total)]),
        ],
        const SizedBox(height: 24),
        Text('Top devices', style: t.titleMedium),
        const SizedBox(height: 8),
        if (perDevice.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No usage recorded yet. Usage is counted while the app is open, '
              'or from the router\'s own counters if it keeps them.',
              style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        for (final e in perDevice)
          _ShareRow(
            name: m.usage.devices[e.key]?.displayName ?? e.key,
            bytes: e.value.total,
            share: total.total == 0 ? 0 : e.value.total / total.total,
            onTap: () => widget.onOpen(e.key),
          ),
        const SizedBox(height: 16),
        Text(
          m.live.values.any((c) => c.totalDown != null)
              ? 'Counted by your router.'
              : 'Estimated from live speeds while the app is open.',
          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ShareRow extends StatelessWidget {
  final String name;
  final int bytes;
  final double share;
  final VoidCallback onTap;
  const _ShareRow({required this.name, required this.bytes, required this.share, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${formatBytes(bytes)} · ${(share * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                color: scheme.primary,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
