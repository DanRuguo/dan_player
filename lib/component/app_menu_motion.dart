import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_menu_surface.dart';
import 'package:dan_player/component/app_scrollbar.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:flutter/material.dart';

/// PopupRoute applies additional Intervals to its curve. Keep it monotonic so
/// the last item does not disappear during a rebound; anchored menus below
/// animate their complete surface and can rebound without delaying labels.
AnimationStyle appMenuAnimationStyle(BuildContext context,
        {bool reduced = false}) =>
    reduced || appToolbarReduceMotion(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AppMotion.emphasized,
            reverseDuration: AppMotion.quick,
            curve: AppMotion.standardCurve,
            reverseCurve: Curves.easeInCubic,
          );

/// Keep Material's menu positioning, focus, dismissal and submenu chain. Its
/// shell is transparent; the bounded inner panel owns the visible surface and
/// scrolling, so a long menu's rounded surface never scrolls with its items.
MenuStyle appMenuShellStyle(BuildContext context, MenuStyle? style) {
  final density = style?.visualDensity ??
      MenuTheme.of(context).style?.visualDensity ??
      Theme.of(context).visualDensity;
  // Material adds positive horizontal density after resolving menu padding.
  // Cancel that shell-only inset; the visible panel applies it exactly once.
  final inset = math.max(0.0, density.baseSizeAdjustment.dx);
  return (style ?? const MenuStyle()).copyWith(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: const WidgetStatePropertyAll(BorderSide.none),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: -inset)),
  );
}

class AppMenuPanel extends StatefulWidget {
  const AppMenuPanel({
    super.key,
    required this.children,
    this.style,
    this.useRootOverlay = false,
    this.reservedPadding = EdgeInsets.zero,
  });

  final List<Widget> children;
  final MenuStyle? style;
  final bool useRootOverlay;
  final EdgeInsetsGeometry reservedPadding;

  /// Material cascades every submenu into its top-level menu's overlay,
  /// regardless of the submenu's own requested overlay. Keep the visible
  /// panel's height bound in that same coordinate space.
  static bool resolveRootOverlay(BuildContext context, bool requested) =>
      context
          .dependOnInheritedWidgetOfExactType<_MenuOverlayScope>()
          ?.useRootOverlay ??
      requested;

  /// A submenu must measure a resting parent, not an intermediate scale.
  static void settleAncestor(BuildContext context) =>
      context.findAncestorStateOfType<_AppMenuPanelState>()?._settle();

  @override
  State<AppMenuPanel> createState() => _AppMenuPanelState();
}

class _AppMenuPanelState extends State<AppMenuPanel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _motion =
      AnimationController(vsync: this, duration: AppMotion.emphasized);
  final _scroll = ScrollController();
  bool _started = false;
  AppLifecycleState? _lifecycle;

  bool get _hidden =>
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  void _settle() => _motion.value = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hidden || appToolbarReduceMotion(context)) {
      _settle();
    } else if (!_started) {
      _motion.forward();
    }
    _started = true;
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (appToolbarReduceMotion(context)) _settle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (_hidden) _settle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? const MenuStyle();
    final themeStyle = MenuTheme.of(context).style ?? const MenuStyle();
    T? resolve<T>(WidgetStateProperty<T?>? Function(MenuStyle) property) =>
        property(style)?.resolve({}) ?? property(themeStyle)?.resolve({});
    final direction = Directionality.of(context);
    final density =
        style.visualDensity ?? themeStyle.visualDensity ?? theme.visualDensity;
    final padding =
        (resolve((s) => s.padding) ?? const EdgeInsets.symmetric(vertical: 8))
            .add(EdgeInsets.symmetric(
                horizontal: math.max(0, density.baseSizeAdjustment.dx)))
            .resolve(direction);
    final overlay = Overlay.of(context, rootOverlay: widget.useRootOverlay)
        .context
        .findRenderObject() as RenderBox;
    final overlayHeight = overlay.hasSize
        ? overlay.size.height
        : MediaQuery.sizeOf(context).height;
    final minimum = resolve((s) => s.minimumSize);
    final maximum = resolve((s) => s.maximumSize);
    final fixed = resolve((s) => s.fixedSize);
    var constraints = density.effectiveConstraints(BoxConstraints(
      minWidth: minimum?.width ?? 0,
      minHeight: minimum?.height ?? 0,
      maxWidth: maximum?.width ?? double.infinity,
      maxHeight: maximum?.height ?? double.infinity,
    ));
    if (fixed != null) {
      final size = constraints.constrain(fixed);
      constraints = constraints.copyWith(
        minWidth: size.width.isFinite ? size.width : null,
        maxWidth: size.width.isFinite ? size.width : null,
        minHeight: size.height.isFinite ? size.height : null,
        maxHeight: size.height.isFinite ? size.height : null,
      );
    }
    final height = math.max(
        0.0,
        math.min(
            constraints.maxHeight,
            overlayHeight -
                widget.reservedPadding.resolve(direction).vertical));
    constraints = constraints.copyWith(
        minHeight: math.min(constraints.minHeight, height), maxHeight: height);
    final shape = (resolve((s) => s.shape) ??
            const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4))))
        .copyWith(side: resolve((s) => s.side));
    final panel = AppMenuSurface(
      color: resolve((s) => s.backgroundColor) ??
          theme.colorScheme.surfaceContainer,
      surfaceTintColor:
          resolve((s) => s.surfaceTintColor) ?? Colors.transparent,
      shadowColor: resolve((s) => s.shadowColor) ?? theme.colorScheme.shadow,
      elevation: resolve((s) => s.elevation) ?? 3,
      shape: shape,
      child: ConstrainedBox(
        constraints: constraints,
        child: Padding(
          padding: padding,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                overscroll: false,
                physics: const ClampingScrollPhysics()),
            child: PrimaryScrollController(
              controller: _scroll,
              child: AppScrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return _MenuOverlayScope(
      useRootOverlay: widget.useRootOverlay,
      child: AnimatedBuilder(
        animation: _motion,
        child: panel,
        builder: (context, child) {
          // Keep the resting rectangle exact. Bounded scaling cannot cross a
          // screen edge, even when Material flips a submenu upward or sideways.
          final t = _motion.value;
          final scale = t == 1
              ? 1.0
              : t < .58
                  ? .94 + .06 * Curves.easeOutCubic.transform(t / .58)
                  : t < .78
                      ? 1 - .012 * Curves.easeInOut.transform((t - .58) / .20)
                      : .988 +
                          .012 * Curves.easeOutCubic.transform((t - .78) / .22);
          return Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: (t / .3).clamp(0.0, 1.0),
              alwaysIncludeSemantics: true,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _MenuOverlayScope extends InheritedWidget {
  const _MenuOverlayScope({required this.useRootOverlay, required super.child});

  final bool useRootOverlay;

  @override
  bool updateShouldNotify(_MenuOverlayScope oldWidget) =>
      useRootOverlay != oldWidget.useRootOverlay;
}
