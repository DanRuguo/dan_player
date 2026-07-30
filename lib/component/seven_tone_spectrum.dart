import 'dart:math' as math;

import 'package:flutter/material.dart';

class SevenToneSpectrum extends StatelessWidget {
  const SevenToneSpectrum({
    super.key,
    required this.levels,
    required this.color,
    this.size = const Size(34.0, 16.0),
  });

  final List<double> levels;
  final Color color;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final visibleLevels =
        disableAnimations ? const <double>[0, 0, 0, 0, 0, 0, 0] : levels;
    return Tooltip(
      message: "Do Re Mi Fa Sol La Si 实时频谱",
      child: Semantics(
        label: "歌曲实时七音频谱",
        child: RepaintBoundary(
          child: SizedBox.fromSize(
            size: size,
            child: CustomPaint(
              painter: _SevenToneSpectrumPainter(
                levels: visibleLevels,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SevenToneSpectrumPainter extends CustomPainter {
  const _SevenToneSpectrumPainter({
    required this.levels,
    required this.color,
  });

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 7;
    final gap = math.max(1.2, size.width * 0.035);
    final barWidth = (size.width - gap * (barCount - 1)) / barCount;
    final paint = Paint()..color = color;

    for (var i = 0; i < barCount; i++) {
      final level = (i < levels.length ? levels[i] : 0.0).clamp(0.0, 1.0);
      final height = math.max(1.4, size.height * level);
      final left = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SevenToneSpectrumPainter oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.color != color;
}
