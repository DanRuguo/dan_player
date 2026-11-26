import 'dart:ui' as ui;

import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Cross-dissolves an in-page section when [identity] changes.
///
/// The live child keeps an unchanging Element path (`_CrossDissolveSnapshotBox`
/// -> `FadeTransition` -> `RepaintBoundary` -> [child]) across idle, animating
/// and completed states, so editors, scroll controllers and focus nodes never
/// remount. When motion is allowed, the outgoing frame is captured once as a
/// bounded GPU texture (`toImageSync`) and dissolved underneath the incoming
/// child so dark themes never dip to black between views; the texture is
/// disposed immediately upon completion, lifecycle hide, reduced motion or
/// widget disposal.
class AppContentTransition extends StatefulWidget {
  const AppContentTransition({
    super.key,
    required this.identity,
    required this.child,
  });

  final Object identity;
  final Widget child;

  static const int maximumSnapshotPixels = 16 * 1024 * 1024;
  static const int maximumSnapshotSide = 8192;

  @visibleForTesting
  static bool debugHasOutgoingSnapshot(BuildContext context) {
    var active = false;
    void visit(Element element) {
      if (active) return;
      if (element is StatefulElement &&
          element.state is _AppContentTransitionState) {
        active = (element.state as _AppContentTransitionState)._outgoing != null;
        if (active) return;
      }
      element.visitChildren(visit);
    }

    visit(context as Element);
    return active;
  }

  @override
  State<AppContentTransition> createState() => _AppContentTransitionState();
}

class _AppContentTransitionState extends State<AppContentTransition>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _boundaryKey = GlobalKey();
  late final _controller =
      AnimationController(vsync: this, duration: AppMotion.standard, value: 1)
        ..addStatusListener(_onStatus);
  late final _opacity =
      _controller.drive(CurveTween(curve: AppMotion.standardCurve));
  bool _enabled = true;
  double _pixelRatio = 1.0;
  ui.Image? _outgoing;
  Size? _outgoingSize;

  bool get _platformReducesMotion {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return features.disableAnimations || features.reduceMotion;
  }

  bool get _lifecycleAllowsSnapshot {
    final state = WidgetsBinding.instance.lifecycleState;
    return state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
  }

  bool get _canAnimate =>
      _enabled && !_platformReducesMotion && _lifecycleAllowsSnapshot;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _outgoing != null) {
      if (mounted) {
        setState(_releaseOutgoing);
      } else {
        _releaseOutgoing();
      }
    }
  }

  void _releaseOutgoing() {
    _outgoing?.dispose();
    _outgoing = null;
    _outgoingSize = null;
  }

  void _captureOutgoingSnapshot() {
    _releaseOutgoing();
    final render = _boundaryKey.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary ||
        !render.attached ||
        !render.hasSize ||
        render.size.isEmpty ||
        render.debugNeedsPaint) {
      return;
    }
    final size = render.size;
    if (!size.width.isFinite || !size.height.isFinite) return;
    final dpr = _pixelRatio > 0 && _pixelRatio.isFinite ? _pixelRatio : 1.0;
    final width = (size.width * dpr).ceil();
    final height = (size.height * dpr).ceil();
    if (width <= 0 ||
        height <= 0 ||
        width > AppContentTransition.maximumSnapshotSide ||
        height > AppContentTransition.maximumSnapshotSide ||
        width * height > AppContentTransition.maximumSnapshotPixels) {
      return;
    }
    try {
      _outgoing = render.toImageSync(pixelRatio: dpr);
      _outgoingSize = size;
    } catch (_) {
      _releaseOutgoing();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enabled = TickerMode.valuesOf(context).enabled &&
        AppMotion.enabled(context, MotionKind.transitions);
    final nextRatio = MediaQuery.devicePixelRatioOf(context);
    final ratioChanged = nextRatio != _pixelRatio;
    _pixelRatio = nextRatio;
    if (!_canAnimate || ratioChanged) {
      _releaseOutgoing();
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AppContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity == widget.identity) return;
    if (_canAnimate) {
      _captureOutgoingSnapshot();
      _controller.forward(from: 0);
    } else {
      _releaseOutgoing();
      _controller.value = 1;
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (_platformReducesMotion) {
      _releaseOutgoing();
      _controller.value = 1;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lifecycleAllowsSnapshot &&
        (_outgoing != null || _controller.isAnimating)) {
      _releaseOutgoing();
      _controller.value = 1;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _releaseOutgoing();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _CrossDissolveSnapshotBox(
        progress: _controller,
        outgoing: _outgoing,
        outgoingSize: _outgoingSize,
        child: FadeTransition(
          opacity: _opacity,
          alwaysIncludeSemantics: true,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: widget.child,
          ),
        ),
      );
}

class _CrossDissolveSnapshotBox extends SingleChildRenderObjectWidget {
  const _CrossDissolveSnapshotBox({
    required this.progress,
    required this.outgoing,
    required this.outgoingSize,
    required super.child,
  });

  final Animation<double> progress;
  final ui.Image? outgoing;
  final Size? outgoingSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCrossDissolveSnapshot(
        progress: progress,
        outgoing: outgoing,
        outgoingSize: outgoingSize,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCrossDissolveSnapshot renderObject,
  ) {
    renderObject
      ..progress = progress
      ..outgoing = outgoing
      ..outgoingSize = outgoingSize;
  }
}

class _RenderCrossDissolveSnapshot extends RenderProxyBox {
  _RenderCrossDissolveSnapshot({
    required Animation<double> progress,
    required ui.Image? outgoing,
    required Size? outgoingSize,
  })  : _progress = progress,
        _outgoing = outgoing,
        _outgoingSize = outgoingSize;

  Animation<double> _progress;
  set progress(Animation<double> value) {
    if (identical(_progress, value)) return;
    if (attached) _progress.removeListener(_onTick);
    _progress = value;
    if (attached) _progress.addListener(_onTick);
    markNeedsPaint();
  }

  ui.Image? _outgoing;
  set outgoing(ui.Image? value) {
    if (identical(_outgoing, value)) return;
    _outgoing = value;
    markNeedsPaint();
  }

  Size? _outgoingSize;
  set outgoingSize(Size? value) {
    if (_outgoingSize == value) return;
    _outgoingSize = value;
    markNeedsPaint();
  }

  void _onTick() {
    if (_outgoing != null) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_onTick);
  }

  @override
  void detach() {
    _progress.removeListener(_onTick);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final snapshot = _outgoing;
    final expectedSize = _outgoingSize;
    final t = _progress.value.clamp(0.0, 1.0);
    if (snapshot != null &&
        t < 1.0 &&
        expectedSize != null &&
        (expectedSize.width - size.width).abs() <= 1.0 &&
        (expectedSize.height - size.height).abs() <= 1.0) {
      // Ease-in outgoing retention paired with ease-out incoming reveal keeps
      // combined coverage >= 96.9% across the entire cross-dissolve, preventing
      // dark-theme black flashes while still fading empty tail space cleanly.
      final outOpacity = 1.0 - Curves.easeInQuad.transform(t);
      final alpha = (outOpacity * 255).round().clamp(0, 255);
      if (alpha > 0) {
        final src = Rect.fromLTWH(
          0,
          0,
          snapshot.width.toDouble(),
          snapshot.height.toDouble(),
        );
        context.canvas.drawImageRect(
          snapshot,
          src,
          offset & size,
          Paint()
            ..filterQuality = FilterQuality.low
            ..color = Color.fromARGB(alpha, 255, 255, 255),
        );
      }
    }
    super.paint(context, offset);
  }
}
