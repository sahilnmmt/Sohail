import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/main.dart';
import 'package:ludo_game/src/engine.dart';
import 'package:ludo_game/src/game_screen.dart';

void main() {
  testWidgets('setup needs at least two players', (tester) async {
    await tester.pumpWidget(const LudoApp());
    expect(find.text('Start game (4 players)'), findsOneWidget);

    for (final c in ['red', 'green', 'yellow']) {
      await tester.tap(
        find.descendant(
          of: find.byKey(Key('seat-$c')),
          matching: find.byIcon(Icons.block),
        ),
      );
      await tester.pump();
    }
    expect(find.text('Pick at least 2 players'), findsOneWidget);
    final start = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Pick at least 2 players'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    expect(start.onPressed, isNull);
  });

  for (final size in [const Size(400, 800), const Size(900, 420)]) {
    testWidgets('a game can be played at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: GameScreen(
            players: const [
              Player(LudoColor.red),
              Player(LudoColor.green, isComputer: true),
              Player(LudoColor.yellow, isComputer: true),
              Player(LudoColor.blue, isComputer: true),
            ],
            random: Random(1),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Tap dice to roll'), findsOneWidget);

      // Play many human rolls; the computers play in between.
      for (var i = 0; i < 40; i++) {
        final dice = find.byKey(const Key('dice-red'));
        await tester.tap(dice, warnIfMissed: false);
        await tester.pump(const Duration(seconds: 2));
        if (find.text('Tap a glowing token').evaluate().isNotEmpty) {
          final token = find.byKey(const ValueKey('token-red-0'));
          await tester.tap(token, warnIfMissed: false);
          for (var t = 1; t < 4; t++) {
            if (find.text('Tap a glowing token').evaluate().isEmpty) break;
            await tester.tap(
              find.byKey(ValueKey('token-red-$t')),
              warnIfMissed: false,
            );
          }
        }
        for (var k = 0; k < 30; k++) {
          await tester.pump(const Duration(seconds: 1));
          if (find.text('Tap dice to roll').evaluate().isNotEmpty) break;
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
