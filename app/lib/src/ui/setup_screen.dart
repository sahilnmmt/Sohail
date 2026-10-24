import 'package:flutter/material.dart';

import '../provisioning/ble_setup.dart' as ble;
import '../provisioning/setup_controller.dart';

class SetupScreen extends StatefulWidget {
  /// Tests inject a controller with fake Bluetooth; the app uses the real one.
  final SetupController? controller;
  const SetupScreen({super.key, this.controller});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final SetupController c = widget.controller ??
      SetupController(scanner: ble.scanForRobots, connector: ble.connectToRobot, ensurePermissions: ble.ensureBluetoothReady);
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    _code.dispose();
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Set up a robot')),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(key: ValueKey(c.step), child: _body(context)),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (c.step) {
      case SetupStep.permissions:
        return _Message(
          icon: Icons.bluetooth,
          title: c.error == null ? 'Checking Bluetooth...' : 'Bluetooth needed',
          body: c.error ?? '',
          busy: c.error == null,
          action: c.error == null ? null : FilledButton(onPressed: c.start, child: const Text('Try again')),
        );
      case SetupStep.scanning:
        return _scanning(context);
      case SetupStep.code:
        return _codeEntry(context);
      case SetupStep.connecting:
        return const _Message(
            icon: Icons.lock_outline, title: 'Connecting securely...', body: 'Checking the code with the robot.', busy: true);
      case SetupStep.chooseNetwork:
        return _networks(context);
      case SetupStep.joining:
        return const _Message(
            icon: Icons.wifi, title: 'Joining Wi-Fi...', body: 'The robot is connecting. This takes a few seconds.', busy: true);
      case SetupStep.done:
        return _Message(
          icon: Icons.check_circle,
          title: '${c.robot?.label ?? 'Robot'} is online',
          body: 'It joined ${c.joinedNetwork}${c.robotIp?.isNotEmpty == true ? ' (${c.robotIp})' : ''}. '
              'Its status dot turns green once it reaches the message server.',
          action: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        );
    }
  }

  Widget _scanning(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Steps(current: 0),
        const SizedBox(height: 16),
        Text('Put the robot in setup mode', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('A new robot starts in setup mode. Otherwise hold its button for 10 seconds until it shows '
            '"Setup mode" and a 6-digit code.'),
        const SizedBox(height: 16),
        if (c.error != null) Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (c.robots.isEmpty)
          const ListTile(leading: CircularProgressIndicator(), title: Text('Looking for robots nearby...')),
        for (final r in c.robots)
          Card(
            child: ListTile(
              leading: const Icon(Icons.smart_toy_outlined),
              title: Text(r.label),
              subtitle: Text('${r.name} · signal ${r.rssi} dBm'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => c.choose(r),
            ),
          ),
      ],
    );
  }

  Widget _codeEntry(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Steps(current: 1),
        const SizedBox(height: 16),
        Text('Enter the code on ${c.robot?.label ?? 'the robot'}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('The robot shows a 6-digit code under its eyes. It proves you are next to it.'),
        const SizedBox(height: 16),
        TextField(
          key: const Key('code'),
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, letterSpacing: 12, fontFeatures: [FontFeature.tabularFigures()]),
          decoration: InputDecoration(border: const OutlineInputBorder(), errorText: c.error, counterText: ''),
          onSubmitted: c.submitCode,
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => c.submitCode(_code.text.trim()), child: const Text('Connect')),
        TextButton(onPressed: c.start, child: const Text('Pick a different robot')),
      ],
    );
  }

  Widget _networks(BuildContext context) {
    return RefreshIndicator(
      onRefresh: c.refreshNetworks,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Steps(current: 2),
          const SizedBox(height: 16),
          Text('Choose your Wi-Fi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Networks the robot can see. It needs 2.4 GHz Wi-Fi.'),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(c.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 8),
          for (final n in c.networks)
            ListTile(
              leading: Icon(_signalIcon(n.bars)),
              title: Text(n.ssid),
              subtitle: Text(n.needsPassword ? 'Secured' : 'Open network'),
              trailing: n.needsPassword ? const Icon(Icons.lock_outline, size: 18) : null,
              onTap: () => _askPassword(context, n.ssid, n.needsPassword),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Other network...'),
            onTap: () => _askPassword(context, null, true),
          ),
        ],
      ),
    );
  }

  IconData _signalIcon(int bars) => switch (bars) {
        4 => Icons.network_wifi,
        3 => Icons.network_wifi_3_bar,
        2 => Icons.network_wifi_2_bar,
        1 => Icons.network_wifi_1_bar,
        _ => Icons.signal_wifi_0_bar,
      };

  Future<void> _askPassword(BuildContext context, String? ssid, bool needsPassword) async {
    final name = TextEditingController(text: ssid ?? '');
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ssid ?? 'Other network'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ssid == null)
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Network name')),
            if (needsPassword)
              TextField(
                key: const Key('wifi-password'),
                controller: pass,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Wi-Fi password'),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await c.join(name.text.trim(), pass.text);
    }
  }
}

class _Steps extends StatelessWidget {
  final int current;
  const _Steps({required this.current});

  @override
  Widget build(BuildContext context) {
    const labels = ['Find', 'Code', 'Wi-Fi'];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          CircleAvatar(
            radius: 12,
            backgroundColor: i <= current ? scheme.primary : scheme.surfaceContainerHighest,
            child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: i <= current ? scheme.onPrimary : scheme.onSurface)),
          ),
          const SizedBox(width: 6),
          Text(labels[i]),
          if (i < labels.length - 1) const Expanded(child: Divider(indent: 8, endIndent: 8)),
        ],
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool busy;
  final Widget? action;
  const _Message({required this.icon, required this.title, required this.body, this.busy = false, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            if (busy) const Padding(padding: EdgeInsets.only(top: 24), child: CircularProgressIndicator()),
            if (action != null) Padding(padding: const EdgeInsets.only(top: 24), child: action),
          ],
        ),
      ),
    );
  }
}
