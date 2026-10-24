// Data used per day, one bar per day. Tap a bar to read its value.
import 'dart:math';

import 'package:flutter/material.dart';

import '../format.dart';

class DailyBarChart extends StatefulWidget {
  /// Oldest first.
  final List<(DateTime, int)> days;
  final double height;

  const DailyBarChart({super.key, required this.days, this.height = 160});

  @override
  State<DailyBarChart> createState() => _DailyBarChartState();
}

class _DailyBarChartState extends State<DailyBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final days = widget.days;
    final peak = days.fold<int>(0, (m, d) => max(m, d.$2));
    final sel = _selected != null && _selected! < days.length ? _selected! : days.length - 1;
    final labelEvery = days.length <= 7 ? 1 : 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${days.length <= 7 ? formatWeekday(days[sel].$1) : ''} ${formatDate(days[sel].$1)}: ${formatBytes(days[sel].$2)}',
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (context, box) {
            final slot = box.maxWidth / days.length;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => setState(() => _selected = (d.localPosition.dx / slot).floor().clamp(0, days.length - 1)),
              onHorizontalDragUpdate: (d) =>
                  setState(() => _selected = (d.localPosition.dx / slot).floor().clamp(0, days.length - 1)),
              child: CustomPaint(
                size: Size(box.maxWidth, widget.height),
                painter: _BarsPainter(
                  values: [for (final d in days) d.$2],
                  peak: peak,
                  selected: sel,
                  bar: scheme.primary,
                  dim: scheme.primary.withValues(alpha: 0.45),
                  grid: scheme.outlineVariant,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Text(
                  (days.length - 1 - i) % labelEvery == 0
                      ? (days.length <= 7 ? formatWeekday(days[i].$1) : formatDate(days[i].$1))
                      : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<int> values;
  final int peak;
  final int selected;
  final Color bar;
  final Color dim;
  final Color grid;

  _BarsPainter({
    required this.values,
    required this.peak,
    required this.selected,
    required this.bar,
    required this.dim,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()
      ..color = grid
      ..strokeWidth = 1);
    if (peak <= 0) return;
    final slot = size.width / values.length;
    final width = min(slot - 2, 28.0);
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final h = max(2.0, size.height * values[i] / peak);
      final left = i * slot + (slot - width) / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, size.height - h, width, h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = i == selected ? bar : dim);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.selected != selected || old.bar != bar || old.peak != peak;
}
