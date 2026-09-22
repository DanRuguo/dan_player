import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A static, scene-aligned edge shade over the flowing cover, below its theme
/// veil. Normalized coordinates keep the same falloff on wide/portrait windows;
/// the shade must never rotate with either artwork layer.
class ArtworkVignette extends StatelessWidget {
  const ArtworkVignette({super.key});

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _ArtworkVignettePainter());
}

class _ArtworkVignettePainter extends CustomPainter {
  const _ArtworkVignettePainter();

  // Approximate the reference's smooth radial attenuation with a native
  // gradient. These stops are created once: no shader asset, image, ticker,
  // offscreen layer, or per-frame curve evaluation is needed.
  static final _paint = Paint()
    ..isAntiAlias = false
    ..shader = ui.Gradient.radial(
      const Offset(.5, .5),
      .8,
      List.generate(17, (index) {
        final t = index / 16;
        return const Color(0xff000000)
            .withValues(alpha: .4 * t * t * (3 - 2 * t));
      }),
      List.generate(17, (index) => (.3 + .5 * index / 16) / .8),
    );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width, size.height);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 1, 1), _paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtworkVignettePainter oldDelegate) => false;
}
