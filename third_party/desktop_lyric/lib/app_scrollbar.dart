import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_motion.dart';

/// Shared desktop policy for the player, lyrics and independent palette window.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      _AppEdgeStretch(
          direction: details.direction,
          controller: details.controller,
          child: child);

  @override
  Widget buildScrollbar(
      BuildContext context, Widget child, ScrollableDetails details) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) return child;
    return switch (getPlatform(context)) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS =>
        AppScrollbar(
            controller: details.controller,
            suppressAutomaticScrollbar: false,
            child: child),
      _ => child,
    };
  }
}

/// Flutter owns the overscroll notification, transform and finite spring.
/// Wheel signals at a clamped edge do not produce Flutter overscroll
/// notifications. Adapt that otherwise unhandled input to the same native
/// finite pull/spring as touch, without changing scroll positions or gestures.
class _AppEdgeStretch extends StatefulWidget {
  const _AppEdgeStretch(
      {required this.direction, required this.controller, required this.child});
  final AxisDirection direction;
  final ScrollController? controller;
  final Widget child;
  @override
  State<_AppEdgeStretch> createState() => _AppEdgeStretchState();
}

class _AppEdgeStretchState extends State<_AppEdgeStretch>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  bool get _motionEnabled {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return AppMotion.enabled(context, MotionKind.feedback) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        TickerMode.valuesOf(context).enabled;
  }

  double _delta(PointerScrollEvent event, AxisDirection direction,
      ScrollBehavior behavior) {
    final flip = event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed
            .any(behavior.pointerAxisModifiers.contains);
    final axis = axisDirectionToAxis(direction);
    final delta = (flip ? flipAxis(axis) : axis) == Axis.horizontal
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    return axisDirectionIsReversed(direction) ? -delta : delta;
  }

  bool _canScroll(ScrollPosition position, double delta) =>
      position.hasContentDimensions &&
      position.physics.shouldAcceptUserOffset(position) &&
      (delta < 0
          ? position.pixels > position.minScrollExtent
          : delta > 0 && position.pixels < position.maxScrollExtent);

  bool _ancestorCanScroll(PointerScrollEvent event, ScrollPosition own) {
    var canScroll = false;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        final position = state.position;
        if (!identical(position, own)) {
          final behavior =
              state.widget.scrollBehavior ?? ScrollConfiguration.of(element);
          final delta = _delta(event, position.axisDirection, behavior);
          if (_canScroll(position, delta)) {
            canScroll = true;
            return false;
          }
        }
      }
      return true;
    });
    return canScroll;
  }

  void _onSignal(PointerSignalEvent signal, BuildContext nativeContext) {
    if (signal is! PointerScrollEvent || !_motionEnabled) return;
    final positions = widget.controller?.positions;
    if (positions == null || positions.length != 1) {
      return;
    }
    final position = positions.single;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position) ||
        // A view may accumulate wheel destinations while animateTo is still
        // at its old edge. Let that active scroll owner resolve/reverse its
        // pending movement before starting visual-only edge feedback.
        position.isScrollingNotifier.value ||
        position.viewportDimension <= 0) {
      return;
    }
    final delta =
        _delta(signal, widget.direction, ScrollConfiguration.of(context));
    if (delta == 0 ||
        _canScroll(position, delta) ||
        _ancestorCanScroll(signal, position)) {
      return;
    }

    // Descendant scrollables register first. Only the deepest otherwise
    // unhandled edge wins, and a parent with available extent keeps its wheel.
    GestureBinding.instance.pointerSignalResolver.register(signal, (event) {
      if (!mounted || !nativeContext.mounted || !_motionEnabled) return;
      final pull = delta.clamp(
          -position.viewportDimension * .25, position.viewportDimension * .25);
      _WheelEdgeOverscroll(
              metrics: position,
              context: nativeContext,
              overscroll: pull,
              dragDetails: DragUpdateDetails(
                  globalPosition: signal.position,
                  delta: axisDirectionToAxis(widget.direction) == Axis.vertical
                      ? Offset(0, -pull)
                      : Offset(-pull, 0),
                  primaryDelta: -pull))
          .dispatch(nativeContext);
      _WheelEdgeEnd(metrics: position, context: nativeContext)
          .dispatch(nativeContext);
      signal.respond(allowPlatformDefault: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _motionEnabled
        ? NotificationListener<ScrollNotification>(
            // The adapter's visual-only notifications must not masquerade as
            // movement in parent views, scrollbars or application listeners.
            onNotification: (notification) =>
                notification is _WheelEdgeOverscroll ||
                notification is _WheelEdgeEnd,
            child: StretchingOverscrollIndicator(
                axisDirection: widget.direction,
                child: Builder(
                    builder: (nativeContext) => Listener(
                        onPointerSignal: (event) =>
                            _onSignal(event, nativeContext),
                        child: widget.child))))
        : widget.child;
  }
}

class _WheelEdgeOverscroll extends OverscrollNotification {
  _WheelEdgeOverscroll(
      {required super.metrics,
      required super.context,
      required super.overscroll,
      required super.dragDetails});
}

class _WheelEdgeEnd extends ScrollEndNotification {
  _WheelEdgeEnd({required super.metrics, required super.context});
}

/// An idle-fading scrollbar that retains Flutter's native scroll gestures.
///
/// Hovering the thumb lane reveals it again, including when fully faded. The
/// underlying painter suppresses bars for content with no scroll extent.
class AppScrollbar extends RawScrollbar {
  const AppScrollbar({
    super.key,
    required super.child,
    super.controller,
    super.interactive = true,
    super.notificationPredicate,
    super.scrollbarOrientation,
    this.suppressAutomaticScrollbar = true,
  }) : super(
          thumbVisibility: false,
          fadeDuration: AppMotion.standard,
          timeToFade: idleDelay,
        );

  static const idleDelay = Duration(milliseconds: 900);

  /// Explicit wrappers replace their view's automatic scrollbar. A scrollbar
  /// inserted by ScrollBehavior must still allow independent nested views.
  final bool suppressAutomaticScrollbar;

  @override
  RawScrollbarState<AppScrollbar> createState() => _AppScrollbarState();
}

class _AppScrollbarState extends RawScrollbarState<AppScrollbar>
    with WidgetsBindingObserver {
  bool _hovered = false;
  bool _dragged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.suppressAutomaticScrollbar
      ? ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: super.build(context),
        )
      : super.build(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => _updateMotion();

  void _updateMotion() {
    // RawScrollbar exposes its painter animation for customization. Retain its
    // gesture/idle lifecycle while applying the same motion as other controls.
    final animation = scrollbarPainter.fadeoutOpacityAnimation;
    if (animation is CurvedAnimation) {
      animation.curve = AppMotion.standardCurve;
      final controller = animation.parent;
      if (controller is AnimationController) {
        final features =
            WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
        final reduced = !AppMotion.enabled(context, MotionKind.feedback) ||
            features.disableAnimations ||
            features.reduceMotion;
        controller.duration = reduced ? Duration.zero : AppMotion.standard;
      }
    }
  }

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    final scheme = Theme.of(context).colorScheme;
    final theme = ScrollbarTheme.of(context);
    final states = <WidgetState>{
      if (_hovered) WidgetState.hovered,
      if (_dragged) WidgetState.dragged,
    };
    scrollbarPainter
      ..color = theme.thumbColor?.resolve(states) ??
          (_dragged
              ? scheme.primary.withValues(alpha: .95)
              : _hovered
                  ? scheme.primary.withValues(alpha: .8)
                  : scheme.onSurfaceVariant.withValues(alpha: .5))
      ..thickness =
          theme.thickness?.resolve(states) ?? (_hovered || _dragged ? 8 : 6)
      ..radius = theme.radius ?? const Radius.circular(8)
      ..crossAxisMargin = theme.crossAxisMargin ?? 2
      ..mainAxisMargin = theme.mainAxisMargin ?? 4
      ..minLength = theme.minThumbLength ?? 36;
  }

  @override
  void handleThumbPressStart(Offset localPosition) {
    super.handleThumbPressStart(localPosition);
    setState(() => _dragged = true);
  }

  @override
  void handleThumbPressEnd(Offset localPosition, Velocity velocity) {
    super.handleThumbPressEnd(localPosition, velocity);
    setState(() => _dragged = false);
  }

  @override
  void handleHover(PointerHoverEvent event) {
    super.handleHover(event);
    final hovered =
        isPointerOverScrollbar(event.position, event.kind, forHover: true);
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  void handleHoverExit(PointerExitEvent event) {
    super.handleHoverExit(event);
    if (_hovered) setState(() => _hovered = false);
  }
}
