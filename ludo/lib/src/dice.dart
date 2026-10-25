import 'package:flutter/material.dart';

/// A die face showing [value] (1..6), or a blank face when null.
class DieFace extends StatelessWidget {
  const DieFace({
    super.key,
    required this.value,
    required this.size,
    this.color = Colors.white,
    this.pipColor = const Color(0xFF212121),
  });

  final int? value;
  final double size;
  final Color color;
  final Color pipColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.2),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: CustomPaint(painter: _PipPainter(value, pipColor)),
    );
  }
}

class _PipPainter extends CustomPainter {
  const _PipPainter(this.value, this.color);
  final int? value;
  final Color color;

  static const _pips = <int, List<Offset>>{
    1: [Offset(0.5, 0.5)],
    2: [Offset(0.27, 0.27), Offset(0.73, 0.73)],
    3: [Offset(0.27, 0.27), Offset(0.5, 0.5), Offset(0.73, 0.73)],
    4: [
      Offset(0.27, 0.27),
      Offset(0.73, 0.27),
      Offset(0.27, 0.73),
      Offset(0.73, 0.73),
    ],
    5: [
      Offset(0.27, 0.27),
      Offset(0.73, 0.27),
      Offset(0.5, 0.5),
      Offset(0.27, 0.73),
      Offset(0.73, 0.73),
    ],
    6: [
      Offset(0.27, 0.25),
      Offset(0.73, 0.25),
      Offset(0.27, 0.5),
      Offset(0.73, 0.5),
      Offset(0.27, 0.75),
      Offset(0.73, 0.75),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final pips = _pips[value];
    if (pips == null) return;
    final paint = Paint()..color = color;
    for (final p in pips) {
      canvas.drawCircle(
        Offset(p.dx * size.width, p.dy * size.height),
        size.width * 0.09,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PipPainter old) =>
      old.value != value || old.color != color;
}
