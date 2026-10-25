import 'dart:ui';

import 'engine.dart';

/// Board layout on a 15x15 grid. Positions are in cell units with (0, 0) at
/// the top-left corner; a cell's centre is at (col + 0.5, row + 0.5).
///
/// Everything is laid out for red (top-left yard, left arm) and rotated a
/// quarter turn clockwise per seat for green, yellow and blue.
class BoardGeometry {
  static const int cells = 15;
  static const Offset centre = Offset(7.5, 7.5);

  /// The shared track as seen by red: index 0 is red's start square.
  static final List<Offset> track = _buildTrack();

  static List<Offset> _buildTrack() {
    final rc = <(int, int)>[
      for (var c = 1; c <= 5; c++) (6, c),
      for (var r = 5; r >= 0; r--) (r, 6),
      (0, 7),
      for (var r = 0; r <= 5; r++) (r, 8),
      for (var c = 9; c <= 14; c++) (6, c),
      (7, 14),
      for (var c = 14; c >= 9; c--) (8, c),
      for (var r = 9; r <= 14; r++) (r, 8),
      (14, 7),
      for (var r = 14; r >= 9; r--) (r, 6),
      for (var c = 5; c >= 0; c--) (8, c),
      (7, 0),
      (6, 0),
    ];
    return [for (final (r, c) in rc) Offset(c + 0.5, r + 0.5)];
  }

  /// The white box inside each yard where tokens wait, and their spots
  /// (red's yard; the others are rotated).
  static const Rect yardBox = Rect.fromLTWH(1.5, 1.5, 3, 3);
  static const List<Offset> yardSlots = [
    Offset(2.25, 2.25),
    Offset(3.75, 2.25),
    Offset(2.25, 3.75),
    Offset(3.75, 3.75),
  ];

  /// Rotates [p] a quarter turn clockwise about the board centre, [times]
  /// times.
  static Offset rotate(Offset p, int times) {
    var o = p;
    for (var i = 0; i < times % 4; i++) {
      o = Offset(
        centre.dx - (o.dy - centre.dy),
        centre.dy + (o.dx - centre.dx),
      );
    }
    return o;
  }

  static Offset _redPosition(int progress, int token) {
    if (progress == inYard) return yardSlots[token];
    if (progress <= lastTrackStep) return track[progress];
    if (progress < home) return Offset(progress - 50 + 0.5, 7.5);
    return const Offset(6.55, 7.5);
  }

  /// Centre of the token [token] of [color] at [progress].
  static Offset position(LudoColor color, int progress, int token) =>
      rotate(_redPosition(progress, token), color.index);

  /// The cells a token passes through, one per step, when moving from
  /// [from] to [to]. Leaving the yard is a single hop to the start square.
  static List<Offset> path(LudoColor color, int token, int from, int to) => [
    for (var p = from == inYard ? 0 : from + 1; p <= to; p++)
      position(color, p, token),
  ];
}
