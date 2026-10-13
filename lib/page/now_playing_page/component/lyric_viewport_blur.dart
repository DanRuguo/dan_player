import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

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
  static const _gradientSteps = 12;
  static const _maximumSigma = 8.0;

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
          final identityRadius = .1 / View.of(context).devicePixelRatio;
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
                    ? _maximumSigma * reading.value.clamp(0.0, 1.0)
                    : 0.0;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    ..._bands(height * topFraction, sigma,
                        top: true, identityRadius: identityRadius),
                    ..._bands(height * bottomFraction, sigma,
                        top: false, identityRadius: identityRadius),
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
      {required bool top, required double identityRadius}) sync* {
    if (extent <= 0) return;
    for (var index = 0; index < _gradientSteps; index++) {
      // Index zero is at the clear boundary; the radius only grows towards
      // the outside of this configured band. None of its output crosses the
      // boundary into the centre.
      final near = extent * index / _gradientSteps;
      final far = extent * (index + 1) / _gradientSteps;
      final progress = (index + .5) / _gradientSteps;
      // Use the whole band for the gradual increase, with a flat derivative
      // at the clear boundary and outer edge. No output crosses the boundary.
      final ramp = progress;
      final radius = sigma * ramp * ramp * (3 - 2 * ramp);
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
                enabled: enabled && radius >= identityRadius,
                filter: ui.ImageFilter.blur(sigmaX: radius, sigmaY: radius),
                // Replace once in a parent entrance's transparent surface.
                // Native identity kernels are disabled above, so they neither
                // erase a backdrop nor paint the same translucent ink twice.
                blendMode: BlendMode.src,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    }
  }
}
