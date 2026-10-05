import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared static plotting for daily and weekday comparisons. Both use the
/// same solid/dashed paths, palette, grid and selected-point markers.
void paintStatisticsComparisonLines(Canvas canvas, Size size,
    {required int count,
    required double maximum,
    required num Function(int) current,
    required num Function(int) previous,
    required int selection,
    required Color currentColor,
    required Color previousColor,
    required Color gridColor,
    bool centerSlots = false,
    bool showCurrent = true,
    bool showPrevious = true}) {
  if (size.isEmpty || count <= 0) return;
  final width = math.max(0.0, size.width - 24);
  final height = math.max(0.0, size.height - 24);
  Offset point(int index, num value) => Offset(
      centerSlots
          ? (index + .5) * size.width / count
          : 12 + index * width / math.max(1, count - 1),
      12 + height * (1 - (maximum == 0 ? 0 : value / maximum)));
  final grid = Paint()
    ..color = gridColor.withValues(alpha: .65)
    ..strokeWidth = 1;
  for (var row = 0; row <= 3; row++) {
    final y = 12 + height * row / 3;
    canvas.drawLine(Offset(12, y), Offset(12 + width, y), grid);
  }
  Path series(num Function(int) value) {
    final path = Path();
    for (var index = 0; index < count; index++) {
      final offset = point(index, value(index));
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    return path;
  }

  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..color = previousColor;
  if (showPrevious) {
    for (final metric in series(previous).computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 10) {
        canvas.drawPath(
            metric.extractPath(offset, math.min(offset + 6, metric.length)),
            line);
      }
    }
  }
  line.color = currentColor;
  if (showCurrent) canvas.drawPath(series(current), line);
  final selected = point(selection, current(selection));
  canvas.drawLine(
      Offset(selected.dx, 12), Offset(selected.dx, 12 + height), grid);
  if (showPrevious) {
    canvas.drawCircle(point(selection, previous(selection)), 4,
        Paint()..color = previousColor);
  }
  if (showCurrent) {
    canvas.drawCircle(selected, 4, Paint()..color = currentColor);
  }
}
