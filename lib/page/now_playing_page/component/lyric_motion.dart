import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dan_player/component/app_motion.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'lyric_fractional_filter.dart';
import 'lyric_follow_words.dart';

/// Motion local to lyric surfaces. Playback time remains the sole clock for
/// word highlighting; these durations only describe presentation transitions.
abstract final class LyricMotion {
  static const lineDuration = AppMotion.lyricLine;
  static const scrollDuration = AppMotion.lyricScroll;
  static const seekScrollDuration = AppMotion.emphasized;
  static const springScrollDuration = AppMotion.lyricSpring;
  static const manualScrollGrace = Duration(seconds: 4);
  static const curve = Cubic(0.22, 0.0, 0.16, 1.0);
  // Start from rest so a new line never spends most of its travel in the
  // first few display frames; accelerate before settling into the anchor.
  // Keep this separate from the shared line/title fade curve: a scroll must
  // decelerate, remain monotonic and never spring past its target.
  static const scrollCurve = Cubic(0.22, 0.0, 0.24, 1.0);
  static const focusedFontScale = 1.50;
  static const focusedFontWeight = FontWeight.w800;
  static const maximumFollowRows = 24;

  static double blurForDistance(int distance) => switch (distance.abs()) {
        0 => 0,
        1 => 1.2,
        2 => 2.4,
        3 => 3.2,
        _ => 4.0,
      };

  /// A subtle optional settle on ordinary line advances, never on a seek.
  /// The overshoot is capped in pixels, including very long translated rows.
  static Curve scrollCurveFor({
    required bool spring,
    required double distance,
  }) =>
      spring
          ? _LyricSpringCurve(
              overshoot: math.min(12, distance.abs() * .08) /
                  math.max(1, distance.abs()))
          : scrollCurve;

  static bool reducedOf(BuildContext context) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (!AppMotion.enabled(context, MotionKind.lyrics)) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  static double opacityForDistance(int distance) => switch (distance.abs()) {
        0 => 1,
        1 => .64,
        2 => .50,
        3 => .40,
        _ => .32,
      };

  // The active line is laid out at its final size; transforms never enlarge it
  // beyond that box or change wrapping while the focus moves between lines.
  static double scaleForDistance(int distance) => switch (distance.abs()) {
        0 => 1,
        1 => .80 * 1.24 / focusedFontScale,
        2 => .78 * 1.24 / focusedFontScale,
        _ => .76 * 1.24 / focusedFontScale,
      };

  /// One shared pose for all three waiting dots, sampled from media time.
  /// Brightness advances per dot; geometry breathes and exits as a group.
  static ({
    double scale,
    double opacity,
    double progress,
    (double, double, double) dotOpacities,
  }) interludePose(Duration elapsed, Duration length, {bool reduced = false}) {
    if (reduced) {
      return (scale: 1, opacity: 1, progress: 1, dotOpacities: (1, 1, 1));
    }
    final duration = length.inMilliseconds.toDouble();
    final time = elapsed.inMicroseconds / 1000;
    const enterHold = 500.0;
    const enterFade = 180.0;
    const dotEnter = 750.0;
    const dotStagger = 80.0;
    const exitGrow = 750.0;
    const exitShrink = 250.0;
    const exitDuration = exitGrow + exitShrink;
    final body = duration - enterHold - exitDuration;
    if (duration <= 0 || time <= 0 || time >= duration) {
      return (
        scale: 0,
        opacity: 0,
        progress: time > 0 ? 1 : 0,
        dotOpacities: (0, 0, 0),
      );
    }
    // A short remainder cannot fit the three staggered entrances plus exit.
    // Keep the existing row geometry, but do not flash a partial performance.
    if (body < dotEnter + 2 * dotStagger || time < enterHold) {
      return (scale: 1, opacity: 0, progress: 0, dotOpacities: (0, 0, 0));
    }
    double smooth(double value) {
      final t = value.clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    final internal = time - enterHold;
    final exiting = internal >= body;
    final exitTime = internal - body;
    final shortBody = body < 3000;
    final cycle = body / math.max(1, (body / 4000).floor());
    final cyclePhase = (internal % cycle) / cycle;
    // Complete cycles meet the exit at scale 1 with zero velocity. The 25%
    // expansion remains visible even with small dots, without another ticker.
    final breathing = 1 + .125 * (1 - math.cos(2 * math.pi * cyclePhase));
    final scale = exiting
        ? exitTime < exitGrow
            ? 1 + .25 * smooth(exitTime / exitGrow)
            : 1.25 - .85 * smooth((exitTime - exitGrow) / exitShrink)
        : shortBody
            ? 1.0
            : breathing;
    final opacity = smooth(internal / enterFade) *
        (1 - smooth((exitTime - exitGrow) / exitShrink));
    // The last dot finishes brightening during the visible grow phase, before
    // the group contracts. All three use the real interlude interval only.
    final segment = (body + exitGrow) / 3;
    double dotOpacity(int index) {
      final bodyFraction = shortBody
          ? 1.0
          : smooth((math.min(internal, body) - index * segment) / segment);
      final fraction = exiting && index == 2
          ? bodyFraction + (1 - bodyFraction) * smooth(exitTime / exitGrow)
          : bodyFraction;
      final entry = smooth((internal - index * dotStagger) / dotEnter);
      return entry * (.2 + .7 * fraction);
    }

    return (
      scale: scale,
      opacity: opacity,
      progress: (internal / (body + exitGrow)).clamp(0.0, 1.0),
      dotOpacities: (dotOpacity(0), dotOpacity(1), dotOpacity(2)),
    );
  }

  static double progress(Duration position, Duration start, Duration length) {
    if (length <= Duration.zero) return position >= start ? 1 : 0;
    return ((position - start).inMicroseconds / length.inMicroseconds)
        .clamp(0.0, 1.0);
  }
}

/// One finite, paint-only trajectory driven by the scroll surface's clock.
/// Delaying each row's travel slightly gives a continuous wave without a
/// separate spring/ticker for every lyric or changing any paragraph geometry.
@immutable
class LyricFollowTransition {
  const LyricFollowTransition({
    required this.distance,
    required this.delay,
    required this.curve,
    required this.initialOffset,
    required this.initialBlur,
    required this.finalBlur,
  });

