import 'package:dan_player/component/app_motion.dart';
import 'dart:async';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RectangleProgressIndicator extends StatefulWidget {
  const RectangleProgressIndicator({
    super.key,
    required this.size,
    required this.child,
    this.positionStream,
    this.lengthProvider,
    this.initialPosition = 0,
    this.trackIdentity,
    this.onSeek,
  });

  final Size size;
  final Widget child;

  /// Test seams also make this component reusable without creating another
  /// player. Production callers leave both null and use the single PlayService.
  final Stream<double>? positionStream;
  final double Function()? lengthProvider;
  final double initialPosition;
  final Object? trackIdentity;
  final ValueChanged<double>? onSeek;

  @override
  State<RectangleProgressIndicator> createState() =>
      _RectangleProgressIndicatorState();
}

class _RectangleProgressIndicatorState extends State<RectangleProgressIndicator>
    with SingleTickerProviderStateMixin {
  /// [positionStream] 的订阅，在dispose取消订阅
  late StreamSubscription<double> subscription;

  /// position / length, [0, 1]
  final progress = ValueNotifier<double>(0);
  late final AnimationController _highlightBoundary;
  final _seekFocus = FocusNode(debugLabel: 'Now playing progress');
  bool _disposed = false;
  bool _dragging = false;
  bool _dragCandidate = false;
  bool _hoveringBoundary = false;
  bool _suppressHoverUntilExit = false;
  bool _pointerFocus = false;
  bool _keyboardFocus = false;
  bool _highlightWanted = false;
  bool _disableAnimations = false;
  double? _hoverX;
  Object? _dragIdentity;
  double _latestFraction = 0;

  double get _length {
    final length = widget.lengthProvider?.call() ??
        PlayService.instance.playbackService.length;
    return length.isFinite && length > 0 ? length : 0;
  }

  double _fraction(double position) => _length > 0 && position.isFinite
      ? (position / _length).clamp(0.0, 1.0)
      : 0;

  void _attach() {
    _latestFraction = _fraction(widget.initialPosition);
    progress.value = _latestFraction;
    subscription = (widget.positionStream ??
            PlayService.instance.playbackService.positionStream)
        .listen((event) {
      if (_disposed) return;
      _latestFraction = _fraction(event);
      if (!_dragging) {
        progress.value = _latestFraction;
        _refreshHover();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _highlightBoundary = AnimationController(vsync: this);
    _seekFocus.addListener(_onSeekFocusChanged);
    _attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations != disableAnimations) {
      _disableAnimations = disableAnimations;
      _highlightBoundary.value = _highlightWanted ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(RectangleProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionStream != widget.positionStream) {
      subscription.cancel();
      _cancelSeek();
      _attach();
    }
    if (oldWidget.trackIdentity != widget.trackIdentity) {
      _dragCandidate = false;
      _dragging = false;
      _dragIdentity = null;
      _latestFraction = _fraction(widget.initialPosition);
      progress.value = _latestFraction;
      _finishPointerHint();
    } else if (widget.onSeek == null || _length == 0) {
      _cancelSeek();
    }
    _refreshHover();
    _updateHighlight();
  }

  void _beginSeek() {
    if (!_dragCandidate || widget.onSeek == null || _length == 0) return;
    _dragging = true;
    _dragIdentity = widget.trackIdentity;
    _pointerFocus = true;
    _keyboardFocus = false;
    _suppressHoverUntilExit = false;
    _seekFocus.requestFocus();
    _updateHighlight();
  }

  void _seekAt(double x) {
    if (!_dragging || !x.isFinite || widget.size.width <= 0) return;
    progress.value = (x / widget.size.width).clamp(0.0, 1.0);
  }

  void _cancelSeek() {
    _dragCandidate = false;
    _dragging = false;
    _dragIdentity = null;
    progress.value = _latestFraction;
    _finishPointerHint();
  }

  void _commitSeek() {
    final valid = _dragging &&
        _dragIdentity == widget.trackIdentity &&
        widget.onSeek != null &&
        _length > 0;
    _dragging = false;
    _dragCandidate = false;
    _dragIdentity = null;
    final previousFraction = _latestFraction;
    try {
      if (valid) {
        _latestFraction = progress.value;
        widget.onSeek!(progress.value * _length);
      } else {
        progress.value = _latestFraction;
      }
    } catch (_) {
      _latestFraction = previousFraction;
      progress.value = previousFraction;
      rethrow;
    } finally {
      _finishPointerHint();
    }
  }

  bool _atBoundary(double x) =>
      widget.onSeek != null &&
      _length > 0 &&
      widget.size.width.isFinite &&
      widget.size.width > 0 &&
      (x - progress.value * widget.size.width).abs() <= 12;

  void _updateHighlight() {
    if (_disposed) return;
    final wanted = widget.onSeek != null &&
        _length > 0 &&
        (_dragging ||
            (_hoveringBoundary && !_suppressHoverUntilExit) ||
            (_keyboardFocus && _seekFocus.hasPrimaryFocus));
    if (_highlightWanted == wanted) return;
    _highlightWanted = wanted;
    if (_disableAnimations) {
      _highlightBoundary.value = wanted ? 1 : 0;
    } else {
      _highlightBoundary.animateTo(wanted ? 1 : 0,
          duration: AppMotion.quick, curve: Curves.easeOutCubic);
    }
  }

  void _finishPointerHint() {
    // A stationary mouse and the focus retained for arrow-key seeking must
    // not pin the hint after release. Hover can reveal it on the next entry.
    _suppressHoverUntilExit = true;
    // Drag events aren't hover events. Wait for a fresh mouse position rather
    // than using the pre-drag coordinate to re-enable the just-dismissed hint.
    _hoverX = null;
    _keyboardFocus = false;
    _updateHighlight();
  }

  void _onSeekFocusChanged() {
    _keyboardFocus = _seekFocus.hasPrimaryFocus && !_pointerFocus;
    if (!_seekFocus.hasPrimaryFocus) _pointerFocus = false;
    _updateHighlight();
  }

  void _hoverBoundary(bool hovering) {
    if (!hovering) _suppressHoverUntilExit = false;
    if (_hoveringBoundary != hovering) {
      setState(() => _hoveringBoundary = hovering);
    }
    _updateHighlight();
  }

  void _handleHover(PointerEvent event) {
    _hoverX = event.localPosition.dx;
    _refreshHover();
  }

  void _refreshHover() {
    final x = _hoverX;
    if (x != null && !_dragging) _hoverBoundary(_atBoundary(x));
  }

  void _seekByKeyboard(double fraction) {
    if (widget.onSeek == null || _length == 0) return;
    _cancelSeek();
    _latestFraction = fraction.clamp(0.0, 1.0);
    progress.value = _latestFraction;
    try {
      widget.onSeek!(_latestFraction * _length);
    } finally {
      _pointerFocus = false;
      _keyboardFocus = _seekFocus.hasPrimaryFocus;
      _updateHighlight();
    }
  }

  KeyEventResult _onSeekKey(FocusNode node, KeyEvent event) {
    // Do not intercept arrow keys from the independently focusable controls.
    if (!node.hasPrimaryFocus ||
        widget.onSeek == null ||
        _length == 0 ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final value = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => progress.value - 5 / _length,
      LogicalKeyboardKey.arrowRight => progress.value + 5 / _length,
      LogicalKeyboardKey.home => 0.0,
      LogicalKeyboardKey.end => 1.0,
      _ => null,
    };
    if (value == null) return KeyEventResult.ignored;
    _seekByKeyboard(value);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final canSeek = widget.onSeek != null && _length > 0;
    // Flutter's accepted DragGestureRecognizer ends on PointerCancel too.
    // Invalidate before it dispatches onEnd, so losing native capture cannot
    // turn a cancelled gesture into an unintended seek.
    return Focus(
      key: const ValueKey('now-playing-seek'),
      focusNode: _seekFocus,
      canRequestFocus: canSeek,
      onKeyEvent: _onSeekKey,
      child: MouseRegion(
        cursor: canSeek && _hoveringBoundary
            ? SystemMouseCursors.resizeColumn
            : MouseCursor.defer,
        onEnter: _handleHover,
        onHover: _handleHover,
        onExit: (_) {
          _hoverX = null;
          _hoverBoundary(false);
        },
        child: Listener(
            // The existing colour boundary is the handle. Keeping recognition on
            // the parent (not an overlay) lets every transport button still win a
            // tap, even when the moving boundary happens to cross that button.
            onPointerDown: (event) => _dragCandidate =
                event.buttons == kPrimaryButton &&
                    _atBoundary(event.localPosition.dx),
            onPointerCancel: (_) => _cancelSeek(),
            child: RawGestureDetector(
              excludeFromSemantics: true,
              gestures: {
                if (canSeek)
                  _BoundaryDragRecognizer: GestureRecognizerFactoryWithHandlers<
                      _BoundaryDragRecognizer>(
                    () => _BoundaryDragRecognizer(debugOwner: this),
                    (recognizer) {
                      recognizer.acceptsDown =
                          (event) => _atBoundary(event.localPosition.dx);
                      recognizer.onStart = (details) {
                        _beginSeek();
                        _seekAt(details.localPosition.dx);
                      };
                      recognizer.onUpdate =
                          (details) => _seekAt(details.localPosition.dx);
                      recognizer.onEnd = (_) => _commitSeek();
                      recognizer.onCancel = _cancelSeek;
                    },
                  ),
              },
              child: Builder(
                  builder: (paintContext) => CustomPaint(
                        size: widget.size,
                        painter: RectangleProgressPainter(
                            progress: progress,
                            scheme: scheme,
                            dragIndicatorColor: scheme.primary,
                            devicePixelRatio:
                                MediaQuery.devicePixelRatioOf(context),
                            globalOrigin: () {
                              if (!paintContext.mounted) return Offset.zero;
                              final render = paintContext.findRenderObject();
                              return render is RenderBox && render.attached
                                  ? render.localToGlobal(Offset.zero)
                                  : Offset.zero;
                            },
                            highlightBoundary: _highlightBoundary),
                        child: ValueListenableBuilder<double>(
                          valueListenable: progress,
                          child: widget.child,
                          builder: (context, fraction, child) => Semantics(
                            key: const ValueKey('now-playing-seek-semantics'),
                            container: true,
                            explicitChildNodes: true,
                            slider: true,
                            enabled: canSeek,
                            label: ui('播放进度'),
                            value: '${(fraction * 100).round()}%',
                            increasedValue: canSeek
                                ? '${((fraction + 5 / _length).clamp(0.0, 1.0) * 100).round()}%'
                                : null,
                            decreasedValue: canSeek
                                ? '${((fraction - 5 / _length).clamp(0.0, 1.0) * 100).round()}%'
                                : null,
                            onIncrease: canSeek
                                ? () => _seekByKeyboard(
                                    progress.value + 5 / _length)
                                : null,
                            onDecrease: canSeek
                                ? () => _seekByKeyboard(
                                    progress.value - 5 / _length)
                                : null,
                            child: child,
                          ),
                        ),
                      )),
            )),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    subscription.cancel();
    _seekFocus.dispose();
    _highlightBoundary.dispose();
    progress.dispose();
    super.dispose();
  }
}

class _BoundaryDragRecognizer extends HorizontalDragGestureRecognizer {
  _BoundaryDragRecognizer({super.debugOwner});

  bool Function(PointerDownEvent)? acceptsDown;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event is PointerDownEvent &&
      acceptsDown?.call(event) == true &&
      super.isPointerAllowed(event);

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool hasSufficientGlobalDistanceToAccept(
          PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      pointerDeviceKind == PointerDeviceKind.mouse
          // Match tap tolerance: the default mouse drag's 1px threshold can
          // cancel a button tap on ordinary hand jitter, even at the boundary.
          ? globalDistanceMoved.abs() > kTouchSlop
          : super.hasSufficientGlobalDistanceToAccept(
              pointerDeviceKind, deviceTouchSlop);
}

class RectangleProgressPainter extends CustomPainter {
  /// position / length, [0, 1]
  final ValueNotifier<double> progress;

  final ColorScheme scheme;
  final Color dragIndicatorColor;
  final ValueListenable<double>? highlightBoundary;
  final double devicePixelRatio;
  final Offset Function()? globalOrigin;

  RectangleProgressPainter(
      {required this.progress,
      required this.scheme,
      required this.dragIndicatorColor,
      this.highlightBoundary,
      this.devicePixelRatio = 1,
      this.globalOrigin})
      : super(repaint: Listenable.merge([progress, highlightBoundary]));

  @override
  void paint(Canvas canvas, Size size) {
    final progressPainter = Paint();
    progressPainter.color = scheme.primary.withValues(alpha: 0.16);

    final trackPainter = Paint();
    trackPainter.color = scheme.surfaceContainerHighest.withValues(alpha: 0.42);

    /// 进度条背景
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width, size.height),
      trackPainter,
    );

    /// 进度
    canvas.drawRect(
      Rect.fromLTWH(0.0, 0.0, size.width * progress.value, size.height),
      progressPainter,
    );
    final opacity = highlightBoundary?.value ?? 0;
    if (opacity > 0 && size.width >= 6 && size.height >= 12) {
      final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
          ? devicePixelRatio
          : 1.0;
      final width =
          ((2 * ratio).roundToDouble() / ratio).clamp(1.0, size.width);
      // A centered bar may start on half a physical pixel. Include layer
      // offsets, but resolve this transform only while the hint is visible.
      final origin = globalOrigin?.call().dx ?? 0.0;
      final originX = origin.isFinite ? origin : 0.0;
      final left = ((size.width * progress.value - width / 2 + originX) * ratio)
                  .roundToDouble() /
              ratio -
          originX;
      final fullHeight = (size.height - 16).clamp(6.0, 26.0);
      // Keep the visible core on the active theme colour. Applying the
      // animation value as alpha blends a saturated primary into a dark track
      // and can make the handle look black or fixed-grey. Only the short end
      // of the existing 80/100ms transition changes its length instead.
      const revealFraction = 0.08;
      final reveal = (opacity / revealFraction).clamp(0.0, 1.0);
      final height = fullHeight * Curves.easeOutCubic.transform(reveal);
      final bounds = Rect.fromLTWH(left.clamp(0.0, size.width - width),
          (size.height - height) / 2, width, height);
      final tint = Paint()..color = dragIndicatorColor;
      // Pixel-aligned, solid core: no gradient, halo or spindle-shaped bulge.
      // Rounded ends meet the colour boundary; only the whole hint fades out.
      canvas.drawRRect(
          RRect.fromRectAndRadius(bounds, const Radius.circular(1)), tint);
    }
  }

  @override
  bool shouldRepaint(RectangleProgressPainter oldDelegate) =>
      oldDelegate.scheme != scheme ||
      oldDelegate.dragIndicatorColor != dragIndicatorColor ||
      oldDelegate.progress != progress ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.globalOrigin != globalOrigin ||
      oldDelegate.highlightBoundary != highlightBoundary;

  @override
  bool shouldRebuildSemantics(RectangleProgressPainter oldDelegate) => false;
}
