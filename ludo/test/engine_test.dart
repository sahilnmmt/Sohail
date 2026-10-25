import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_game/src/ai.dart';
import 'package:ludo_game/src/engine.dart';
import 'package:ludo_game/src/geometry.dart';

LudoGame twoPlayers() =>
    LudoGame(const [Player(LudoColor.red), Player(LudoColor.yellow)]);

void main() {
  group('rules', () {
    test('needs 2 to 4 distinct players', () {
      expect(
        () => LudoGame(const [Player(LudoColor.red)]),
        throwsArgumentError,
      );
      expect(
        () => LudoGame(const [Player(LudoColor.red), Player(LudoColor.red)]),
        throwsArgumentError,
      );
    });

    test('a six brings a token out and gives another roll', () {
      final g = twoPlayers();
      expect(g.roll(6), RollResult.mustMove);
      expect(g.movableTokens(), [0, 1, 2, 3]);
      final r = g.move(2);
      expect(r.to, 0);
      expect(r.extraTurn, isTrue);
      expect(g.current.color, LudoColor.red);
    });

    test('no token out and no six passes the turn', () {
      final g = twoPlayers();
      expect(g.roll(4), RollResult.noMoves);
      expect(g.current.color, LudoColor.yellow);
      expect(g.lastRoller, LudoColor.red);
    });

    test('three sixes in a row lose the turn', () {
      final g = twoPlayers();
      g.roll(6);
      g.move(0);
      g.roll(6);
      g.move(0);
      expect(g.roll(6), RollResult.threeSixes);
      expect(g.current.color, LudoColor.yellow);
      expect(g.tokens[LudoColor.red]![0], 6);
    });

    test('landing on an opponent captures it and gives another roll', () {
      final g = twoPlayers();
      // Yellow starts on square 26; red reaches it at progress 26.
      g.tokens[LudoColor.yellow]![0] = 3; // square 29, not safe
      g.tokens[LudoColor.red]![1] = 25; // square 25
      g.roll(4);
      final r = g.move(1);
      expect(r.captures.single.color, LudoColor.yellow);
      expect(g.tokens[LudoColor.yellow]![0], inYard);
      expect(r.extraTurn, isTrue);
      expect(g.current.color, LudoColor.red);
    });

    test('safe squares protect tokens', () {
      final g = twoPlayers();
      g.tokens[LudoColor.yellow]![0] = 8; // square 34, a star
      g.tokens[LudoColor.red]![0] = 31;
      g.roll(3);
      expect(g.move(0).captures, isEmpty);
      expect(g.tokens[LudoColor.yellow]![0], 8);
      expect(g.current.color, LudoColor.yellow);
    });

    test('home needs an exact roll', () {
      final g = twoPlayers();
      g.tokens[LudoColor.red]!.setAll(0, [53, home, home, home]);
      expect(g.roll(4), RollResult.noMoves);
      g.roll(1); // yellow
      expect(g.roll(3), RollResult.mustMove);
      final r = g.move(0);
      expect(r.reachedHome, isTrue);
      expect(g.ranking, [LudoColor.red, LudoColor.yellow]);
      expect(g.isOver, isTrue);
    });

    test('finished players are skipped and the rest play on', () {
      final g = LudoGame(const [
        Player(LudoColor.red),
        Player(LudoColor.green),
        Player(LudoColor.blue),
      ]);
      g.tokens[LudoColor.red]!.setAll(0, [55, home, home, home]);
      g.roll(1);
      final r = g.move(0);
      expect(r.extraTurn, isFalse);
      expect(g.ranking, [LudoColor.red]);
      expect(g.isOver, isFalse);
      expect(g.current.color, LudoColor.green);
      g.roll(1); // green, no moves
      g.roll(1); // blue, no moves
      expect(g.current.color, LudoColor.green);
    });

    test('a player stuck in the yard gets a six after 3 misses', () {
      final g = LudoGame(const [
        Player(LudoColor.red),
        Player(LudoColor.green),
      ], random: _NeverSix());
      for (var turn = 0; turn < yardMissLimit; turn++) {
        expect(g.roll(g.rollDie()), RollResult.noMoves); // red
        expect(g.roll(g.rollDie()), RollResult.noMoves); // green
      }
      expect(g.yardMisses[LudoColor.red], yardMissLimit);
      expect(g.rollDie(), 6);
      expect(g.roll(6), RollResult.mustMove);
      expect(g.yardMisses[LudoColor.red], 0);
      g.move(0);
      // With a token on the board, rolls are random again.
      expect(g.rollDie(), isNot(6));
    });

    test('misses only count while stuck in the yard', () {
      final g = twoPlayers();
      g.tokens[LudoColor.red]![0] = 10;
      for (var i = 0; i < 5; i++) {
        g.roll(2); // red moves
        g.move(0);
        g.roll(1); // yellow
      }
      expect(g.yardMisses[LudoColor.red], 0);
      expect(g.yardMisses[LudoColor.yellow], 5);
    });

    test('only safe squares are the starts and stars', () {
      expect(
        [
          for (var s = 0; s < trackLength; s++)
            if (LudoGame.isSafe(s)) s,
        ],
        [0, 8, 13, 21, 26, 34, 39, 47],
      );
    });
  });

  group('board geometry', () {
    test('the track is 52 neighbouring, distinct cells', () {
      final t = BoardGeometry.track;
      expect(t.length, trackLength);
      expect(t.toSet().length, trackLength);
      for (var i = 0; i < trackLength; i++) {
        final d = t[i] - t[(i + 1) % trackLength];
        expect(d.dx.abs() + d.dy.abs(), anyOf(1, 2), reason: 'step $i');
      }
    });

    test('each seat is red rotated, so routes share the track', () {
      for (final c in LudoColor.values) {
        for (var p = 0; p <= lastTrackStep; p++) {
          expect(
            BoardGeometry.position(c, p, 0),
            BoardGeometry.track[LudoGame.trackSquare(c, p)!],
          );
        }
      }
    });

    test('start squares sit next to their own yard', () {
      expect(
        BoardGeometry.position(LudoColor.red, 0, 0),
        const Offset(1.5, 6.5),
      );
      expect(
        BoardGeometry.position(LudoColor.green, 0, 0),
        const Offset(8.5, 1.5),
      );
      expect(
        BoardGeometry.position(LudoColor.yellow, 0, 0),
        const Offset(13.5, 8.5),
      );
      expect(
        BoardGeometry.position(LudoColor.blue, 0, 0),
        const Offset(6.5, 13.5),
      );
    });

    test('home columns lead from the track entry to the centre', () {
      for (final c in LudoColor.values) {
        final cells = [
          for (var p = lastTrackStep; p < home; p++)
            BoardGeometry.position(c, p, 0),
        ];
        for (var i = 1; i < cells.length; i++) {
          final d = cells[i] - cells[i - 1];
          expect(d.distance, 1, reason: '$c step $i');
        }
        expect((cells.last - BoardGeometry.centre).distance, 2);
      }
    });
  });

  group('whole games', () {
    for (final n in [2, 3, 4]) {
      test('$n computer players always finish', () {
        for (var seed = 0; seed < 30; seed++) {
          final players = [
            for (final c in LudoColor.values.take(n))
              Player(c, isComputer: true),
          ];
          final g = LudoGame(players, random: Random(seed));
          var turns = 0;
          while (!g.isOver) {
            if (g.roll() == RollResult.mustMove) g.move(chooseMove(g));
            expect(++turns, lessThan(5000));
          }
          expect(g.ranking.toSet().length, n);
        }
      });
    }

    test('the computer beats random moves most of the time', () {
      var wins = 0;
      for (var seed = 0; seed < 100; seed++) {
        final rnd = Random(seed);
        final g = LudoGame(const [
          Player(LudoColor.red, isComputer: true),
          Player(LudoColor.yellow),
        ], random: rnd);
        while (!g.isOver) {
          if (g.roll() != RollResult.mustMove) continue;
          final m = g.movableTokens();
          g.move(
            g.current.isComputer ? chooseMove(g) : m[rnd.nextInt(m.length)],
          );
        }
        if (g.ranking.first == LudoColor.red) wins++;
      }
      expect(wins, greaterThan(60));
    });
  });
}

class _NeverSix implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