  final double distance;
  final double delay;
  final Curve curve;
  final double initialOffset;
  final double initialBlur;
  final double finalBlur;

  ({double offset, double blur}) sample(double progress) {
    final t = progress.clamp(0.0, 1.0);
    if (t >= 1) return (offset: 0, blur: finalBlur);
    final common = curve.transform(t);
    final delayed = curve.transform(((t - delay) / (1 - delay)).clamp(0, 1));
    final rawLag = distance * (common - delayed);
    // Smooth saturation avoids the velocity corner produced by a hard clamp.
    final lag = rawLag / math.sqrt(1 + rawLag * rawLag / 1764);
    final settle = LyricMotion.curve.transform(t);
    return (
      offset: (initialOffset * (1 - settle) + lag).clamp(-48.0, 48.0),
      blur: ui.lerpDouble(initialBlur, finalBlur, settle)!,
    );
  }
}

/// Only the bounded viewport band receives a live animation. The paragraph is
/// an AnimatedBuilder child and does not rebuild on these presentation frames.
class LyricFollowEffects extends StatelessWidget {
  const LyricFollowEffects({
    super.key,
    required this.clock,
    required this.transition,
    required this.blur,
    this.blurEnabled = true,
    this.blurAnimation,
    this.reading,
    required this.child,
  });

  final Animation<double> clock;
  final LyricFollowTransition? transition;
  final double blur;
  final bool blurEnabled;
  final Animation<double>? blurAnimation;
  final Animation<double>? reading;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          if (transition != null) clock,
          if (blurAnimation != null) blurAnimation!,
          if (reading != null) reading!,
        ]),
        child: child,
        builder: (context, child) {
          final sample = transition?.sample(clock.value);
          final sigma = blurEnabled
              ? (blurAnimation?.value ?? sample?.blur ?? blur) *
                  (reading?.value ?? 1)
              : 0.0;
          final offset = sample?.offset ?? 0;
          // Keep the subtree shape stable while crossing zero blur; otherwise
          // a focus handoff would discard the timed paragraph's glyph cache.
          return LyricWordFollowScope(
            // The row's transition record survives after its finite clock has
            // completed. Disconnect the per-word painter at that point: an
            // idle phonetic paragraph must no longer advertise continuous
            // repainting to the Windows raster cache while the sung primary
            // line keeps changing. The settled paint is identical to the
            // final follow frame, so this does not alter the visual handoff.
            follow: transition != null && clock.isAnimating && clock.value < 1
                ? LyricWordFollow(
                    clock, transition!.curve, transition!.distance)
                : null,
            child: Transform.translate(
              offset: Offset(0, offset),
              // Keep the cached paragraph, but sample its fractional position
              // inside the filter. ImageFiltered rounds the incoming scroll/lag
              // transform in the Windows raster cache: the slow spring return
              // otherwise stalls, then jumps by a physical pixel.
              child: LyricFractionalFilterScope(
                repaintToken: (
                  clock.value,
                  blurAnimation?.value,
                  reading?.value,
                  offset
                ),
                enabled: blurEnabled,
                dpr: View.of(context).devicePixelRatio,
                // Preserve the same clear-filter path during hover and after
                // follow cleanup; zero blur changes glyph sampling on Windows.
                sigma: math.max(.1, sigma),
                child: child!,
              ),
            ),
          );
        },
      );
}

