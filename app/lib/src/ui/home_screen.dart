import 'package:flutter/material.dart';

import '../messaging/message.dart';
import '../messaging/messaging_service.dart';
import '../settings.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends StatelessWidget {
  final AppSettings settings;
  final MessagingService messaging;
  final Future<void> Function(AppSettings) onSettingsChanged;

  const HomeScreen({super.key, required this.settings, required this.messaging, required this.onSettingsChanged});

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(settings: settings, onSave: onSettingsChanged),
    ));
  }

  void _openSetup(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: messaging,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('Family: ${settings.group}'),
          actions: [
            IconButton(
              tooltip: 'Set up a robot',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _openSetup(context),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _openSettings(context),
            ),
          ],
        ),
        body: Column(
          children: [
            _ConnectionBanner(
              messaging: messaging,
              settings: settings,
              onOpenSettings: () => _openSettings(context),
              onRetry: () => messaging.connect(settings),
            ),
            if (messaging.robots.isNotEmpty) _RobotStrip(robots: messaging.robots),
            Expanded(child: _Feed(items: messaging.feed, onSetup: () => _openSetup(context))),
            _Composer(messaging: messaging),
          ],
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final MessagingService messaging;
  final AppSettings settings;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  const _ConnectionBanner(
      {required this.messaging, required this.settings, required this.onOpenSettings, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!settings.isComplete) {
      return MaterialBanner(
        content: const Text('Add your message server to start talking to your robots.'),
        leading: const Icon(Icons.dns_outlined),
        actions: [TextButton(onPressed: onOpenSettings, child: const Text('Open settings'))],
      );
    }
    switch (messaging.state) {
      case LinkState.connected:
        return const SizedBox.shrink();
      case LinkState.connecting:
        return const LinearProgressIndicator();
      case LinkState.failed:
      case LinkState.disconnected:
        return MaterialBanner(
          backgroundColor: scheme.errorContainer,
          content: Text(messaging.error ?? 'Not connected to the message server.',
              style: TextStyle(color: scheme.onErrorContainer)),
          leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
          actions: [
            TextButton(onPressed: onOpenSettings, child: const Text('Settings')),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        );
    }
  }
}

class _RobotStrip extends StatelessWidget {
  final Map<String, bool> robots;
  const _RobotStrip({required this.robots});

  @override
  Widget build(BuildContext context) {
    final entries = robots.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Chip(
                avatar: Icon(Icons.circle, size: 12, color: e.value ? Colors.green : Colors.grey),
                label: Text(e.key),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _Feed extends StatelessWidget {
  final List<FeedItem> items;
  final VoidCallback onSetup;
  const _Feed({required this.items, required this.onSetup});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              const Text('No messages yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Send a nudge below, or press the button on a robot.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onSetup,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Set up a robot'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, i) => _Bubble(item: items[items.length - 1 - i]),
    );
  }
}

String describe(SohailMessage m) => switch (m.type) {
      MessageType.nudge => '💗 is thinking of you',
      MessageType.emoji => '${emojiGlyphs[m.emoji]} ${m.emoji!.name}',
      MessageType.text => m.text!,
    };

class _Bubble extends StatelessWidget {
  final FeedItem item;
  const _Bubble({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = item.mine;
    final t = item.time;
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mine ? 'You' : item.message.sender,
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.primary, fontSize: 13)),
            const SizedBox(height: 2),
            Text(describe(item.message), style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(time, style: TextStyle(fontSize: 11, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  final MessagingService messaging;
  const _Composer({required this.messaging});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _text = TextEditingController();

  void _send(MessageType type, {Emoji? emoji, String? text}) {
    final err = widget.messaging.send(type, emoji: emoji, text: text);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else if (type == MessageType.text) {
      _text.clear();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.messaging.isConnected;
    final bytes = utf8Length(_text.text);
    return SafeArea(
      top: false,
      child: Material(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilledButton.icon(
                        onPressed: enabled ? () => _send(MessageType.nudge) : null,
                        icon: const Icon(Icons.favorite),
                        label: const Text('Nudge'),
                      ),
                    ),
                    for (final e in Emoji.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          tooltip: 'Send ${e.name}',
                          label: Text(emojiGlyphs[e]!, style: const TextStyle(fontSize: 20)),
                          onPressed: enabled ? () => _send(MessageType.emoji, emoji: e) : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: enabled,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (v) {
                        if (isValidText(v.trim())) _send(MessageType.text, text: v.trim());
                      },
                      decoration: InputDecoration(
                        hintText: 'Message for the robots',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        counterText: '$bytes/$textMax',
                        errorText: bytes > textMax ? 'Too long for the robot screen' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: enabled && isValidText(_text.text.trim())
                        ? () => _send(MessageType.text, text: _text.text.trim())
                        : null,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int utf8Length(String s) {
  var n = 0;
  for (final r in s.runes) {
    n += r < 0x80 ? 1 : r < 0x800 ? 2 : r < 0x10000 ? 3 : 4;
  }
  return n;
}
