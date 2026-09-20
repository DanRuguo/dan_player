import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:dan_player/component/app_motion.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
  static const focusedFontScale = 1.24;
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
          ? _LyricSpringCurve(maxOvershoot: 8 / math.max(1, distance.abs()))
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
        1 => .80,
        2 => .78,
        _ => .76,
      };

  /// One shared pose for all three waiting dots, sampled from media time.
  /// Brightness advances per dot; geometry breathes and exits as a group.
  static ({double scale, double opacity, double progress}) interludePose(
      Duration elapsed, Duration length,
      {bool reduced = false}) {
    if (reduced) return (scale: 1, opacity: 1, progress: 1);
    final duration = length.inMilliseconds.toDouble();
    final time = elapsed.inMilliseconds.toDouble();
    if (duration <= 0 || time <= 0 || time >= duration) {
      return (scale: 0, opacity: 0, progress: time > 0 ? 1 : 0);
    }
    final remaining = duration - time;
    final cycle = duration / math.max(1, (duration / 4500).ceil());
    final breathing = 1 - .05 * math.cos(time / cycle * 2 * math.pi);
    final entry = Curves.easeOutCubic.transform((time / 2000).clamp(0.0, 1.0));
    final end = ((750 - remaining) / 750).clamp(0.0, 1.0);
    final exit = end < .35
        ? 1 + .04 * math.sin(end / .35 * math.pi / 2)
        : 1.04 * (1 - Curves.easeInOutCubic.transform((end - .35) / .65));
    return (
      scale: breathing * entry * exit,
      opacity: ((time - 500) / 500).clamp(0.0, 1.0) *
          (remaining / 375).clamp(0.0, 1.0),
      progress: (time / math.max(1, duration - 750)).clamp(0.0, 1.0),
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
    final lag = rawLag / math.sqrt(1 + rawLag * rawLag / 900);
    final settle = LyricMotion.curve.transform(t);
    return (
      offset: (initialOffset * (1 - settle) + lag).clamp(-36.0, 36.0),
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
    this.reading,
    required this.child,
  });

  final Animation<double> clock;
  final LyricFollowTransition? transition;
  final double blur;
  final bool blurEnabled;
  final Animation<double>? reading;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          if (transition != null) clock,
          if (reading != null) reading!,
        ]),
        child: child,
        builder: (context, child) {
          final sample = transition?.sample(clock.value);
          final sigma = blurEnabled
              ? (sample?.blur ?? blur) * (reading?.value ?? 1)
              : 0.0;
          final offset = sample?.offset ?? 0;
          // Keep the subtree shape stable while crossing zero blur; otherwise
          // a focus handoff would discard the timed paragraph's glyph cache.
          return Transform.translate(
            offset: Offset(0, offset),
            child: ImageFiltered(
              // Keep the context filter path during hover reading. A zero blur
              // is optimized away below Flutter; after cache warm-up that path
              // can shift scaled glyphs by one pixel on Windows. Sigma .1 is
              // visually clear but retains stable sampling. Reduced motion /
              // disabled blur still bypass the filter entirely.
              enabled: blurEnabled && (blur > 0 || transition != null),
              imageFilter: ui.ImageFilter.blur(
                  sigmaX: math.max(.1, sigma), sigmaY: math.max(.1, sigma)),
              child: child,
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

/// An independently implemented damped spring. Only scroll/paint transforms
/// use this curve; paragraph size, opacity and word timing never overshoot.
class _LyricSpringCurve extends Curve {
  const _LyricSpringCurve({required this.maxOvershoot});

  final double maxOvershoot;

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    double value(double time) =>
        1 -
        math.exp(-10 * time) *
            (math.cos(7 * time) + 10 / 7 * math.sin(7 * time));
    return (value(t) / value(1)).clamp(0.0, 1 + maxOvershoot);
  }
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
          child: RepaintBoundary(
              child: widget.builder(context, _activation!.evaluate(animation))),
        ),
      );
}
