import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:dan_player/page/now_playing_page/component/detail_position_follow.dart';
import 'dart:async';

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A rounded vertical handle keeps the timeline light without using a dot.
/// Its visual size changes; Slider retains its full 48px interaction surface.
class DetailProgressHandleShape extends SliderComponentShape {
  const DetailProgressHandleShape({required this.emphasis, this.resolveHeight});
  final double emphasis;
  final double Function(double target)? resolveHeight;

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
    final track = sliderTheme.trackShape;
    final targetHeight = track is DetailWaveformTrackShape
        ? track.handleHeight(emphasis) ?? height
        : height;
    final paintedHeight = resolveHeight?.call(targetHeight) ?? targetHeight;
    context.canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: center, width: width, height: paintedHeight),
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
    this.waveform,
    this.waveformTooltip,
    this.waveformDensity = WaveformBarDensity.automatic,
  });

  final Stream<double> positions;
  final double Function() readPosition;
  final double duration;
  final Object? trackIdentity;
  final ValueChanged<double> onSeek;
  final bool enabled;
  final ValueListenable<bool>? hidden;

  /// Decoded 0..1 peaks, bounded to 512 points by the track shape.
  final List<double>? waveform;

  /// Availability or source information, shown without changing seek labels.
  final String? waveformTooltip;
  final WaveformBarDensity waveformDensity;

  @override
  State<DetailProgressSlider> createState() => _DetailProgressSliderState();
}

