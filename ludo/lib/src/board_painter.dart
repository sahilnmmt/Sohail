import 'dart:math';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'geometry.dart';

const Map<LudoColor, Color> seatColors = {
  LudoColor.red: Color(0xFFE53935),
  LudoColor.green: Color(0xFF43A047),
  LudoColor.yellow: Color(0xFFFDD835),
  LudoColor.blue: Color(0xFF1E88E5),
};

/// Draws the empty board. The red quarter (top-left yard, left arm, left
/// centre triangle) is drawn four times, rotated a quarter turn each time.
class BoardPainter extends CustomPainter {
  const BoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // A square of the even grid, as drawn inside the yards.
    final cell = size.width * BoardGeometry.along / BoardGeometry.cells;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1, cell / 30);
    final starPaint = Paint()..color = const Color(0xFFBDBDBD);

    Offset at(double col, double row) =>
        BoardGeometry.toBoardOffset(Offset(col, row))
            .scale(size.width, size.height);
    Rect r(double col, double row, double w, double h) =>
        Rect.fromPoints(at(col, row), at(col + w, row + h));

    for (final color in LudoColor.values) {
      final seat = seatColors[color]!;
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(pi / 2 * color.index);
      canvas.translate(-size.width / 2, -size.height / 2);

      // Yard.
      canvas.drawRect(r(0, 0, 6, 6), Paint()..color = seat);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromPoints(
            at(BoardGeometry.yardBox.left, BoardGeometry.yardBox.top),
            at(BoardGeometry.yardBox.right, BoardGeometry.yardBox.bottom),
          ),
          Radius.circular(cell * 0.4),
        ),
        Paint()..color = Colors.white,
      );
      for (final slot in BoardGeometry.yardSlots) {
        canvas.drawCircle(
          at(slot.dx, slot.dy),
          cell * 0.55,
          Paint()..color = seat.withValues(alpha: 0.3),
        );
      }

      // Left arm: 3 rows x 6 columns of track, with the home column and the
      // start square in the seat colour.
      for (var row = 6; row <= 8; row++) {
        for (var col = 0; col <= 5; col++) {
          final rect = r(col.toDouble(), row.toDouble(), 1, 1);
          final coloured = (row == 7 && col >= 1) || (row == 6 && col == 1);
          if (coloured) canvas.drawRect(rect, Paint()..color = seat);
          canvas.drawRect(rect, line);
        }
      }
      _drawStar(canvas, r(2, 8, 1, 1), starPaint);
      _drawArrow(canvas, r(0, 7, 1, 1), seat);

      // Centre triangle.
      canvas.drawPath(
        Path()
          ..moveTo(at(6, 6).dx, at(6, 6).dy)
          ..lineTo(at(7.5, 7.5).dx, at(7.5, 7.5).dy)
          ..lineTo(at(6, 9).dx, at(6, 9).dy)
          ..close(),
        Paint()..color = seat,
      );
      canvas.restore();
    }

    canvas.drawRect(Offset.zero & size, line);
  }

  static void _drawStar(Canvas canvas, Rect rect, Paint paint) {
    final c = rect.center;
    final outer = rect.shortestSide * 0.42;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -pi / 2 + i * pi / 5;
      final p = c + Offset(cos(a), sin(a)) * radius;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  /// A small arrow pointing into the home column.
  static void _drawArrow(Canvas canvas, Rect rect, Color color) {
    final c = rect.center;
    final s = rect.shortestSide * 0.3;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + s, c.dy)
        ..lineTo(c.dx - s * 0.7, c.dy - s)
        ..lineTo(c.dx - s * 0.7, c.dy + s)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => false;
}
