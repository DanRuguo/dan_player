export 'package:desktop_lyric/lyric_content_reveal.dart';
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
    this.samplingEnabled,
    this.blurAnimation,
    this.reading,
    required this.child,
  });

  final Animation<double> clock;
  final LyricFollowTransition? transition;
  final double blur;
  final bool blurEnabled;

  /// Keep the paragraph's glyph sampling when reading turns blur off.
  final bool? samplingEnabled;
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
              // Keep fractional glyph sampling at zero blur too. Switching to
              // direct text paint on the final frame shifts glyph ink by up to
              // half a physical pixel; the leaf skips only its Gaussian pass.
              child: LyricFractionalFilterScope(
                repaintToken: (
                  clock.value,
                  blurAnimation?.value,
                  reading?.value,
                  offset
                ),
                enabled: samplingEnabled ?? blurEnabled,
                dpr: View.of(context).devicePixelRatio,
                sigma: sigma,
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
    this.retainLayer = false,
    required super.child,
  });

  final bool enabled;

  /// An opaque mask preserves the same compositing path while fading is off.
  final bool retainLayer;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricViewportFade(enabled, retainLayer);

  @override
  void updateRenderObject(
          BuildContext context, covariant RenderProxyBox renderObject) =>
      (renderObject as _RenderLyricViewportFade)
        ..enabled = enabled
        ..retainLayer = retainLayer;
}

class _RenderLyricViewportFade extends RenderProxyBox {
  _RenderLyricViewportFade(this._enabled, this._retainLayer);

