import 'package:flutter/material.dart';

enum ScreenType {
  /// width <= 640
  small,

  /// 640 < width < 1100
  medium,

  /// width >= 1100
  large,
}

class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, ScreenType screenType) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // Nested pages must respond to their actual content allocation, not
          // the full native window. This keeps a dragged desktop sidebar from
          // forcing wide layouts into a clipped main pane.
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          if (width <= 640) return builder(context, ScreenType.small);
          if (width < 1100) return builder(context, ScreenType.medium);
          return builder(context, ScreenType.large);
        },
      );
}

class ResponsiveBuilder2 extends StatelessWidget {
  const ResponsiveBuilder2({super.key, required this.builder});

  final Widget Function(BuildContext context, ScreenType screenType) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          return builder(
            context,
            width <= 928 ? ScreenType.small : ScreenType.large,
          );
        },
      );
}
