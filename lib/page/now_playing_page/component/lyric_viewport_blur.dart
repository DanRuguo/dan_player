import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'lyric_motion.dart';

/// Fixed, progressively blurred bands above a composited lyric viewport.
///
/// The viewport paints once. These overlays leave its clear centre untouched,
/// rather than changing the sampling of individual lyric paragraphs.
class LyricViewportBlur extends StatelessWidget {
  const LyricViewportBlur({
    super.key,
    required this.enabled,
    required this.reading,
    required this.child,
    this.topFraction = .25,
    this.bottomFraction = .22,
  });

  final bool enabled;
  final double topFraction;
  final double bottomFraction;

  /// The existing reading clock: one is blurred and zero is clear.
  final Animation<double> reading;
  final Widget child;

  // Small, disjoint strips vary the actual Gaussian radius. A ShaderMask or
  // Opacity around a BackdropFilter would put the filter in a fresh, empty
  // surface, and cannot reliably mask the previously composited lyrics.
  static const _gradientSteps = 6;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // The lyric scroll viewport supplies the actual available height,
          // including the space remaining above an optional spectrum.
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return child;
          }
          final height = constraints.maxHeight;
          final topFraction = _fraction(this.topFraction, .25);
          final bottomFraction = _fraction(this.bottomFraction, .22);
          return ClipRect(
            child: AnimatedBuilder(
              animation: enabled && (topFraction > 0 || bottomFraction > 0)
                  ? reading
                  : const AlwaysStoppedAnimation<double>(0),
              child: child,
              builder: (context, child) {
                final sigma = enabled
                    ? LyricMotion.blurForDistance(2) *
                        reading.value.clamp(0.0, 1.0)
                    : 0.0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    ..._bands(height * topFraction, sigma, top: true),
                    ..._bands(height * bottomFraction, sigma, top: false),
                  ],
                );
              },
            ),
          );
        },
      );

  double _fraction(double value, double fallback) =>
      value.isFinite ? value.clamp(0.0, .45).toDouble() : fallback;

  Iterable<Widget> _bands(double extent, double sigma,
      {required bool top}) sync* {
    if (extent <= 0) return;
    for (var index = 0; index < _gradientSteps; index++) {
      // Index zero is at the clear boundary; the radius only grows towards
      // the outside of this configured band. None of its output crosses the
      // boundary into the centre.
      final near = extent * index / _gradientSteps;
      final far = extent * (index + 1) / _gradientSteps;
      final progress = (index + .5) / _gradientSteps;
      final radius = sigma * progress * progress * (3 - 2 * progress);
      yield Positioned(
        key: ValueKey((top, index)),
        left: 0,
        right: 0,
        top: top ? extent - far : null,
        bottom: top ? null : extent - far,
        height: far - near,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: ClipRect(
              child: BackdropFilter(
                // No shared backdrop snapshot: each filter reads this region
                // at its actual location. A zero-radius pass must not replace
                // the lyrics with an identity backdrop during hover/entrance.
                enabled: enabled && radius > 0,
                filter: ui.ImageFilter.blur(sigmaX: radius, sigmaY: radius),
                blendMode: BlendMode.srcOver,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    }
  }
}
