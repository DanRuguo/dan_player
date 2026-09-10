import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'dart:async';

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A rounded vertical handle keeps the timeline light without using a dot.
/// Its visual size changes; Slider retains its full 48px interaction surface.
class DetailProgressHandleShape extends SliderComponentShape {
  const DetailProgressHandleShape({required this.emphasis});
  final double emphasis;

  double get width => 4 + 2 * emphasis;
  double get height => 18 + 3 * emphasis;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(48, 48);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = Color.lerp(sliderTheme.disabledThumbColor,
        sliderTheme.thumbColor, enableAnimation.value)!;
    context.canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: width, height: height),
            const Radius.circular(3)),
        Paint()..color = color);
  }
}

/// A single visible-only position subscription. Short finite interpolation
/// connects real samples without extrapolation or a separate playback clock.
class DetailProgressSlider extends StatefulWidget {
  const DetailProgressSlider({
    super.key,
    required this.positions,
    required this.readPosition,
    required this.duration,
    required this.trackIdentity,
    required this.onSeek,
    this.enabled = true,
    this.hidden,
  });

  final Stream<double> positions;
  final double Function() readPosition;
  final double duration;
  final Object? trackIdentity;
  final ValueChanged<double> onSeek;
  final bool enabled;
  final ValueListenable<bool>? hidden;

  @override
  State<DetailProgressSlider> createState() => _DetailProgressSliderState();
}

class _DetailProgressSliderState extends State<DetailProgressSlider>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _smoothing;
  late final ValueNotifier<double> _display;
  StreamSubscription<double>? _subscription;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = false;
  bool _mediaReduced = false;
  bool _active = false;
  bool _reduced = false;
  bool _hovered = false;
  bool _focused = false;
  bool _dragging = false;
  Object? _dragIdentity;
  double _from = 0;
  double _target = 0;
  int _generation = 0;

  double get _length =>
      widget.duration.isFinite && widget.duration > 0 ? widget.duration : 0;
  bool get _enabled => widget.enabled && _length > 0;
  double _safe(double value) =>
      value.isFinite ? value.clamp(0.0, _length).toDouble() : 0;

  static String _time(double seconds) {
    final value = seconds.floor();
    final hours = value ~/ 3600;
    final minutes = (value ~/ 60) % 60;
    final remainder = (value % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$remainder'
        : '$minutes:$remainder';
  }

  @override
  void initState() {
    super.initState();
    _display = ValueNotifier(_safe(widget.readPosition()));
    _target = _display.value;
    _smoothing =
        AnimationController(vsync: this, duration: AppMotion.followSample)
          ..addListener(() {
            _display.value =
                _safe(_from + (_target - _from) * _smoothing.value);
          });
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _mediaReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncActivity();
  }

  @override
  void didUpdateWidget(covariant DetailProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
    }
    if (oldWidget.trackIdentity != widget.trackIdentity || !_enabled) {
      _dragging = false;
      _dragIdentity = null;
      _receive(widget.readPosition(), immediate: true);
    } else if (oldWidget.duration != widget.duration && !_dragging) {
      _receive(widget.readPosition(), immediate: true);
    }
    if (!identical(oldWidget.positions, widget.positions)) {
      _detach();
      _active = false;
    }
    _syncActivity();
  }

  void _detach() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _smoothing.stop();
  }

  void _syncActivity() {
    if (!mounted) return;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    _reduced =
        _mediaReduced || features.disableAnimations || features.reduceMotion;
    final active = const RenderingPreferences().allowsVisualUpdates(
      lifecycle: _lifecycle,
      treeVisible: _treeVisible,
      nativeHidden: widget.hidden?.value ?? false,
    );
    if (active != _active) {
      _active = active;
      _detach();
      if (active) {
        final generation = _generation;
        _receive(widget.readPosition(), immediate: true);
        _subscription = widget.positions.listen((position) {
          if (mounted && _active && generation == _generation) {
            _receive(position);
          }
        }, onError: (Object _, StackTrace __) {
          if (mounted && _active && generation == _generation) {
            _smoothing.stop();
          }
        });
      } else {
        _dragging = false;
        _dragIdentity = null;
      }
      setState(() {});
    }
    if (_reduced && _smoothing.isAnimating) {
      _smoothing.stop();
      _display.value = _target;
    }
  }

  void _receive(double position, {bool immediate = false}) {
    if (_dragging) return;
    final target = _safe(position);
    final delta = target - _display.value;
    if (target == _target && !immediate) return;
    _smoothing.stop();
    _from = _display.value;
    _target = target;
    // Seeks, loop jumps and track changes must never slide through old time.
    if (immediate || _reduced || !_active || delta <= 0 || delta > .75) {
      _display.value = target;
    } else {
      _smoothing.forward(from: 0);
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    _syncActivity();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncActivity();
  }

  void _begin(double value) {
    _smoothing.stop();
    _dragIdentity = widget.trackIdentity;
    setState(() => _dragging = true);
    _display.value = _safe(value);
  }

  void _finish(double value) {
    final canSeek =
        _dragging && _enabled && _dragIdentity == widget.trackIdentity;
    setState(() => _dragging = false);
    _dragIdentity = null;
    if (canSeek) widget.onSeek(_safe(value));
    _receive(widget.readPosition(), immediate: true);
  }

  @override
  void dispose() {
    _detach();
    WidgetsBinding.instance.removeObserver(this);
    widget.hidden?.removeListener(_syncActivity);
    _smoothing.dispose();
    _display.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final emphasis = !_enabled
        ? 0.0
        : _dragging
            ? 2.0
            : (_hovered || _focused)
                ? 1.0
                : 0.0;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final motion = _active && !_reduced;
    return RepaintBoundary(
      child: Column(children: [
        MouseRegion(
          cursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Focus(
            onFocusChange: (focused) => setState(() => _focused = focused),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: emphasis),
              duration: motion ? AppMotion.quick : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, emphasis, child) => SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4 + emphasis,
                  trackShape: const RoundedRectSliderTrackShape(),
                  thumbShape: DetailProgressHandleShape(emphasis: emphasis),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: scheme.primary,
                  inactiveTrackColor: highContrast
                      ? scheme.outline
                      : scheme.primary.withValues(alpha: .18),
                  thumbColor: scheme.primary,
                  valueIndicatorColor: scheme.primaryContainer,
                  valueIndicatorTextStyle:
                      TextStyle(color: scheme.onPrimaryContainer),
                  showValueIndicator: ShowValueIndicator.onDrag,
                ),
                child: child!,
              ),
              child: ValueListenableBuilder<double>(
                valueListenable: _display,
                builder: (context, position, _) => Semantics(
                  label: ui('播放进度'),
                  child: Slider(
                    key: const ValueKey('detail-progress-slider'),
                    min: 0,
                    max: _length > 0 ? _length : 1,
                    value: _safe(position),
                    label: _time(position),
                    semanticFormatterCallback: _time,
                    onChangeStart: _enabled ? _begin : null,
                    onChanged: _enabled
                        ? (value) {
                            if (_dragging) _display.value = _safe(value);
                          }
                        : null,
                    onChangeEnd: _enabled ? _finish : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()]),
            child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                spacing: 16,
                overflowSpacing: 2,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: _display,
                    builder: (context, position, _) => Text(_time(position),
                        key: const ValueKey('detail-progress-elapsed'),
                        style: _dragging
                            ? TextStyle(color: scheme.primary)
                            : null),
                  ),
                  Text(_time(_length)),
                ]),
          ),
        ),
      ]),
    );
  }
}
