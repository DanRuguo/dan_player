import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion local to lyric surfaces. Playback time remains the sole clock for
/// word highlighting; these durations only describe presentation transitions.
abstract final class LyricMotion {
  static const lineDuration = Duration(milliseconds: 460);
  static const scrollDuration = Duration(milliseconds: 620);
  static const seekScrollDuration = Duration(milliseconds: 320);
  static const springScrollDuration = Duration(milliseconds: 720);
  static const manualScrollGrace = Duration(seconds: 4);
  static const curve = Cubic(0.22, 0.0, 0.16, 1.0);
  // Start travelling promptly, then spend the final part settling at the line.
  // Keep this separate from the shared line/title fade curve: a scroll must
  // decelerate, remain monotonic and never spring past its target.
  static const scrollCurve = Cubic(0.16, 1.0, 0.30, 1.0);
  static const focusedFontScale = 1.12;
  static const focusedFontWeight = FontWeight.w800;

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
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  static double opacityForDistance(int distance) => switch (distance.abs()) {
        0 => 1,
        1 => .46,
        2 => .30,
        3 => .22,
        _ => .16,
      };

  // The active line is laid out at its final size; transforms never enlarge it
  // beyond that box or change wrapping while the focus moves between lines.
  static double scaleForDistance(int distance) => switch (distance.abs()) {
        0 => 1,
        1 => .88,
        2 => .86,
        _ => .84,
      };

  static double progress(Duration position, Duration start, Duration length) {
    if (length <= Duration.zero) return position >= start ? 1 : 0;
    return ((position - start).inMicroseconds / length.inMicroseconds)
        .clamp(0.0, 1.0);
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
          child: widget.builder(context, _activation!.evaluate(animation)),
        ),
      );
}
