import 'dart:math' as math;

import 'package:dan_player/component/artwork_pulse.dart';
import 'package:dan_player/component/background_image_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Two independently moving copies of the real, blurred artwork. Unlike a
/// palette approximation this preserves spatial colour and luminance detail.
/// Each layer is raster-isolated; phase updates only repaint transforms.
class FluidArtwork extends StatefulWidget {
  const FluidArtwork({
    super.key,
    required this.phase,
    required this.child,
    this.active,
    this.readLowFrequency,
  });
  final ValueListenable<double> phase;
  final Widget child;
  final ValueListenable<bool>? active;

  /// Reads the existing spectrum cache; never requests audio capture or FFT.
  final double Function()? readLowFrequency;

  @override
  State<FluidArtwork> createState() => _FluidArtworkState();
}

class _FluidArtworkState extends State<FluidArtwork> {
  final _pulse = ArtworkPulse();
  late double _lastPhase;

  @override
  void initState() {
    super.initState();
    _lastPhase = widget.phase.value;
    widget.phase.addListener(_sample);
  }

  @override
  void didUpdateWidget(FluidArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.phase, widget.phase)) {
      oldWidget.phase.removeListener(_sample);
      _lastPhase = widget.phase.value;
      widget.phase.addListener(_sample);
    }
    if (widget.readLowFrequency == null) _pulse.reset();
  }

  void _sample() {
    final phase = widget.phase.value;
    final delta = (phase - _lastPhase + 1) % 1;
    _lastPhase = phase;
    final read = widget.readLowFrequency;
    if (read == null || !(widget.active?.value ?? true)) return;
    // A stalled frame should not create a large zoom jump on recovery. The
    // parent clock already excludes all time spent paused or hidden.
    final seconds = (delta *
            BackgroundImageMotion.cycle.inMicroseconds /
            Duration.microsecondsPerSecond)
        .clamp(0.0, .1);
    _pulse.advance(seconds, read());
  }

  @override
  Widget build(BuildContext context) => Flow(
        delegate: ArtworkFlowDelegate(widget.phase,
            pulse: widget.readLowFrequency == null ? null : _pulse),
        clipBehavior: Clip.hardEdge,
        children: [
          RepaintBoundary(child: widget.child),
          RepaintBoundary(child: widget.child)
        ],
      );

  @override
  void dispose() {
    widget.phase.removeListener(_sample);
    super.dispose();
  }
}

class ArtworkFlowDelegate extends FlowDelegate {
  ArtworkFlowDelegate(this.phase, {this.pulse}) : super(repaint: phase);
  final ValueListenable<double> phase;
  final ArtworkPulse? pulse;

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
    final scale = cover * 1.18 * (pulse?.scale ?? 1);
    return Matrix4.identity()
      ..translateByDouble(size.width / 2 + dx, size.height / 2 + dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    context.paintChild(0, transform: transform(context.size, 0));
    context.paintChild(1, transform: transform(context.size, 1), opacity: .38);
  }

  @override
  bool shouldRepaint(ArtworkFlowDelegate oldDelegate) =>
      !identical(phase, oldDelegate.phase) ||
      !identical(pulse, oldDelegate.pulse);
}
