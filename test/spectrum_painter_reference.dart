import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';

double _safeLevel(double value) => value.isFinite ? value.clamp(0.0, 1.0) : 0;

/// FFT arrivals repaint this surface directly, without rebuilding or laying out
/// a widget per 33ms sample. Horizontal geometry and the shader survive frames.
class OriginalSpectrumPainter extends CustomPainter {
  OriginalSpectrumPainter({
    required this.levels,
    required this.startColor,
    required this.endColor,
  }) : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color startColor;
  final Color endColor;
  final _paint = Paint();
  Size? _geometrySize;
  List<_SpectrumBar> _bars = const [];

  double sampleAt(double position) {
    final frame = levels.value;
    if (frame.isEmpty) return 0;
    final safePosition = position.isFinite ? position.clamp(0.0, 1.0) : 0.0;
    final scaled = safePosition * (frame.length - 1);
    final left = scaled.floor();
    final right = math.min(left + 1, frame.length - 1);
    final fraction = scaled - left;
    return _safeLevel(frame[left]) * (1.0 - fraction) +
        _safeLevel(frame[right]) * fraction;
  }

  void _layoutBars(Size size) {
    if (size == _geometrySize) return;
    final count = (size.width / 5).floor().clamp(1, 112);
    final gap = math.min(2.0, size.width / count * .4);
    final barWidth = (size.width - gap * (count - 1)) / count;
    _bars = List.generate(count, (index) {
      final normalized = count == 1 ? .5 : index / (count - 1);
      final edgeFade = math.sin(math.pi * normalized).clamp(.18, 1.0);
      return _SpectrumBar(
        left: index * (barWidth + gap),
        width: barWidth,
        position: normalized,
        edgeFade: edgeFade,
      );
    }, growable: false);
    _paint.shader = LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [startColor, endColor],
    ).createShader(Offset.zero & size);
    _geometrySize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    _layoutBars(size);
    final baselineHeight = math.min(2.0, size.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final bar in _bars) {
      final height = math.max(
        baselineHeight,
        size.height * sampleAt(bar.position) * bar.edgeFade,
      );
      _paint.color = Colors.white.withValues(alpha: .35 + bar.edgeFade * .65);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, size.height - height, bar.width, height),
          Radius.circular(bar.width / 2),
        ),
        _paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OriginalSpectrumPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor;
}

class _SpectrumBar {
  const _SpectrumBar({
    required this.left,
    required this.width,
    required this.position,
    required this.edgeFade,
  });

  final double left;
  final double width;
  final double position;
  final double edgeFade;
}
