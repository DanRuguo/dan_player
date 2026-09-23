import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A single-line title that moves only when it cannot fit. Shaping is cached;
/// display frames repaint this small line without rebuilding its parent.
class OverflowMarqueeText extends StatefulWidget {
  const OverflowMarqueeText(this.text,
      {super.key,
      this.style,
      this.textAlign = TextAlign.start,
      this.hidden,
      this.pixelsPerSecond = 26,
      this.pauseDuration = const Duration(milliseconds: 1200)});

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final ValueListenable<bool>? hidden;
  final double pixelsPerSecond;
  final Duration pauseDuration;

  @override
  State<OverflowMarqueeText> createState() => _OverflowMarqueeTextState();
}

enum _Stage { leadingHold, outward, trailingHold, wrap }

class _OverflowMarqueeTextState extends State<OverflowMarqueeText>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _pose = ValueNotifier((offset: 0.0, wrapping: false));
  Ticker? _ticker;
  Timer? _hold;
  Duration _lastTick = Duration.zero;
  double _travelSeconds = 0;
  _Stage _stage = _Stage.leadingHold;
  ValueListenable<RenderingPreferences>? _preferences;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = true, _contextAllowsMotion = true, _overflow = false;
  TextPainter? _textPainter;
  TextStyle? _measuredStyle;
  TextScaler? _measuredScaler;
  Locale? _measuredLocale;
  TextDirection? _measuredDirection;
  String? _measuredText;
  double _width = 0;

  static const _gap = 36.0;
  double get _overflowDistance => math.max(0, _textPainter!.width - _width);
  double get _cycle => _textPainter!.width + _gap;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncClock);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncClock);
      _preferences = preferences..addListener(_syncClock);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _contextAllowsMotion = AppMotion.enabled(context, MotionKind.layout) &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncClock();
  }

  @override
  void didUpdateWidget(OverflowMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncClock);
      widget.hidden?.addListener(_syncClock);
    }
    _syncClock();
  }

  bool get _motionAllowed {
    final accessibility =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return _contextAllowsMotion &&
        (_preferences?.value.animations.allows(MotionKind.layout) ?? true) &&
        !accessibility.disableAnimations &&
        !accessibility.reduceMotion;
  }

  bool get _canRun =>
      _overflow &&
      _motionAllowed &&
      (_preferences?.value ?? const RenderingPreferences()).allowsVisualUpdates(
        lifecycle: _lifecycle,
        treeVisible: _treeVisible,
        nativeHidden: widget.hidden?.value ?? false,
      );

  void _stop() {
    _hold?.cancel();
    _hold = null;
    _ticker?.stop();
    _lastTick = Duration.zero;
  }

  void _reset() {
    _stop();
    _stage = _Stage.leadingHold;
    _travelSeconds = 0;
    _pose.value = (offset: 0, wrapping: false);
  }

  void _syncClock() {
    if (!_canRun) {
      _stop();
      return;
    }
    if (_stage == _Stage.leadingHold || _stage == _Stage.trailingHold) {
      // Endpoint rests need no frames. Resuming a hidden rest simply grants
      // another full reading pause rather than skipping text while invisible.
      _hold ??= Timer(widget.pauseDuration, () {
        _hold = null;
        if (!mounted || !_canRun) return;
        _stage = _stage == _Stage.leadingHold ? _Stage.outward : _Stage.wrap;
        _travelSeconds = 0;
        _syncClock();
      });
    } else {
      // The application binding applies the user's existing frame-rate cap.
      // No parallel periodic timer produces requests outside that policy.
      _ticker ??= createTicker(_tick);
      if (!_ticker!.isActive) {
        _lastTick = Duration.zero;
        _ticker!.start();
      }
    }
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    // A stalled/occluded frame must not fast-forward an unread word.
    _travelSeconds += delta.inMicroseconds.clamp(0, 100000) / 1000000;
    final wrapping = _stage == _Stage.wrap;
    final distance = wrapping ? _cycle - _overflowDistance : _overflowDistance;
    final speed = widget.pixelsPerSecond.isFinite && widget.pixelsPerSecond > 0
        ? widget.pixelsPerSecond.clamp(8.0, 80.0)
        : 26.0;
    final ramp = math.min(.25, distance / speed);
    final duration = distance / speed + ramp;
    final t = math.min(_travelSeconds, duration);
    final traveled = t < ramp
        ? speed * t * t / (2 * ramp)
        : t > duration - ramp
            ? distance - speed * math.pow(duration - t, 2) / (2 * ramp)
            : speed * (t - ramp / 2);
    _pose.value = (
      offset: (wrapping ? _overflowDistance : 0) + traveled,
      wrapping: wrapping
    );
    if (_travelSeconds >= duration) {
      _ticker!.stop();
      _lastTick = Duration.zero;
      _travelSeconds = 0;
      if (wrapping) {
        _pose.value = (offset: 0, wrapping: false);
        _stage = _Stage.leadingHold;
      } else {
        _stage = _Stage.trailingHold;
      }
      _syncClock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncClock();
  }

  @override
  void didChangeAccessibilityFeatures() {
    _syncClock();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final text = widget.text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return LayoutBuilder(builder: (context, constraints) {
      final changed = _measuredText != text ||
          _measuredStyle != style ||
          _measuredScaler != scaler ||
          _measuredDirection != direction ||
          _measuredLocale != locale ||
          _width != constraints.maxWidth;
      if (changed) {
        _reset();
        _textPainter?.dispose();
        _measuredText = text;
        _measuredStyle = style;
        _measuredScaler = scaler;
        _measuredDirection = direction;
        _measuredLocale = locale;
        _width = constraints.maxWidth;
        _textPainter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            locale: locale,
            maxLines: 1)
          ..layout();
        _overflow =
            _width.isFinite && _width > 0 && _textPainter!.width > _width + .5;
      }
      if (!_overflow || !_motionAllowed) {
        _reset();
        return Text(text,
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis);
      }
      _syncClock();
      return Semantics(
          label: widget.text,
          textDirection: direction,
          child: RepaintBoundary(
              child: CustomPaint(
                  size: Size(_width, _textPainter!.height),
                  painter: _MarqueePainter(
                      _textPainter!, _pose, _width, direction, _gap))));
    });
  }

  @override
  void dispose() {
    _stop();
    _ticker?.dispose();
    _pose.dispose();
    _textPainter?.dispose();
    widget.hidden?.removeListener(_syncClock);
    _preferences?.removeListener(_syncClock);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _MarqueePainter extends CustomPainter {
  _MarqueePainter(this.text, this.pose, this.width, this.direction, this.gap)
      : super(repaint: pose);
  final TextPainter text;
  final ValueListenable<({double offset, bool wrapping})> pose;
  final double width, gap;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final value = pose.value;
    final overflow = text.width - width;
    final cycle = text.width + gap;
    final extent = math.min(20.0, width / 5);
    final leading = (value.wrapping ? cycle - value.offset : value.offset)
        .clamp(0.0, extent);
    final trailing =
        (value.wrapping ? value.offset - overflow : overflow - value.offset)
            .clamp(0.0, extent);
    final left = direction == TextDirection.ltr ? leading : trailing;
    final right = direction == TextDirection.ltr ? trailing : leading;
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.saveLayer(bounds, Paint());
    final x = direction == TextDirection.ltr
        ? -value.offset
        : width - text.width + value.offset;
    text.paint(canvas, Offset(x, 0));
    if (value.wrapping) {
      text.paint(canvas,
          Offset(x + (direction == TextDirection.ltr ? cycle : -cycle), 0));
    }
    canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = LinearGradient(colors: [
            left > 0 ? Colors.transparent : Colors.white,
            Colors.white,
            Colors.white,
            right > 0 ? Colors.transparent : Colors.white,
          ], stops: [
            0,
            left / width,
            1 - right / width,
            1,
          ]).createShader(bounds));
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarqueePainter oldDelegate) =>
      !identical(text, oldDelegate.text) ||
      !identical(pose, oldDelegate.pose) ||
      width != oldDelegate.width ||
      direction != oldDelegate.direction ||
      gap != oldDelegate.gap;
}
