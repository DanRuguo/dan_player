import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

const appToolbarIconSize = 20.0;
const appToolbarLabelGap = 8.0;
const appToolbarTrailingGap = 4.0;
const appToolbarPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);

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

bool appToolbarReduceMotion(BuildContext context) {
  final features =
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
  return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
      features.disableAnimations ||
      features.reduceMotion ||
      !TickerMode.valuesOf(context).enabled;
}

double appToolbarControlHeight(BuildContext context) {
  // A shared measured line gives text and icon buttons equal *painted* heights
  // even with desktop compact density, custom fonts, and 200% accessibility.
  final painter = TextPainter(
    text: TextSpan(
      text: ui("新建歌单 播放全部 自定义 移除所选 Ag（0123）"),
      style: Theme.of(context).textTheme.labelLarge,
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
  final scheme = Theme.of(context).colorScheme;
  final foreground = destructive
      ? scheme.onError
      : tonal
          ? scheme.onSecondaryContainer
          : scheme.onPrimary;
  final height = appToolbarControlHeight(context);
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(44, height)),
    fixedSize: WidgetStatePropertyAll(
        Size(iconOnly ? height : double.infinity, height)),
    visualDensity: VisualDensity.standard,
    iconSize: const WidgetStatePropertyAll(appToolbarIconSize),
    padding:
        WidgetStatePropertyAll(iconOnly ? EdgeInsets.zero : appToolbarPadding),
    alignment: Alignment.center,
    shape: const WidgetStatePropertyAll(AppShape.control),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    animationDuration: (reduced ?? appToolbarReduceMotion(context))
        ? Duration.zero
        : AppMotion.quick,
    textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelLarge),
    side: primary
        ? null
        : WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? scheme.outlineVariant.withValues(alpha: .32)
                  : scheme.outlineVariant.withValues(alpha: .7),
            )),
    backgroundColor: primary
        ? destructive
            ? WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled) ? null : scheme.error)
            : null
        : WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? Colors.transparent
                : states.contains(WidgetState.hovered)
                    ? scheme.surfaceContainerHighest.withValues(alpha: .45)
                    : Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: .38)
            : primary
                ? foreground
                : scheme.primary),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      final color = primary ? foreground : scheme.primary;
      if (states.contains(WidgetState.pressed)) {
        return color.withValues(alpha: .13);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return color.withValues(alpha: .08);
      }
      return Colors.transparent;
    }),
  );
}
