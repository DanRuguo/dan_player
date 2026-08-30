import 'package:flutter/material.dart';

/// A Material scrollbar with its own lane beside main list/grid content.
///
/// The viewport is narrowed instead of padding individual rows, so trailing
/// menus, reorder handles and grid cards all keep the same safe clearance.
/// The builder must attach the supplied controller to its one vertical view.
class AppContentScrollbar extends StatefulWidget {
  const AppContentScrollbar({
    super.key,
    this.controller,
    required this.builder,
  });

  static const gutter = 24.0;
  static const thumbThickness = 6.0;
  static const activeThumbThickness = 8.0;
  static const crossAxisMargin = 4.0;

  final ScrollController? controller;
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  @override
  State<AppContentScrollbar> createState() => _AppContentScrollbarState();
}

class _AppContentScrollbarState extends State<AppContentScrollbar> {
  ScrollController? _ownedController;

  @override
  Widget build(BuildContext context) {
    final controller =
        widget.controller ?? (_ownedController ??= ScrollController());
    final scheme = Theme.of(context).colorScheme;
    return ScrollConfiguration(
      // Keep the app's wheel/touch/trackpad policy, but avoid a second
      // automatically inserted desktop scrollbar inside the reserved lane.
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ScrollbarTheme(
        data: ScrollbarTheme.of(context).copyWith(
          crossAxisMargin: AppContentScrollbar.crossAxisMargin,
          mainAxisMargin: 4,
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.dragged)
                  ? AppContentScrollbar.activeThumbThickness
                  : AppContentScrollbar.thumbThickness),
          thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.dragged)
                  ? scheme.primary.withValues(alpha: .95)
                  : states.contains(WidgetState.hovered)
                      ? scheme.primary.withValues(alpha: .8)
                      : scheme.onSurfaceVariant.withValues(alpha: .5)),
          interactive: true,
        ),
        child: Scrollbar(
          controller: controller,
          thumbVisibility: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
                end: AppContentScrollbar.gutter),
            child: widget.builder(context, controller),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    super.dispose();
  }
}