/// One viewport mask with short edge ramps, disabled for manual reading and
/// reduced motion/high contrast. No timer or animation is owned by this mask.
class LyricViewportFade extends SingleChildRenderObjectWidget {
  const LyricViewportFade({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricViewportFade(enabled);

  @override
  void updateRenderObject(
          BuildContext context, covariant RenderProxyBox renderObject) =>
      (renderObject as _RenderLyricViewportFade).enabled = enabled;
}

class _RenderLyricViewportFade extends RenderProxyBox {
  _RenderLyricViewportFade(this._enabled);

  bool _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsPaint();
    markNeedsCompositingBitsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _enabled;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled || child == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final edge = math.min(24.0, size.height * .05) / math.max(1.0, size.height);
    final mask = layer is ShaderMaskLayer
        ? layer! as ShaderMaskLayer
        : ShaderMaskLayer();
    mask
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [
          Colors.transparent,
          Colors.white,
          Colors.white,
          Colors.transparent
        ],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}

/// A finite spring-shaped trajectory with one visible return. Both segments
/// meet at zero velocity, as does the endpoint. Unlike clipping an oscillator,
/// this has no flat cap or tiny secondary rebound during the final frames.
class _LyricSpringCurve extends Curve {
  const _LyricSpringCurve({required this.overshoot});

  final double overshoot;

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    const peak = .66;
    double smooth(double x) => x * x * x * (10 + x * (-15 + 6 * x));
    if (t < peak) {
      return (1 + overshoot) * scrollEase(t / peak);
    }
    return 1 + overshoot * (1 - smooth((t - peak) / (1 - peak)));
  }

  // The shared cubic accelerates naturally and reaches the peak at rest.
  double scrollEase(double t) => LyricMotion.scrollCurve.transform(t);
}

/// One stable animation state per lyric occurrence. A retargeted transition
/// begins at the currently painted values, not at the previous target values.
class LyricLineMotion extends ImplicitlyAnimatedWidget {
  const LyricLineMotion({
    super.key,
    required this.opacity,
    required this.scale,
    required this.activation,
    required this.alignment,
    required this.builder,
    required bool reducedMotion,
  }) : super(
          duration: reducedMotion ? Duration.zero : LyricMotion.lineDuration,
          curve: LyricMotion.curve,
        );

  final double opacity;
  final double scale;
  final double activation;
  final Alignment alignment;
  final Widget Function(BuildContext context, double activation) builder;

  @override
  AnimatedWidgetBaseState<LyricLineMotion> createState() =>
      _LyricLineMotionState();
}

class _LyricLineMotionState extends AnimatedWidgetBaseState<LyricLineMotion> {
  Tween<double>? _opacity;
  Tween<double>? _scale;
  Tween<double>? _activation;

  @override
  void didUpdateWidget(LyricLineMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration == Duration.zero) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _opacity = visitor(_opacity, widget.opacity,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _scale = visitor(_scale, widget.scale,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _activation = visitor(_activation, widget.activation,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: _opacity!.evaluate(animation).clamp(0.0, 1.0),
        alwaysIncludeSemantics: true,
        child: Transform.scale(
          scale: _scale!.evaluate(animation),
          alignment: widget.alignment,
          // Sample the cached text image instead of rerasterizing glyphs at
          // every intermediate scale. Reduced motion adds no sampling layer.
          filterQuality:
              widget.duration == Duration.zero ? null : FilterQuality.low,
          child: RepaintBoundary(
              child: widget.builder(context, _activation!.evaluate(animation))),
        ),
      );
}
