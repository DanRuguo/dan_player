import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Shared desktop policy for the player, lyrics and independent palette window.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

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
        final reduced = MediaQuery.disableAnimationsOf(context) ||
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
