import 'package:flutter/material.dart';

import 'app_scrollbar.dart';

/// A fading overlay scrollbar for main list/grid content.
///
/// It preserves the full viewport width without adding a scrollbar gutter.
/// The builder must attach the supplied controller to its one vertical view.
class AppContentScrollbar extends StatefulWidget {
  const AppContentScrollbar({
    super.key,
    this.controller,
    required this.builder,
  });

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
      // automatically inserted desktop scrollbar over the same content.
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
        child: AppScrollbar(
          controller: controller,
          child: widget.builder(context, controller),
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
