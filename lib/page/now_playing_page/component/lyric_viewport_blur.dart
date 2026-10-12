import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'lyric_motion.dart';

/// Fixed blur bands above an already composited lyric viewport.
///
/// The viewport paints once. Both bands read that same backdrop, rather than
/// changing the sampling or blur of individual lyric paragraphs.
class LyricViewportBlur extends StatefulWidget {
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

  @override
  State<LyricViewportBlur> createState() => _LyricViewportBlurState();
}

class _LyricViewportBlurState extends State<LyricViewportBlur> {
  final _backdropKey = BackdropKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // The lyric scroll viewport supplies the actual available height,
          // including the space remaining above an optional spectrum.
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return widget.child;
          }
          final height = constraints.maxHeight;
          final topFraction = _fraction(widget.topFraction, .25);
          final bottomFraction = _fraction(widget.bottomFraction, .22);
          return ClipRect(
            child: BackdropGroup(
              backdropKey: _backdropKey,
              child: AnimatedBuilder(
                animation:
                    widget.enabled && (topFraction > 0 || bottomFraction > 0)
                        ? widget.reading
                        : const AlwaysStoppedAnimation<double>(0),
                child: widget.child,
                builder: (context, child) {
                  final sigma = widget.enabled
                      ? LyricMotion.blurForDistance(2) *
                          widget.reading.value.clamp(0.0, 1.0)
                      : 0.0;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      child!,
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: height * topFraction,
                        child: _band(sigma, visible: topFraction > 0),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: height * (1 - bottomFraction),
                        bottom: 0,
                        child: _band(sigma, visible: bottomFraction > 0),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );

  double _fraction(double value, double fallback) =>
      value.isFinite ? value.clamp(0.0, .45).toDouble() : fallback;

  Widget _band(double sigma, {required bool visible}) => IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRect(
            child: visible
                ? BackdropFilter.grouped(
                    // Keep the same backdrop layers throughout reading's zero
                    // crossing. Accessibility/visibility gates may disable them.
                    enabled: widget.enabled,
                    filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    // Replace the captured band, including at zero sigma.
                    // Source-over would apply its alpha twice under a fade.
                    blendMode: BlendMode.src,
                    child: const SizedBox.expand(),
                  )
                : const SizedBox.expand(),
          ),
        ),
      );
}
