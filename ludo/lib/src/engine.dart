import 'dart:math';

/// The four seats, in turn order (clockwise around the board).
enum LudoColor {
  red('Red'),
  green('Green'),
  yellow('Yellow'),
  blue('Blue');

  const LudoColor(this.label);
  final String label;
}

class Player {
  const Player(this.color, {this.isComputer = false});
  final LudoColor color;
  final bool isComputer;

  String get name => isComputer ? '${color.label} (CPU)' : color.label;
}

/// Two players sit in opposite corners, facing each other: if the two
/// chosen colours are side by side, the second player takes the colour
/// opposite the first. Three or four players keep their colours.
List<Player> seatPlayers(List<Player> players) {
  if (players.length != 2) return players;
  final [a, b] = players;
  if ((b.color.index - a.color.index).isEven) return players;
  final opposite = LudoColor.values[(a.color.index + 2) % 4];
  return [a, Player(opposite, isComputer: b.isComputer)]
    ..sort((x, y) => x.color.index.compareTo(y.color.index));
}

/// A token's progress along its own route:
/// [inYard], then 0..50 on the shared track starting at the player's start
/// square, then 51..55 up the player's home column, then [home].
const int inYard = -1;
const int lastTrackStep = 50;
const int home = 56;
const int trackLength = 52;
const int tokensPerPlayer = 4;
const int yardMissLimit = 3;

enum TurnPhase { roll, move, over }

enum RollResult {
  /// The player must now pick one of [LudoGame.movableTokens].
  mustMove,

  /// No token can move with this roll; the turn moved on (or, on a six, the
  /// same player rolls again).
  noMoves,

  /// Third six in a row: the turn is lost.
  threeSixes,
}

class Capture {
  const Capture(this.color, this.token);
  final LudoColor color;
  final int token;
}

class MoveResult {
  const MoveResult({
    required this.color,
    required this.token,
    required this.from,
    required this.to,
    required this.captures,
    required this.extraTurn,
  });
  final LudoColor color;
  final int token;
  final int from;
  final int to;
  final List<Capture> captures;
  final bool extraTurn;

  bool get reachedHome => to == home;
}

/// Standard Ludo rules:
/// - a six brings a token out of the yard onto the start square;
/// - a six, a capture or bringing a token home earns another roll;
/// - three sixes in a row lose the turn;
/// - landing on an opponent captures it (sends it back to the yard), except
///   on the start squares and star squares, which are safe;
/// - a token must reach home with an exact roll;
/// - a player stuck in the yard is given a six after [yardMissLimit] turns
///   in a row without one, so nobody waits long to start.
class LudoGame {
  LudoGame(List<Player> players, {Random? random})
    : players = List.unmodifiable(players),
      _random = random ?? Random() {
    if (players.length < 2 || players.length > 4) {
      throw ArgumentError('Ludo needs 2 to 4 players');
    }
    if (players.map((p) => p.color).toSet().length != players.length) {
      throw ArgumentError('Each player needs a different colour');
    }
    for (final p in players) {
      tokens[p.color] = List.filled(tokensPerPlayer, inYard);
      yardMisses[p.color] = 0;
    }
  }

  final List<Player> players;
  final Random _random;
  final Map<LudoColor, List<int>> tokens = {};

  /// Turns in a row each player has rolled without a six while having no
  /// token on the board.
  final Map<LudoColor, int> yardMisses = {};

  /// Colours in the order they finished.
  final List<LudoColor> ranking = [];

  int _current = 0;
  TurnPhase phase = TurnPhase.roll;

  /// The last value rolled, and who rolled it.
  int? dice;
  LudoColor? lastRoller;
  int sixesInRow = 0;

  Player get current => players[_current];
  bool get isOver => phase == TurnPhase.over;

  static int startSquare(LudoColor c) => c.index * 13;

  /// The shared-track square (0..51) a token is on, or null if it is in the
  /// yard, in its home column or home.
  static int? trackSquare(LudoColor c, int progress) =>
      progress >= 0 && progress <= lastTrackStep
      ? (startSquare(c) + progress) % trackLength
      : null;

