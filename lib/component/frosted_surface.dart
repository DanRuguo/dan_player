import 'dart:ui';

import 'package:flutter/material.dart';

class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16.0)),
    this.padding = EdgeInsets.zero,
    this.blur = 20.0,
    this.tintColor,
    this.borderColor,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tintColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tint = tintColor ??
        (isDark
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.58)
            : scheme.surface.withValues(alpha: 0.74));
    final outline = borderColor ??
        scheme.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.56);
    final shadows = boxShadow ??
        [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: isDark ? 0.28 : 0.14),
            blurRadius: 24.0,
            offset: const Offset(0.0, 12.0),
          ),
        ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tint,
              borderRadius: borderRadius,
              border: Border.all(color: outline),
            ),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
