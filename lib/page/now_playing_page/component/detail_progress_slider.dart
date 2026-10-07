import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/primary_pointer_input.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:dan_player/utils.dart' show showAppNotice;
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/page/now_playing_page/component/detail_waveform_track.dart';
import 'package:dan_player/page/now_playing_page/component/detail_position_follow.dart';
import 'dart:async';

import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import 'detail_timeline_annotations.dart';

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
    this.bookmarks = const [],
    this.loopStart,
    this.loopEnd,
    this.loopEnabled = false,
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
  final List<PlaybackBookmark> bookmarks;
  final double? loopStart, loopEnd;
  final bool loopEnabled;

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
  final _hoverPosition = ValueNotifier<double?>(null);
  final _previewOverlay = OverlayPortalController();
  final _previewLink = LayerLink();
  late final FocusNode _sliderFocus;
  bool _showRemaining = false;
  double? _undoPosition;
  double _dragOrigin = 0;
  double _lastPreviewFraction = 0;
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
  bool _ignoreAdjustmentCycle = false;
  Object? _dragIdentity;
  int? _pointer;
  double _target = 0;
  int _generation = 0;

  double get _length =>
      widget.duration.isFinite && widget.duration > 0 ? widget.duration : 0;
  bool get _enabled => widget.enabled && _length > 0;
  double _safe(double value) =>
      value.isFinite ? value.clamp(0.0, _length).toDouble() : 0;

  static String _time(double seconds) => detailTimelineTime(seconds);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _previewOverlay.show();
    });
    _sliderFocus = FocusNode(onKeyEvent: _handleKey);
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
      _undoPosition = null;
      _hoverPosition.value = null;
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
        _hoverPosition.value = null;
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
    // Semantics adjustments synchronously emit a second start/change/end even
    // while Material's physical drag remains active. Keep that touch's preview.
    if (_dragging && _pointer != null) {
      _ignoreAdjustmentCycle = true;
      return;
    }
    _smoothing.stop();
    _dragOrigin = _safe(widget.readPosition());
    _dragIdentity = widget.trackIdentity;
    setState(() => _dragging = true);
    _markHandleJump(_display.value, _safe(value));
    _display.value = _safe(value);
  }

  void _finish(double value) {
    if (_ignoreAdjustmentCycle) {
      _ignoreAdjustmentCycle = false;
      return;
    }
    // An end while the finger is still down is a semantics cycle or an arena
    // cancellation to the controls' scrollable, never a physical release.
    final canSeek = _pointer == null &&
        _dragging &&
        _enabled &&
        _dragIdentity == widget.trackIdentity;
    // MouseRegion does not emit hover while a button is down. Hand off at the
    // last drag position instead of reviving the stale pre-drag hover point.
    _hoverPosition.value = _hovered ? _safe(value) : null;
    setState(() => _dragging = false);
    _dragIdentity = null;
    try {
      if (canSeek) _commitSeek(value, origin: _dragOrigin);
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

  void _commitSeek(double target, {double? origin, bool remember = true}) {
    if (!_enabled || !_active) return;
    final identity = widget.trackIdentity;
    final before = origin ?? _safe(widget.readPosition());
    final value = _safe(target);
    widget.onSeek(value);
    if (!mounted || identity != widget.trackIdentity) return;
    // The service can reject a seek (buffering/device transition). Remember
    // only a real position change, never offer an undo for a failed command.
    final actual = _safe(widget.readPosition());
    if (remember && (actual - before).abs() > .05) {
      setState(() => _undoPosition = before);
    }
    _receive(actual, immediate: true);
  }

  void _seekFromAction(double target, {bool remember = true}) {
    try {
      _commitSeek(target, remember: remember);
    } catch (error) {
      if (mounted) {
        _receive(widget.readPosition(), immediate: true);
        showAppNotice(ui('操作失败：{0}', [error]),
            context: context, kind: AppNoticeKind.error);
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (_dragging || _pointer != null || !_active) {
      // Ignoring an arrow lets Material's enclosing shortcut commit the
      // preview through onChangeStart/onChangeEnd while a pointer still owns it.
      return key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (!_enabled) return KeyEventResult.ignored;
    final step = keyboard.isShiftPressed ? 1.0 : 5.0;
    double? target;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final forward = (key == LogicalKeyboardKey.arrowRight) != rtl;
      target = widget.readPosition() + (forward ? step : -step);
    } else if (!keyboard.isShiftPressed) {
      if (key == LogicalKeyboardKey.home) target = 0;
      if (key == LogicalKeyboardKey.end) target = _length;
      const digits = [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      final digit = digits.indexOf(key);
      if (digit >= 0) target = _length * digit / 10;
    }
    if (target == null) return KeyEventResult.ignored;
    _seekFromAction(target);
    return KeyEventResult.handled;
  }

  void _hover(Offset local, double width) {
    if (!_enabled || !_active || width <= 48) return;
    var fraction = ((local.dx - 24) / (width - 48)).clamp(0.0, 1.0);
    if (Directionality.of(context) == TextDirection.rtl) {
      fraction = 1 - fraction;
    }
    _hoverPosition.value = (_length * fraction).floorToDouble();
  }

  Future<void> _copyTime() async {
    final time = _time(_safe(widget.readPosition()));
    try {
      await Clipboard.setData(ClipboardData(text: time));
      if (mounted) {
        showAppNotice(ui('已复制播放时间'),
            context: context, kind: AppNoticeKind.success);
      }
    } catch (error) {
      if (mounted) {
        showAppNotice(ui('复制播放时间失败：{0}', [error]),
            context: context, kind: AppNoticeKind.error);
      }
    }
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
    _hoverPosition.dispose();
    _sliderFocus.dispose();
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        DetailTimelineAnnotations(
          duration: _length,
          bookmarks: widget.bookmarks,
          loopStart: widget.loopStart,
          loopEnd: widget.loopEnd,
          loopEnabled: widget.loopEnabled,
          onBookmark: _enabled
              ? (bookmark) => _seekFromAction(bookmark.position)
              : null,
        ),
        LayoutBuilder(
            builder: (context, constraints) => OverlayPortal(
                controller: _previewOverlay,
                overlayChildBuilder: (context) => Positioned(
                    width:
                        (constraints.maxWidth - 48).clamp(1.0, double.infinity),
                    child: CompositedTransformFollower(
                      link: _previewLink,
                      targetAnchor: Alignment.topLeft,
                      followerAnchor: Alignment.bottomLeft,
                      offset: const Offset(24, 6),
                      showWhenUnlinked: false,
                      child: _previewBubble(scheme),
                    )),
                child: CompositedTransformTarget(
                  link: _previewLink,
                  child: MouseRegion(
                    cursor: _enabled
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    onEnter: (_) => setState(() => _hovered = true),
                    onHover: (event) =>
                        _hover(event.localPosition, constraints.maxWidth),
                    onExit: (_) {
                      _hoverPosition.value = null;
                      setState(() => _hovered = false);
                    },
                    child: PrimaryPointerInput(
                        child: Listener(
                      onPointerDown: (event) => _pointer ??= event.pointer,
                      onPointerUp: (event) {
                        if (_pointer == event.pointer) _pointer = null;
                      },
                      onPointerCancel: (event) => _cancelPointer(event.pointer),
                      child: Focus(
                        onFocusChange: (focused) =>
                            setState(() => _focused = focused),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: emphasis),
                          duration: motion ? AppMotion.quick : Duration.zero,
                          curve: Curves.easeOutCubic,
                          builder: (context, emphasis, child) => SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4 + emphasis,
                              trackShape: _waveformVisual.layers.isEmpty
                                  ? const RoundedRectSliderTrackShape()
                                  : DetailWaveformTrackShape.visual(
                                      _waveformVisual),
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
                              showValueIndicator: ShowValueIndicator.never,
                            ),
                            child: child!,
                          ),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _display,
                            builder: (context, position, _) => Semantics(
                              label: ui('播放进度'),
                              child: Slider(
                                key: const ValueKey('detail-progress-slider'),
                                focusNode: _sliderFocus,
                                min: 0,
                                max: _length > 0 ? _length : 1,
                                value: _safe(position),
                                label: _dragging
                                    ? '${_time(position)}  (${position >= _dragOrigin ? '+' : '−'}${_time((position - _dragOrigin).abs())})'
                                    : _time(position),
                                semanticFormatterCallback: _time,
                                onChangeStart: _enabled ? _begin : null,
                                onChanged: _enabled
                                    ? (value) {
                                        if (_dragging &&
                                            !_ignoreAdjustmentCycle) {
                                          _markHandleJump(
                                              _display.value, _safe(value));
                                          _display.value = _safe(value);
                                        }
                                      }
                                    : null,
                                onChangeEnd: _enabled ? _finish : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )),
                  ),
                ))),
        DetailTimelineScale(duration: _length),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.labelMedium!.copyWith(
                color: scheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()]),
            child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                spacing: 16,
                overflowSpacing: 2,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  _withWaveformTooltip(_timeMenu(scheme)),
                  Tooltip(
                    message: ui(_showRemaining ? '显示总时长' : '显示剩余时间'),
                    child: InkWell(
                      key: const ValueKey('detail-progress-time-mode'),
                      borderRadius: AppShape.smallRadius,
                      onTap: () =>
                          setState(() => _showRemaining = !_showRemaining),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _elapsed,
                          builder: (context, position, _) => Text(
                            _showRemaining
                                ? '−${_time((_length - position).clamp(0.0, _length))}'
                                : _time(_length),
                            key: const ValueKey('detail-progress-total'),
                            semanticsLabel: _showRemaining
                                ? ui('剩余 {0}', [
                                    _time((_length - position)
                                        .clamp(0.0, _length))
                                  ])
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
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
    final keyboard = ui('进度快捷键：←/→ 5 秒，Shift+←/→ 1 秒，Home/End 首尾，0–9 百分比');
    return Tooltip(
        message: [
          if (message != null && message.trim().isNotEmpty) message,
          keyboard
        ].join('\n'),
        excludeFromSemantics: true,
        child: child);
  }

  Widget _previewBubble(ColorScheme scheme) => IgnorePointer(
        child: ExcludeSemantics(
          child: ListenableBuilder(
            listenable: Listenable.merge([_display, _hoverPosition]),
            builder: (context, _) {
              final position =
                  _dragging ? _display.value : _hoverPosition.value;
              final visible = position != null && _enabled && _active;
              if (visible) {
                final fraction = position / _length;
                _lastPreviewFraction =
                    Directionality.of(context) == TextDirection.rtl
                        ? 1 - fraction
                        : fraction;
              }
              final duration =
                  _active && !_reduced ? AppMotion.quick : Duration.zero;
              // The numeral ink sits above the font's line-box centre. Balance
              // its optical padding without moving the bubble's time anchor.
              const opticalOffset = .5;
              return _PreviewPosition(
                fraction: _lastPreviewFraction,
                child: AnimatedSwitcher(
                  duration: duration,
                  reverseDuration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                          alignment: Alignment.bottomCenter,
                          scale: Tween<double>(begin: .8, end: 1)
                              .animate(animation),
                          child: child)),
                  child: !visible
                      ? const SizedBox.shrink()
                      : Material(
                          key: const ValueKey('detail-progress-preview-bubble'),
                          color: scheme.primaryContainer,
                          borderRadius: AppShape.smallRadius,
                          elevation: 2,
                          child: _previewSize(
                              duration,
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10,
                                    5 + opticalOffset, 10, 5 - opticalOffset),
                                child: Text(
                                  _dragging
                                      ? '${_time(position)}  (${position >= _dragOrigin ? '+' : '−'}${_time((position - _dragOrigin).abs())})'
                                      : _time(position),
                                  key: ValueKey(_dragging
                                      ? 'detail-progress-drag-time'
                                      : 'detail-progress-hover-time'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium
                                      ?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              )),
                        ),
                ),
              );
            },
          ),
        ),
      );

  Widget _previewSize(Duration duration, Widget child) =>
      duration == Duration.zero
          ? child
          : AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: child);

  Widget _timeMenu(ColorScheme scheme) {
    final identity = widget.trackIdentity;
    final generation = _generation;
    final undoPosition = _undoPosition;
    bool current() =>
        mounted &&
        !_dragging &&
        _pointer == null &&
        identity == widget.trackIdentity &&
        generation == _generation;
    final menuWidth =
        (MediaQuery.sizeOf(context).width - 32).clamp(120.0, 360.0);
    final menuStyle = MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, double.infinity)));
    Widget label(String text, {bool time = false}) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: menuWidth - 88),
          child: Text(text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: time
                  ? TextStyle(
                      color:
                          scheme.primary.withValues(alpha: _enabled ? 1 : .38))
                  : null),
        );
    final bookmarks = widget.bookmarks
        .where((b) => b.fitsDuration(_length))
        .toList()
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    return AppMenuAnchor(
      style: menuStyle,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('detail-progress-copy-time'),
          onPressed: _enabled ? _copyTime : null,
          leadingIcon: const Icon(Icons.content_copy),
          child: label(ui('复制播放时间')),
        ),
        MenuItemButton(
          key: const ValueKey('detail-progress-undo-seek'),
          onPressed: !_enabled || undoPosition == null
              ? null
              : () {
                  if (!current() || _undoPosition != undoPosition) return;
                  setState(() => _undoPosition = null);
                  _seekFromAction(undoPosition, remember: false);
                },
          leadingIcon: const Icon(Icons.undo),
          child: label(ui('撤销进度跳转')),
        ),
        if (bookmarks.isNotEmpty)
          AppSubmenuButton(
            menuStyle: menuStyle,
            leadingIcon: const Icon(Icons.bookmarks_outlined),
            menuChildren: [
              for (final bookmark in bookmarks)
                MenuItemButton(
                  onPressed: _enabled
                      ? () {
                          if (current()) _seekFromAction(bookmark.position);
                        }
                      : null,
                  child: label(
                      '${_time(bookmark.position)} · ${bookmark.label}',
                      time: true),
                ),
            ],
            child: label(ui('播放书签')),
          ),
      ],
      builder: (context, controller, _) => InkWell(
        key: const ValueKey('detail-progress-time-menu'),
        borderRadius: AppShape.smallRadius,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ValueListenableBuilder<int>(
            valueListenable: _elapsed,
            builder: (context, position, _) =>
                Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(_time(position.toDouble()),
                      key: const ValueKey('detail-progress-elapsed'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          _dragging ? TextStyle(color: scheme.primary) : null)),
              const SizedBox(width: 2),
              Icon(Icons.expand_more,
                  key: const ValueKey('detail-progress-time-chevron'),
                  size: 14,
                  color: scheme.primary),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Center the bubble on the media position, independently of the label width.
/// Only clamp near the ends; Align would shift its center whenever text changes.
class _PreviewPosition extends SingleChildRenderObjectWidget {
  const _PreviewPosition({required this.fraction, required super.child});
  final double fraction;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPreviewPosition(fraction);
  @override
  void updateRenderObject(
          BuildContext context, _RenderPreviewPosition renderObject) =>
      renderObject.fraction = fraction;
}

class _RenderPreviewPosition extends RenderShiftedBox {
  _RenderPreviewPosition(this._fraction) : super(null);
  double _fraction;
  set fraction(double value) {
    if (_fraction == value) return;
    _fraction = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size =
        constraints.constrain(Size(constraints.maxWidth, child!.size.height));
    (child!.parentData! as BoxParentData).offset = Offset(
        (size.width * _fraction - child!.size.width / 2).clamp(
            0.0, (size.width - child!.size.width).clamp(0.0, double.infinity)),
        0);
  }
}
