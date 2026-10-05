import 'dart:math' as math;

import 'package:dan_player/process_resource_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

double _resourceMaximum(double maximum) =>
    maximum.isFinite && maximum > 0 ? maximum : 1.0;

bool _knownResourceValue(double? value, double maximum) =>
    value != null &&
    value.isFinite &&
    value >= 0 &&
    value <= _resourceMaximum(maximum);

/// A bounded, sample-driven range. Rounded divisions keep small fluctuations
/// readable without changing the reported utilization or starting a ticker.
@immutable
class ProcessResourceChartScale {
  const ProcessResourceChartScale(this.minimum, this.maximum, this.division);

  final double minimum, maximum, division;

  factory ProcessResourceChartScale.fromHistory(List<double?> history,
      {required double maximum, double minimumSpan = 1}) {
    final limit = _resourceMaximum(maximum);
    final values = history
        .whereType<double>()
        .where((value) => _knownResourceValue(value, limit));
    double? low, high;
    for (final value in values) {
      low = low == null ? value : math.min(low, value);
      high = high == null ? value : math.max(high, value);
    }
    if (low == null || high == null) {
      return ProcessResourceChartScale(0, limit, _niceStep(limit / 4));
    }
    final floorSpan =
        minimumSpan.isFinite && minimumSpan > 0 ? minimumSpan : 1.0;
    final span = math.min(limit, math.max(floorSpan, (high - low) * 1.25));
    final padding = (span - (high - low)) / 2;
    var lower = low - padding, upper = high + padding;
    if (lower < 0) {
      upper -= lower;
      lower = 0;
    }
    if (upper > limit) {
      lower = math.max(0, lower - (upper - limit));
      upper = limit;
    }
    final step = _niceStep(span / 4);
    return ProcessResourceChartScale((lower / step).floor() * step,
        math.min(limit, (upper / step).ceil() * step), step);
  }

  static double _niceStep(double value) {
    if (!value.isFinite || value <= 0) return 1;
    final base = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
    final scaled = value / base;
    return base *
        (scaled <= 1
            ? 1
            : scaled <= 2
                ? 2
                : scaled <= 5
                    ? 5
                    : 10);
  }

  double fraction(double value) => maximum > minimum
      ? ((value - minimum) / (maximum - minimum)).clamp(0, 1)
      : 0;

  String format(double value, {String unit = '%'}) {
    final decimals = division >= 1
        ? 0
        : division >= .1
            ? 1
            : 2;
    return '${value.toStringAsFixed(decimals)}$unit';
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessResourceChartScale &&
      minimum == other.minimum &&
      maximum == other.maximum &&
      division == other.division;
  @override
  int get hashCode => Object.hash(minimum, maximum, division);
}

/// Keeps an existing range while samples fit. It contracts only after the
/// needed span drops below half, so quantization boundaries do not cause a
/// visible jump on every small change. Empty histories retire the old range.
class ProcessResourceChartScaleTracker {
  ProcessResourceChartScale? _scale;
  double? _limit, _minimumSpan;

  void reset() => _scale = null;

  ProcessResourceChartScale resolve(List<double?> history,
      {required double maximum, double minimumSpan = 1}) {
    final candidate = ProcessResourceChartScale.fromHistory(history,
        maximum: maximum, minimumSpan: minimumSpan);
    final current = _scale;
    final values = history
        .whereType<double>()
        .where((value) => _knownResourceValue(value, maximum));
    final reuse = current != null &&
        _limit == maximum &&
        _minimumSpan == minimumSpan &&
        values.isNotEmpty &&
        values.every(
            (value) => value >= current.minimum && value <= current.maximum) &&
        current.maximum - current.minimum <=
            (candidate.maximum - candidate.minimum) * 2;
    _limit = maximum;
    _minimumSpan = minimumSpan;
    return _scale = reuse ? current : candidate;
  }
}

/// A static resource chart, shared by the settings surface and compact views.
/// Unknown samples break the line instead of being reported as zero.
class ProcessResourceChart extends StatelessWidget {
  const ProcessResourceChart({
    super.key,
    required this.history,
    required this.value,
    required this.maximum,
    required this.mode,
    required this.color,
    required this.track,
    required this.height,
    this.lineScale,
  });

  final List<double?> history;
  final double? value;
  final double maximum, height;
  final ProcessResourceDisplay mode;
  final Color color, track;
  final ProcessResourceChartScale? lineScale;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
          painter: _ResourceGraph(
              history: history,
              value: value,
              maximum: maximum,
              lineScale: lineScale ??
                  (mode == ProcessResourceDisplay.line
                      ? ProcessResourceChartScale.fromHistory(history,
                          maximum: maximum)
                      : const ProcessResourceChartScale(0, 1, 1)),
              mode: mode,
              color: color,
              track: track)));
}

class _ResourceGraph extends CustomPainter {
  const _ResourceGraph({
    required this.history,
    required this.value,
    required this.maximum,
    required this.lineScale,
    required this.mode,
    required this.color,
    required this.track,
  });
  final List<double?> history;
  final double? value;
  final double maximum;
  final ProcessResourceChartScale lineScale;
  final ProcessResourceDisplay mode;
  final Color color, track;

  double _fraction(double value) =>
      maximum.isFinite && maximum > 0 ? (value / maximum).clamp(0, 1) : 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (mode == ProcessResourceDisplay.bar) {
      final radius = Radius.circular(size.height / 2);
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius),
          Paint()..color = track);
      if (_knownResourceValue(value, maximum)) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(
                    0, 0, size.width * _fraction(value!), size.height),
                radius),
            Paint()..color = color);
      }
      return;
    }
    canvas.drawLine(Offset(0, size.height - 1),
        Offset(size.width, size.height - 1), Paint()..color = track);
    final compact = size.height <= 14;
    final inset = (compact ? 1.0 : 2.0).clamp(0.0, size.height / 2);
    if (!compact) {
      final gridPaint = Paint()..color = track.withValues(alpha: track.a * .5);
      // No axes inside the compact sparkline; its tooltip reports the range.
      for (var tick = lineScale.minimum;
          tick <= lineScale.maximum + lineScale.division * .01;
          tick += lineScale.division) {
        final y =
            (size.height - inset * 2) * (1 - lineScale.fraction(tick)) + inset;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
    final path = Path();
    bool connected = false;
    for (var index = 0; index < history.length; index++) {
      final value = history[index];
      if (value == null || !_knownResourceValue(value, maximum)) {
        connected = false;
        continue;
      }
      final x =
          history.length < 2 ? 0.0 : index * size.width / (history.length - 1);
      final y = (size.height - inset * 2).clamp(0, double.infinity) *
              (1 - lineScale.fraction(value)) +
          inset;
      if (connected) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      final next = index + 1 < history.length ? history[index + 1] : null;
      final isolated = !connected && !_knownResourceValue(next, maximum);
      if (!compact || isolated) {
        canvas.drawCircle(Offset(x, y), inset, Paint()..color = color);
      }
      connected = true;
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = compact ? 1.4 : 2
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _ResourceGraph old) =>
      old.value != value ||
      old.maximum != maximum ||
      old.lineScale != lineScale ||
      old.mode != mode ||
      old.color != color ||
      old.track != track ||
      !listEquals(old.history, history);
}