  /// Start squares and the star squares eight steps after them.
  static bool isSafe(int square) => square % 13 == 0 || square % 13 == 8;

  /// Where token progress [from] ends up after a roll of [roll], or null if
  /// it can't move.
  static int? targetFor(int from, int roll) {
    if (from == inYard) return roll == 6 ? 0 : null;
    if (from == home) return null;
    final to = from + roll;
    return to <= home ? to : null;
  }

  bool hasFinished(LudoColor c) => tokens[c]!.every((t) => t == home);

  List<int> movableTokens() {
    final d = dice;
    if (phase != TurnPhase.move || d == null) return const [];
    return _movable(current.color, d);
  }

  List<int> _movable(LudoColor c, int roll) => [
    for (var i = 0; i < tokensPerPlayer; i++)
      if (targetFor(tokens[c]![i], roll) != null) i,
  ];

  /// No token on the board: only a six lets the player move.
  bool isStuckInYard(LudoColor c) =>
      tokens[c]!.every((t) => t == inYard || t == home);

  /// A random roll for the current player, or a six once they have missed
  /// [yardMissLimit] times in a row while stuck in the yard.
  int rollDie() {
    final c = current.color;
    if (isStuckInYard(c) && yardMisses[c]! >= yardMissLimit) return 6;
    return _random.nextInt(6) + 1;
  }

  /// Applies a roll for the current player.
  RollResult roll([int? value]) {
    if (phase != TurnPhase.roll) throw StateError('Not time to roll');
    final v = value ?? rollDie();
    if (v < 1 || v > 6) throw ArgumentError.value(v, 'value');
    dice = v;
    lastRoller = current.color;
    final c = current.color;
    yardMisses[c] = isStuckInYard(c) && v != 6 ? yardMisses[c]! + 1 : 0;
    sixesInRow = v == 6 ? sixesInRow + 1 : 0;
    if (sixesInRow == 3) {
      _endTurn(extraTurn: false);
      return RollResult.threeSixes;
    }
    if (_movable(current.color, v).isEmpty) {
      _endTurn(extraTurn: v == 6);
      return RollResult.noMoves;
    }
    phase = TurnPhase.move;
    return RollResult.mustMove;
  }

  /// Opponent tokens that a token of [c] landing on [progress] would capture.
  List<Capture> capturesAt(LudoColor c, int progress) {
    final square = trackSquare(c, progress);
    if (square == null || isSafe(square)) return const [];
    return [
      for (final p in players)
        if (p.color != c)
          for (var i = 0; i < tokensPerPlayer; i++)
            if (trackSquare(p.color, tokens[p.color]![i]) == square)
              Capture(p.color, i),
    ];
  }

  MoveResult move(int token) {
    if (!movableTokens().contains(token)) {
      throw StateError('Token $token cannot move');
    }
    final c = current.color;
    final from = tokens[c]![token];
    final to = targetFor(from, dice!)!;
    final captures = capturesAt(c, to);
    tokens[c]![token] = to;
    for (final cap in captures) {
      tokens[cap.color]![cap.token] = inYard;
    }

    var extra = dice == 6 || captures.isNotEmpty || to == home;
    if (hasFinished(c)) {
      ranking.add(c);
      extra = false;
      final left = players.where((p) => !ranking.contains(p.color)).toList();
      if (left.length == 1) {
        ranking.add(left.single.color);
        phase = TurnPhase.over;
      }
    }
    if (!isOver) _endTurn(extraTurn: extra);
    return MoveResult(
      color: c,
      token: token,
      from: from,
      to: to,
      captures: captures,
      extraTurn: extra,
    );
  }

  void _endTurn({required bool extraTurn}) {
    phase = TurnPhase.roll;
    if (extraTurn) return;
    sixesInRow = 0;
    do {
      _current = (_current + 1) % players.length;
    } while (ranking.contains(current.color));
  }
}
