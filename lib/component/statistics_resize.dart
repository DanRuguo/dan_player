import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'app_motion.dart';
import 'app_toolbar_style.dart';

/// One finite height transition around a statistics section or complete grid.
/// Place outside intrinsic/equal-height rows, never around individual grid cells.
/// Width follows the viewport immediately, including continuous window resizing.
class StatisticsResize extends StatefulWidget {
  const StatisticsResize({super.key, required this.child});
  final Widget child;

  @override
  State<StatisticsResize> createState() => _StatisticsResizeState();
}

class _StatisticsResizeState extends State<StatisticsResize>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _contentKey = GlobalKey();
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle == state) return;
    setState(() => _lifecycle = state);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final treeVisible = TickerMode.valuesOf(context).enabled;
    final reduced = appToolbarReduceMotion(context, kind: MotionKind.layout);
    return ValueListenableBuilder<RenderingPreferences>(
      valueListenable: RenderingPreferencesScope.listenableOf(context),
      builder: (context, preferences, _) {
        final content = KeyedSubtree(key: _contentKey, child: widget.child);
        final animate = !reduced &&
            preferences.allowsVisualUpdates(
                lifecycle: _lifecycle, treeVisible: treeVisible);
        // Removing the clock lands at the natural height immediately and keeps
        // the same content, form state, focus and semantics in both branches.
        return SizedBox(
          width: double.infinity,
          child: animate
              ? _StatisticsHeightTransition(vsync: this, child: content)
              : content,
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _StatisticsHeightTransition extends SingleChildRenderObjectWidget {
  const _StatisticsHeightTransition(
      {required this.vsync, required super.child});
  final TickerProvider vsync;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStatisticsHeight(vsync: vsync);

  @override
  void updateRenderObject(
          BuildContext context, _RenderStatisticsHeight renderObject) =>
      renderObject.vsync = vsync;
}

/// AnimatedSize treats changing widths as unstable sizes and can snap a height
/// reflow. This proxy owns only a height transition; it lays out its direct child
/// normally, so animation ticks reuse that layout rather than measuring text.
class _RenderStatisticsHeight extends RenderProxyBox {
  _RenderStatisticsHeight({required TickerProvider vsync}) : _vsync = vsync {
    _controller = AnimationController(
        vsync: vsync, value: 1, duration: AppMotion.standard)
      ..addListener(_tick);
  }

  late final AnimationController _controller;
  TickerProvider _vsync;
  final _clipLayer = LayerHandle<ClipRectLayer>();
  double? _fromHeight;
  double? _targetHeight;
  bool _layingOut = false;
  bool _overflow = false;

  set vsync(TickerProvider value) {
    if (identical(value, _vsync)) return;
    _vsync = value;
    _controller.resync(value);
  }

  double get _presentationHeight {
    final from = _fromHeight ?? 0;
    final target = _targetHeight ?? from;
    return from +
        (target - from) * AppMotion.standardCurve.transform(_controller.value);
  }

  void _tick() {
    // forward(from: 0) notifies synchronously when a new target is found during
    // layout. That layout already commits the first frame; later ticks relayout.
    if (!_layingOut) markNeedsLayout();
  }

  @override
  void performLayout() {
    _layingOut = true;
    try {
      child?.layout(constraints, parentUsesSize: true);
      final naturalSize = child?.size ?? constraints.smallest;
      final target = naturalSize.height;
      if (_targetHeight == null) {
        _fromHeight = _targetHeight = target;
      } else if (target != _targetHeight) {
        _fromHeight = _presentationHeight;
        _targetHeight = target;
        _controller.forward(from: 0);
      }
      size =
          constraints.constrain(Size(naturalSize.width, _presentationHeight));
      _overflow = naturalSize.height > size.height;
    } finally {
      _layingOut = false;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_overflow) {
      _clipLayer.layer = context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        super.paint,
        clipBehavior: Clip.hardEdge,
        oldLayer: _clipLayer.layer,
      );
    } else {
      _clipLayer.layer = null;
      super.paint(context, offset);
    }
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) =>
      _overflow ? Offset.zero & size : null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    if (_controller.value < 1) _controller.forward();
  }

  @override
  void detach() {
    _controller.stop();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _controller.dispose();
    super.dispose();
  }
}
