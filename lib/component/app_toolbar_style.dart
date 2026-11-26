import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

const appToolbarIconSize = 20.0;
const appToolbarLabelGap = 8.0;
const appToolbarTrailingGap = 4.0;
const appToolbarPadding = EdgeInsets.symmetric(horizontal: 13, vertical: 10);

/// One centered icon/label group for every toolbar button. Using the plain
/// button constructors avoids their icon factories' scale-dependent gaps.
class AppToolbarLabel extends StatelessWidget {
  const AppToolbarLabel({
    super.key,
    required this.label,
    required this.icon,
    this.trailing,
    this.labelKey,
    this.semanticsLabel,
  });

  final String label;
  final IconData icon;
  final Widget? trailing;
  final Key? labelKey;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: appToolbarIconSize),
          const SizedBox(width: appToolbarLabelGap),
          Flexible(
            child: Text(label,
                key: labelKey,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                semanticsLabel: semanticsLabel ?? label),
          ),
          if (trailing != null) ...[
            const SizedBox(width: appToolbarTrailingGap),
            trailing!,
          ],
        ],
      );
}

bool appToolbarReduceMotion(BuildContext context,
    {MotionKind kind = MotionKind.feedback}) {
  final features =
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
  return (!AppMotion.enabled(context, kind)) ||
      features.disableAnimations ||
      features.reduceMotion ||
      !TickerMode.valuesOf(context).enabled;
}

double appToolbarControlHeight(BuildContext context) {
  // A shared measured line gives text and icon buttons equal *painted* heights
  // even with desktop compact density, custom fonts, and 200% accessibility.
  final baseStyle = Theme.of(context).textTheme.labelLarge;
  final painter = TextPainter(
    text: TextSpan(
      text: ui("新建歌单 播放全部 自定义 移除所选 Ag（0123）"),
      style: baseStyle?.copyWith(fontWeight: FontWeight.w600),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = math.max(
      44.0, painter.height.ceilToDouble() + appToolbarPadding.vertical);
  painter.dispose();
  return height;
}

ButtonStyle appToolbarControlStyle(BuildContext context,
    {bool? reduced,
    bool primary = false,
    bool tonal = false,
    bool destructive = false,
    bool iconOnly = false}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final isDark = scheme.brightness == Brightness.dark;
  final foreground = destructive
      ? scheme.onError
      : tonal
          ? scheme.onSecondaryContainer
          : scheme.onPrimary;
  final height = appToolbarControlHeight(context);
  final labelStyle =
      (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.w600,
  );
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(iconOnly ? height : 44, height)),
    fixedSize:
        iconOnly ? WidgetStatePropertyAll(Size.square(height)) : null,
    visualDensity: VisualDensity.standard,
    iconSize: const WidgetStatePropertyAll(appToolbarIconSize),
    padding:
        WidgetStatePropertyAll(iconOnly ? EdgeInsets.zero : appToolbarPadding),
    alignment: Alignment.center,
    shape: const WidgetStatePropertyAll(AppShape.pill),
    elevation: const WidgetStatePropertyAll(0),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    animationDuration: (reduced ?? appToolbarReduceMotion(context))
        ? Duration.zero
        : AppMotion.quick,
    textStyle: WidgetStatePropertyAll(labelStyle),
    side: primary
        ? const WidgetStatePropertyAll(BorderSide.none)
        : WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .24),
              );
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return BorderSide(
                color: scheme.primary.withValues(alpha: .38),
              );
            }
            return BorderSide(
              color:
                  scheme.outlineVariant.withValues(alpha: isDark ? .38 : .46),
            );
          }),
    backgroundColor: primary
        ? WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurface.withValues(alpha: .12);
            }
            if (destructive) return scheme.error;
            if (tonal) return scheme.secondaryContainer;
            return scheme.primary;
          })
        : WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerLow.withValues(alpha: .42);
            }
            if (states.contains(WidgetState.pressed)) {
              return scheme.secondaryContainer.withValues(alpha: .72);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.secondaryContainer
                  .withValues(alpha: isDark ? .42 : .55);
            }
            return scheme.surfaceContainerLow;
          }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.onSurface.withValues(alpha: .38);
      }
      if (primary) return foreground;
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed)) {
        return scheme.primary;
      }
      return scheme.onSurface;
    }),
    iconColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return scheme.onSurface.withValues(alpha: .38);
      }
      if (primary) return foreground;
      return scheme.primary;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      final color = primary ? foreground : scheme.primary;
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: .12);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return color.withValues(alpha: .06);
      }
      return Colors.transparent;
    }),
  );
}