  bool _enabled;
  bool _retainLayer;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsPaint();
    markNeedsCompositingBitsUpdate();
  }

  set retainLayer(bool value) {
    if (_retainLayer == value) return;
    _retainLayer = value;
    markNeedsPaint();
    markNeedsCompositingBitsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing =>
      child != null && (_enabled || _retainLayer);

  @override
  void paint(PaintingContext context, Offset offset) {
    if ((!_enabled && !_retainLayer) || child == null) {
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
        colors: _enabled
            ? const [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent
              ]
            : const [Colors.white, Colors.white, Colors.white, Colors.white],
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
typedef LyricTextPresentation = ({
  double fontSize,
  double translationFontSize,
  Alignment alignment,
});

/// The font endpoints remain fixed while a line changes size. Paragraphs can
/// keep both line-break layouts alive and blend them instead of re-shaping text
/// on every tick (which makes a one-line/two-line boundary jump in one frame).
typedef LyricFontTransition = ({
  double fromFontSize,
  double toFontSize,
  double fromTranslationFontSize,
  double toTranslationFontSize,
  double progress,
  double visualProgress,
  double fromLetterSpacing,
  double toLetterSpacing,
});

/// Reading anchors use the line's current paint geometry during parent layout.
/// Plain values avoid accessing a descendant Transform's size in that phase.
abstract interface class LyricLineReadingGeometry {
  double readingPaintY(double layoutY, double lineHeight);
}

typedef LyricSpacingRestoration = ({int revision, double spacing});

class _VisibleSpacingSnapshot {
  _VisibleSpacingSnapshot(Object source, this.identity, this.spacing)
      : source = WeakReference(source);
  final WeakReference<Object> source;
  final Object identity;
  final double spacing;
}

// One scalar pose survives the now-playing route's maintainState:false. The
// lyric document remains owned by its service; no glyphs, rows or media clock
// are retained here. Natural line advances can use the current line's text.
_VisibleSpacingSnapshot? _visibleSpacingSnapshot;
int _spacingRestorationRevision = 0;

class LyricSpacingRestore extends StatefulWidget {
  const LyricSpacingRestore(
      {super.key,
      required this.source,
      required this.identity,
      required this.spacing,
      required this.visible,
      required this.enabled,
      required this.currentLine,
      required this.builder});

  final Object source;
  final Object identity;
  final double spacing;
  final bool visible;
  final bool enabled;
  final bool currentLine;
  final Widget Function(BuildContext, LyricSpacingRestoration?) builder;

  @override
  State<LyricSpacingRestore> createState() => _LyricSpacingRestoreState();
}

class _LyricSpacingRestoreState extends State<LyricSpacingRestore> {
  bool _wasVisible = false;
  Object? _identity;
  double? _spacing;
  Object? _source;
  LyricSpacingRestoration? _restoration;
  ModalRoute<dynamic>? _route;
  final _routeAnimations = <Animation<double>>[];

  void _routeStatusChanged(AnimationStatus status) {
    if (mounted) setState(() {});
  }

  void _syncRouteListeners() {
    for (final animation in _routeAnimations) {
      animation.removeStatusListener(_routeStatusChanged);
    }
    _routeAnimations.clear();
    if (!widget.currentLine) return;
    for (final animation in [_route?.animation, _route?.secondaryAnimation]) {
      if (animation == null) continue;
      animation.addStatusListener(_routeStatusChanged);
      _routeAnimations.add(animation);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(route, _route)) return;
    _route = route;
    _syncRouteListeners();
  }

  @override
  void didUpdateWidget(LyricSpacingRestore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLine != widget.currentLine) _syncRouteListeners();
  }

  @override
  void dispose() {
    for (final animation in _routeAnimations) {
      animation.removeStatusListener(_routeStatusChanged);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Overlay makes the row tickable at the start of a covering route's exit.
    // Wait for that finite route handoff to expose the paragraph before using
    // the existing finite lyric transition. Popup routes do not drive the
    // PageRoute's secondary transition, and ordinary lyric/media motion keeps
    // its existing visibility contract.
    final routeReady = (_route?.animation == null ||
            _route!.animation!.status == AnimationStatus.completed) &&
        (_route?.secondaryAnimation == null ||
            _route!.secondaryAnimation!.status == AnimationStatus.dismissed);
    final visible =
        widget.visible && TickerMode.valuesOf(context).enabled && routeReady;
    final previous = _visibleSpacingSnapshot;
    final sameSource = identical(previous?.source.target, widget.source);
    if (!widget.enabled ||
        (sameSource && previous!.identity != widget.identity)) {
      if (sameSource) _visibleSpacingSnapshot = null;
      _restoration = null;
    }
    if (visible && widget.enabled && widget.currentLine) {
      if (!_wasVisible &&
          sameSource &&
          previous!.identity == widget.identity &&
          previous.spacing != widget.spacing) {
        _restoration = (
          revision: ++_spacingRestorationRevision,
          spacing: previous.spacing,
        );
      } else if (!identical(_source, widget.source) ||
          _identity != widget.identity ||
          _spacing != widget.spacing) {
        _restoration = null;
      }
      _visibleSpacingSnapshot = _VisibleSpacingSnapshot(
          widget.source, widget.identity, widget.spacing);
    } else {
      _restoration = null;
    }
    _wasVisible = visible;
    _identity = widget.identity;
    _spacing = widget.spacing;
    _source = widget.source;
    return widget.builder(context, _restoration);
  }
}

class LyricLineMotion extends ImplicitlyAnimatedWidget {
  const LyricLineMotion({
    super.key,
    super.onEnd,
    required this.opacity,
    required this.scale,
    required this.activation,
    required this.alignment,
    required this.presentation,
    this.directFontSize = false,
    this.letterSpacing = 0,
    this.animateLetterSpacing = true,
    this.restoredLetterSpacing,
    required this.builder,
    required bool reducedMotion,
  }) : super(
          duration: restoredLetterSpacing != null && animateLetterSpacing
              ? LyricMotion.lineDuration
              : reducedMotion
                  ? Duration.zero
                  : LyricMotion.lineDuration,
          curve: LyricMotion.curve,
        );

  final double opacity;
  final double scale;
  final double activation;
  final Alignment alignment;
  final LyricTextPresentation presentation;
  final bool directFontSize;
  final double letterSpacing;
  final bool animateLetterSpacing;
  final LyricSpacingRestoration? restoredLetterSpacing;
  final Widget Function(
      BuildContext context,
      double activation,
      LyricTextPresentation presentation,
      LyricFontTransition fontTransition) builder;

  @override
  AnimatedWidgetBaseState<LyricLineMotion> createState() =>
      _LyricLineMotionState();
}

// The visible geometry and the value used by ImplicitlyAnimatedWidget when a
// transition is interrupted must use the same interpolation. Settling before
// the final tick keeps the retained image filter from shifting its last pixel.
double _settledGeometryProgress(double t) => (t / .995).clamp(0.0, 1.0);

class _SettledScaleTween extends Tween<double> {
  _SettledScaleTween({super.begin});

  @override
  double lerp(double t) => super.lerp(_settledGeometryProgress(t));
}

class _SettledAlignmentTween extends AlignmentTween {
  _SettledAlignmentTween({super.begin});

  @override
  Alignment lerp(double t) => super.lerp(_settledGeometryProgress(t));
}

class _LyricLineMotionState extends AnimatedWidgetBaseState<LyricLineMotion>
    implements LyricLineReadingGeometry {
  Tween<double>? _opacity;
  Tween<double>? _scale;
  Tween<double>? _activation;
  Tween<double>? _fontSize;
  Tween<double>? _translationFontSize;
  Tween<double>? _letterSpacing;
  AlignmentTween? _alignment;

  void _restoreSpacing() {
    final restoration = widget.restoredLetterSpacing;
    if (restoration == null || !widget.animateLetterSpacing) return;
    // Route restoration snaps every other presentation value as before. Only
    // the settings' spacing gets a fresh, finite visible handoff.
    _opacity = Tween(begin: widget.opacity, end: widget.opacity);
    _scale = _SettledScaleTween(begin: widget.scale)..end = widget.scale;
    _activation = Tween(begin: widget.activation, end: widget.activation);
    _fontSize = Tween(
        begin: widget.presentation.fontSize, end: widget.presentation.fontSize);
    _translationFontSize = Tween(
        begin: widget.presentation.translationFontSize,
        end: widget.presentation.translationFontSize);
    _alignment = AlignmentTween(begin: widget.alignment, end: widget.alignment);
    _letterSpacing =
        Tween(begin: restoration.spacing, end: widget.letterSpacing);
    controller
      ..duration = LyricMotion.lineDuration
      ..forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _restoreSpacing();
  }

  @override
  double readingPaintY(double layoutY, double lineHeight) {
    final pivot = (_alignment!.evaluate(animation).y + 1) * lineHeight / 2;
    return pivot + (layoutY - pivot) * _scale!.evaluate(animation);
  }

  @override
  void didUpdateWidget(LyricLineMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final restoring = widget.restoredLetterSpacing != null &&
        oldWidget.restoredLetterSpacing != widget.restoredLetterSpacing &&
        widget.animateLetterSpacing;
    if (restoring) {
      _restoreSpacing();
      return;
    }
    if (oldWidget.letterSpacing != widget.letterSpacing &&
        widget.animateLetterSpacing &&
        widget.duration != Duration.zero &&
        oldWidget.presentation == widget.presentation &&
        oldWidget.opacity == widget.opacity &&
        oldWidget.scale == widget.scale &&
        oldWidget.alignment == widget.alignment &&
        oldWidget.activation == widget.activation) {
      // The base state has already started its simulation with lineDuration.
      // Restart only this settings handoff with the finite layout duration.
      controller
        ..duration = LyricMotion.lineDuration
        ..forward(from: 0);
    }
    final onlySpacing = _opacity?.begin == _opacity?.end &&
        _scale?.begin == _scale?.end &&
        _activation?.begin == _activation?.end &&
        _fontSize?.begin == _fontSize?.end &&
        _translationFontSize?.begin == _translationFontSize?.end &&
        _alignment?.begin == _alignment?.end;
    if ((widget.duration == Duration.zero &&
            widget.restoredLetterSpacing == null) ||
        (!widget.animateLetterSpacing && onlySpacing)) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _opacity = visitor(_opacity, widget.opacity,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _scale = visitor(_scale, widget.scale,
            (value) => _SettledScaleTween(begin: value as double))
        as Tween<double>?;
    _activation = visitor(_activation, widget.activation,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _fontSize = visitor(_fontSize, widget.presentation.fontSize,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    _translationFontSize = visitor(
        _translationFontSize,
        widget.presentation.translationFontSize,
        (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    if (!widget.animateLetterSpacing) {
      _letterSpacing =
          Tween<double>(begin: widget.letterSpacing, end: widget.letterSpacing);
    } else {
      _letterSpacing = visitor(_letterSpacing, widget.letterSpacing,
          (value) => Tween<double>(begin: value as double)) as Tween<double>?;
    }
    _alignment = visitor(_alignment, widget.alignment,
            (value) => _SettledAlignmentTween(begin: value as Alignment))
        as AlignmentTween?;
  }

  @override
  Widget build(BuildContext context) {
    // The size menu lays out its target paragraph immediately. Its separate
    // visual progress only scales/fades those already shaped target glyphs.
    final fontProgress = widget.directFontSize ? 1.0 : animation.value;
    final fontSize = _fontSize!.transform(fontProgress);
    final translationFontSize = _translationFontSize!.transform(fontProgress);
    final alignment = _alignment!.evaluate(animation);
    final hasGeometryMotion =
        _scale!.begin != _scale!.end || _alignment!.begin != _alignment!.end;
    return Opacity(
      opacity: _opacity!.evaluate(animation).clamp(0.0, 1.0),
      alwaysIncludeSemantics: true,
      child: Transform.scale(
        scale: _scale!.evaluate(animation),
        alignment: alignment,
        filterQuality: widget.duration == Duration.zero || !hasGeometryMotion
            ? null
            : FilterQuality.low,
        child: RepaintBoundary(
            child: widget.builder(
          context,
          _activation!.evaluate(animation),
          (
            fontSize: fontSize,
            translationFontSize: translationFontSize,
            alignment: alignment,
          ),
          (
            fromFontSize: _fontSize!.begin!,
            toFontSize: _fontSize!.end!,
            fromTranslationFontSize: _translationFontSize!.begin!,
            toTranslationFontSize: _translationFontSize!.end!,
            progress: fontProgress,
            visualProgress: animation.value,
            fromLetterSpacing: _letterSpacing!.begin!,
            toLetterSpacing: _letterSpacing!.end!,
          ),
        )),
      ),
    );
  }
}
