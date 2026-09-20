import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Two independently moving copies of the real, blurred artwork. Unlike a
/// palette approximation this preserves spatial colour and luminance detail.
/// Each layer is raster-isolated; phase updates only repaint transforms.
class FluidArtwork extends StatelessWidget {
  const FluidArtwork({super.key, required this.phase, required this.child});
  final ValueListenable<double> phase;
  final Widget child;

  @override
  Widget build(BuildContext context) => Flow(
        delegate: ArtworkFlowDelegate(phase),
        clipBehavior: Clip.hardEdge,
        children: [
          RepaintBoundary(child: child),
          RepaintBoundary(child: child)
        ],
      );
}

class ArtworkFlowDelegate extends FlowDelegate {
  ArtworkFlowDelegate(this.phase) : super(repaint: phase);
  final ValueListenable<double> phase;

  Matrix4 transform(Size size, int layer) {
    final t = phase.value * math.pi * 2;
    final angle = layer == 0 ? .15 * math.sin(t) : -.22 * math.sin(t + .8);
    final dx = size.width * .055 * math.sin(t + layer * 2.1);
    final dy = size.height * .055 * math.cos(t * 2 + layer * 1.3);
    // Cover the viewport at every angle, including wide and portrait windows.
    final c = math.cos(angle).abs();
    final s = math.sin(angle).abs();
    final cover = math.max(c + size.height / math.max(1, size.width) * s,
        c + size.width / math.max(1, size.height) * s);
    return Matrix4.identity()
      ..translateByDouble(size.width / 2 + dx, size.height / 2 + dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(cover * 1.18, cover * 1.18, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    context.paintChild(0, transform: transform(context.size, 0));
    context.paintChild(1, transform: transform(context.size, 1), opacity: .38);
  }

  @override
  bool shouldRepaint(ArtworkFlowDelegate oldDelegate) =>
      !identical(phase, oldDelegate.phase);
}