class _DetailProgressSliderState extends State<DetailProgressSlider>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _smoothing;
  DetailPositionFollow? _follow;
  late final AnimationController _waveformTransition;
  late final AnimationController _handleTransition;
  double _handleFrom = 18, _handleTo = 18, _handlePaintedHeight = 18;
  bool _handleJumpPending = false, _handleTweenActive = false;
  int _handleGeneration = 0;
  double? _handleMorphAnchor, _handleMorphCorrection;
  WaveformTrackVisual _waveformFrom = const WaveformTrackVisual.line();
  WaveformTrackVisual _waveformTo = const WaveformTrackVisual.line();
  WaveformTrackSource? _waveformTarget;
  final _waveformSources = <WaveformBarDensity, WaveformTrackSource>{};
  List<double>? _rawWaveform;
  List<double> _waveformPeaks = const [];
  bool _waveformInitialized = false;
  late final ValueNotifier<double> _display;
  final _elapsed = ValueNotifier<int>(0);
  StreamSubscription<double>? _subscription;
  AppLifecycleState? _lifecycle;
  ValueListenable<RenderingPreferences>? _preferences;
  bool _treeVisible = false;
  bool _mediaReduced = false;
  bool _active = false;
  bool _reduced = false;
  bool _hovered = false;
  bool _focused = false;
  bool _dragging = false;
  Object? _dragIdentity;
  int? _pointer;
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
    _elapsed.value = _display.value.floor();
    _display.addListener(() => _elapsed.value = _display.value.floor());
    _target = _display.value;
    _smoothing = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        _display.value = _safe(_smoothing.value);
      });
    _waveformTransition = AnimationController(
        vsync: this, value: 1, duration: const Duration(milliseconds: 240))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _waveformFrom = _waveformTo;
      });
    _handleTransition = AnimationController(
        vsync: this, value: 1, duration: const Duration(milliseconds: 80))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _handleTweenActive = false;
      });
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncActivity);
      _preferences = preferences..addListener(_syncActivity);
    }
    // Popup routes leave this surface visible. Overlay already disables
    // TickerMode when an opaque route covers it; isCurrent would also stop
    // playback visuals behind ordinary dialogs and popup menus.
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _mediaReduced = !AppMotion.enabled(context, MotionKind.feedback);
    _syncActivity();
    if (!_waveformInitialized) {
      _waveformInitialized = true;
      _updateWaveform(clearPrevious: true);
    }
  }

  @override
  void didUpdateWidget(covariant DetailProgressSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
    }
    final sourceChanged = !identical(oldWidget.positions, widget.positions);
    if (oldWidget.trackIdentity != widget.trackIdentity ||
        sourceChanged ||
        !_enabled) {
      _dragging = false;
      _dragIdentity = null;
      _receive(widget.readPosition(), immediate: true);
    } else if (oldWidget.duration != widget.duration && !_dragging) {
      _receive(widget.readPosition(), immediate: true);
    }
    if (sourceChanged) {
      _detach();
      _active = false;
    }
    _syncActivity();
    _updateWaveform(
        clearPrevious: oldWidget.trackIdentity != widget.trackIdentity);
  }

  WaveformTrackVisual get _waveformVisual => WaveformTrackVisual.interpolate(
      _waveformFrom,
      _waveformTo,
      Curves.easeInOutCubic.transform(_waveformTransition.value));

  void _updateWaveform({bool clearPrevious = false}) {
    final raw = widget.waveform;
    if (clearPrevious ||
        (!identical(raw, _rawWaveform) && !listEquals(raw, _rawWaveform))) {
      _waveformPeaks = boundedWaveformPeaks(raw ?? const []);
      _waveformSources.clear();
    }
    _rawWaveform = raw;
    final target = _waveformPeaks.isEmpty
        ? null
        : _waveformSources.putIfAbsent(widget.waveformDensity,
            () => WaveformTrackSource(_waveformPeaks, widget.waveformDensity));
    if (!clearPrevious && identical(target, _waveformTarget)) return;
    _handleGeneration++;
    _handleMorphAnchor =
        !clearPrevious && _handleTweenActive ? _handlePaintedHeight : null;
    _handleMorphCorrection = null;
    _handleTransition.stop();
    _handleJumpPending = false;
    _handleTweenActive = false;
    if (clearPrevious) _handlePaintedHeight = 18;
    final current =
        clearPrevious ? const WaveformTrackVisual.line() : _waveformVisual;
    _waveformTransition.stop();
    _waveformFrom = current;
    _waveformTarget = target;
    _waveformTo = target == null
        ? const WaveformTrackVisual.line()
        : WaveformTrackVisual.wave(target);
    if (!_active || _reduced || (target == null && current.layers.isEmpty)) {
      _waveformTransition.value = 1;
    } else {
      _waveformTransition.forward(from: 0);
    }
  }

  // The painter supplies the exact bucket/geometry height. A large pointer or
  // seek jump moves x immediately; only this short visual height tween follows.
  double _resolveHandleHeight(double target) {
    if (!_active || _reduced) {
      _handleJumpPending = _handleTweenActive = false;
      return _handlePaintedHeight = target;
    }
    if (_waveformTransition.isAnimating) {
      final anchor = _handleMorphAnchor;
      if (anchor != null) {
        _handleMorphCorrection ??= anchor - target;
        target += _handleMorphCorrection! *
            (1 - Curves.easeInOutCubic.transform(_waveformTransition.value));
      }
      return _handlePaintedHeight = target;
    }
    if (_handleJumpPending) {
      _handleJumpPending = false;
      _handleFrom = _handlePaintedHeight;
      _handleTo = target;
      _handleTweenActive = (_handleTo - _handleFrom).abs() > .1;
      if (_handleTweenActive) {
        final generation = ++_handleGeneration;
        // A controller cannot mark the tree dirty during paint. Start after
        // this frame, retaining the old height at the already-updated x.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              generation == _handleGeneration &&
              _active &&
              !_reduced) {
            _handleTransition.forward(from: 0);
          }
        });
        return _handlePaintedHeight = _handleFrom;
      }
    }
    if (_handleTweenActive) {
      return _handlePaintedHeight = _handleFrom +
          (_handleTo - _handleFrom) *
              Curves.easeOutCubic.transform(_handleTransition.value);
    }
    return _handlePaintedHeight = target;
  }

  void _markHandleJump(double previous, double next) {
    if (_waveformPeaks.isNotEmpty && (next - previous).abs() > .75) {
      _handleJumpPending = true;
    }
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
    final active = (_preferences?.value ?? const RenderingPreferences())
        .allowsVisualUpdates(
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
    if ((!_active || _reduced) && _waveformTransition.isAnimating) {
      _waveformTransition.stop();
      _waveformTransition.value = 1;
    }
    if (!_active || _reduced) {
      _handleGeneration++;
      _handleJumpPending = _handleTweenActive = false;
      _handleTransition.stop();
      _handleTransition.value = 1;
    }
  }

  void _receive(double position, {bool immediate = false}) {
    if (_dragging) return;
    final target = _safe(position);
    final delta = target - _display.value;
    if (target == _target && !immediate) return;
    _markHandleJump(_display.value, target);
    _target = target;
    // Seeks, loop jumps and track changes must never slide through old time.
    if (immediate || _reduced || !_active || delta <= 0 || delta > .75) {
      _smoothing.stop();
      _display.value = target;
    } else if (_smoothing.isAnimating) {
      _follow!.retarget(
          from: _display.value,
          target: target,
          elapsed: _smoothing.lastElapsedDuration ?? Duration.zero);
    } else {
      _follow = DetailPositionFollow(
          from: _display.value,
          target: target,
          duration: AppMotion.followSample);
      _smoothing.animateWith(_follow!);
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
    _markHandleJump(_display.value, _safe(value));
    _display.value = _safe(value);
  }

  void _finish(double value) {
    final canSeek =
        _dragging && _enabled && _dragIdentity == widget.trackIdentity;
    setState(() => _dragging = false);
    _dragIdentity = null;
    try {
      if (canSeek) widget.onSeek(_safe(value));
    } catch (error, stack) {
      // Let Slider finish its own gesture cleanup even if a caller fails.
      // Rethrowing here leaves its internal interaction active on the next
      // drag; report through Flutter's usual error channel instead.
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'Dan Player',
        context: ErrorDescription('while seeking from the detail timeline'),
      ));
    } finally {
      if (mounted) _receive(widget.readPosition(), immediate: true);
    }
  }

  void _cancelPointer(int pointer) {
    if (_pointer != pointer) return;
    _pointer = null;
    if (!_dragging) return;
    // Material Slider also calls onChangeEnd for pointer cancellation. Clear
    // the preview before its recognizer runs so lost native capture cannot
    // commit a seek as if the user had released the handle normally.
    setState(() => _dragging = false);
    _dragIdentity = null;
    _receive(widget.readPosition(), immediate: true);
  }

  @override
  void dispose() {
    _detach();
    WidgetsBinding.instance.removeObserver(this);
    widget.hidden?.removeListener(_syncActivity);
    _preferences?.removeListener(_syncActivity);
    _smoothing.dispose();
    _waveformTransition.dispose();
    _handleTransition.dispose();
    _display.dispose();
    _elapsed.dispose();
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
    final timeline = RepaintBoundary(
      child: Column(children: [
        MouseRegion(
          cursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Listener(
            onPointerDown: (event) => _pointer ??= event.pointer,
            onPointerUp: (event) {
              if (_pointer == event.pointer) _pointer = null;
            },
            onPointerCancel: (event) => _cancelPointer(event.pointer),
            child: Focus(
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: emphasis),
                duration: motion ? AppMotion.quick : Duration.zero,
                curve: Curves.easeOutCubic,
                builder: (context, emphasis, child) => SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4 + emphasis,
                    trackShape: _waveformVisual.layers.isEmpty
                        ? const RoundedRectSliderTrackShape()
                        : DetailWaveformTrackShape.visual(_waveformVisual),
                    thumbShape: DetailProgressHandleShape(
                        emphasis: emphasis,
                        resolveHeight: _resolveHandleHeight),
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
                child: _withWaveformTooltip(ValueListenableBuilder<double>(
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
                              if (_dragging) {
                                _markHandleJump(_display.value, _safe(value));
                                _display.value = _safe(value);
                              }
                            }
                          : null,
                      onChangeEnd: _enabled ? _finish : null,
                    ),
                  ),
                )),
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
                  ValueListenableBuilder<int>(
                    valueListenable: _elapsed,
                    builder: (context, position, _) => Text(
                        _time(position.toDouble()),
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
    // Native hiding does not necessarily insert an ancestor TickerMode.
    // Mute stock Slider enable/hover animations as well as our finite tickers.
    return TickerMode(enabled: _active, child: timeline);
  }

  Widget _withWaveformTooltip(Widget child) {
    final message = widget.waveformTooltip;
    if (message == null || message.trim().isEmpty) return child;
    return Tooltip(message: message, excludeFromSemantics: true, child: child);
  }
}
