import 'engine.dart';

/// Picks a move for a computer player: capture if it can, then bring tokens
/// home, out of the yard and onto safe squares, while staying out of reach
/// of opponents.
int chooseMove(LudoGame game) {
  final movable = game.movableTokens();
  if (movable.isEmpty) throw StateError('Nothing to move');
  final c = game.current.color;
  var best = movable.first;
  var bestScore = double.negativeInfinity;
  for (final t in movable) {
    final from = game.tokens[c]![t];
    final to = LudoGame.targetFor(from, game.dice!)!;
    var score = to / 10;
    final captures = game.capturesAt(c, to);
    if (captures.isNotEmpty) {
      score += 60;
      for (final cap in captures) {
        score += game.tokens[cap.color]![cap.token] / 2;
      }
    }
    if (to == home) score += 45;
    if (from == inYard) score += 35;
    if (from <= lastTrackStep && to > lastTrackStep) score += 25;
    final toSquare = LudoGame.trackSquare(c, to);
    if (toSquare != null) {
      if (LudoGame.isSafe(toSquare)) {
        score += 15;
      } else if (captures.isEmpty && _threatened(game, c, toSquare)) {
        score -= 30 + to / 3;
      }
    }
    final fromSquare = LudoGame.trackSquare(c, from);
    if (fromSquare != null &&
        !LudoGame.isSafe(fromSquare) &&
        _threatened(game, c, fromSquare)) {
      score += 20 + from / 3;
    }
    if (score > bestScore) {
      bestScore = score;
      best = t;
    }
  }
  return best;
}

/// Whether an opponent token sits 1..6 squares behind [square] and could
/// reach it on the shared track.
bool _threatened(LudoGame game, LudoColor me, int square) {
  for (final p in game.players) {
    if (p.color == me || game.ranking.contains(p.color)) continue;
    for (final progress in game.tokens[p.color]!) {
      final s = LudoGame.trackSquare(p.color, progress);
      if (s == null) continue;
      final gap = (square - s) % trackLength;
      if (gap >= 1 && gap <= 6 && progress + gap <= lastTrackStep) {
        return true;
      }
    }
  }
  return false;
}
