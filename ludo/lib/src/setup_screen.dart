import 'package:flutter/material.dart';

import 'board_painter.dart';
import 'engine.dart';
import 'game_screen.dart';
import 'rules.dart';

enum Seat { human, computer, off }

/// Picks who plays each colour: a person, the computer, or nobody.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final Map<LudoColor, Seat> _seats = {
    for (final c in LudoColor.values) c: Seat.human,
  };

  List<Player> get _chosen => [
    for (final c in LudoColor.values)
      if (_seats[c] != Seat.off)
        Player(c, isComputer: _seats[c] == Seat.computer),
  ];

  List<Player> get _players => seatPlayers(_chosen);

  void _start() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(players: _players)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _players.length;
    final moved = _chosen
        .where((p) => !_players.any((q) => q.color == p.color))
        .firstOrNull;
    final movedTo = _players
        .where((p) => !_chosen.any((q) => q.color == p.color))
        .firstOrNull;
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1F2A44), Color(0xFF0B0F1A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _Title(),
                    const SizedBox(height: 8),
                    const Text(
                      'Offline · 2 to 4 players on one device',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    for (final c in LudoColor.values) _seatRow(c),
                    if (moved != null && movedTo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '2 players sit in opposite corners: '
                          '${moved.color.label} plays as ${movedTo.color.label}.',
                          key: const Key('seat-note'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        key: const Key('start'),
                        onPressed: count >= 2 ? _start : null,
                        icon: const Icon(Icons.play_arrow, size: 28),
                        label: Text(
                          count >= 2
                              ? 'Start game ($count players)'
                              : 'Pick at least 2 players',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => showRules(context),
                      icon: const Icon(Icons.help_outline),
                      label: const Text('How to play'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seatRow(LudoColor c) {
    final seat = seatColors[c]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: seat, width: 6)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 12, backgroundColor: seat),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              c.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SegmentedButton<Seat>(
            key: Key('seat-${c.name}'),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              foregroundColor: Colors.white70,
              selectedForegroundColor: Colors.black,
              selectedBackgroundColor: seat,
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: Seat.human,
                icon: Icon(Icons.person),
                tooltip: 'Player',
              ),
              ButtonSegment(
                value: Seat.computer,
                icon: Icon(Icons.smart_toy),
                tooltip: 'Computer',
              ),
              ButtonSegment(
                value: Seat.off,
                icon: Icon(Icons.block),
                tooltip: 'Off',
              ),
            ],
            selected: {_seats[c]!},
            onSelectionChanged: (s) => setState(() => _seats[c] = s.first),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, letter) in 'LUDO'.split('').indexed)
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: seatColors[LudoColor.values[i]],
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8),
              ],
            ),
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }
}
