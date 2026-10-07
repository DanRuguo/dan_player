import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Daily and weekday plots share the same solid/dashed geometry. The snapshot
/// and plot size own it; hover, focus and palette only
/// choose how it is painted. Retain one instance per chart, without a ticker.
class StatisticsComparisonLineGeometry {
  StatisticsComparisonLineGeometry(this.size,
      {required int count,
      required double maximum,
      required num Function(int) current,
      required num Function(int) previous,
      bool centerSlots = false}) {
    if (size.isEmpty || count <= 0) return;
    final width = math.max(0.0, size.width - 24);
    final height = math.max(0.0, size.height - 24);
    Offset point(int index, num value) => Offset(
        centerSlots
            ? (index + .5) * size.width / count
            : 12 + index * width / math.max(1, count - 1),
        // A hidden series can exceed the visible series' scale. Keep its
        // cached path bounded; changing the scale rebuilds its true geometry.
        12 + height * (1 - (maximum == 0 ? 0 : (value / maximum).clamp(0, 1))));
    _current = List.generate(count, (index) => point(index, current(index)),
        growable: false);
    _previous = List.generate(count, (index) => point(index, previous(index)),
        growable: false);
    Path series(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final offset in points.skip(1)) {
        path.lineTo(offset.dx, offset.dy);
      }
      return path;
    }

    _currentPath = series(_current);
    for (final metric in series(_previous).computeMetrics()) {
      for (var offset = 0.0; offset < metric.length; offset += 10) {
        _previousDashes.add(
            metric.extractPath(offset, math.min(offset + 6, metric.length)));
      }
    }
  }

  final Size size;
  List<Offset> _current = const [], _previous = const [];
  Path? _currentPath;
  final _previousDashes = <Path>[];

  void paint(Canvas canvas,
      {required int selection,
      required Color currentColor,
      required Color previousColor,
      required Color gridColor,
      bool showCurrent = true,
      bool showPrevious = true}) {
    if (_current.isEmpty) return;
    final width = math.max(0.0, size.width - 24);
    final height = math.max(0.0, size.height - 24);
    final grid = Paint()
      ..color = gridColor.withValues(alpha: .65)
      ..strokeWidth = 1;
    for (var row = 0; row <= 3; row++) {
      final y = 12 + height * row / 3;
      canvas.drawLine(Offset(12, y), Offset(12 + width, y), grid);
    }
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = previousColor;
    if (showPrevious) {
      for (final dash in _previousDashes) {
        canvas.drawPath(dash, line);
      }
    }
    line.color = currentColor;
    if (showCurrent) canvas.drawPath(_currentPath!, line);
    final selected = _current[selection];
    canvas.drawLine(
        Offset(selected.dx, 12), Offset(selected.dx, 12 + height), grid);
    if (showPrevious) {
      canvas.drawCircle(
          _previous[selection], 4, Paint()..color = previousColor);
    }
    if (showCurrent) {
      canvas.drawCircle(selected, 4, Paint()..color = currentColor);
    }
  }
}
