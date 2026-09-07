import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Canonical glyphs for the small actions repeated by lists and toolbars.
///
/// Keeping the mapping here prevents one page from falling back to a plain
/// equals sign, a thin play triangle, or a differently weighted overflow icon.
enum AppActionGlyph {
  reorder,
  play,
  moreVertical,
  moreHorizontal;

  IconData get icon => switch (this) {
        AppActionGlyph.reorder => Symbols.drag_handle,
        AppActionGlyph.play => Symbols.play_circle,
        AppActionGlyph.moreVertical => Symbols.more_vert,
        AppActionGlyph.moreHorizontal => Symbols.more_horiz,
      };
}

/// One Material Symbols presentation for action glyphs used in both labelled
/// controls and icon-only controls.
class AppActionIcon extends StatelessWidget {
  const AppActionIcon(
    this.glyph, {
    super.key,
    this.size = 22,
  });

  final AppActionGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) => Icon(
        glyph.icon,
        size: size,
        // A filled play circle has a stable visual centre. The remaining
        // outlined symbols keep the same stroke weight and optical size.
        fill: glyph == AppActionGlyph.play ? 1 : 0,
        weight: glyph == AppActionGlyph.reorder ? 520 : 480,
        opticalSize: 24,
      );
}

/// Shared 44 logical-pixel icon action for playlist/list surfaces.
///
/// IconButton supplies keyboard activation, focus, hover and tooltip
/// semantics. This wrapper only unifies size, shape, colours and animation;
/// callers continue to own menu, playback and reorder behaviour.
class AppIconActionButton extends StatelessWidget {
  const AppIconActionButton({
    super.key,
    required this.tooltip,
    required this.glyph,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final AppActionGlyph glyph;
  final VoidCallback? onPressed;
  final bool selected;

  bool _reduceMotion(BuildContext context) {
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      visualDensity: VisualDensity.standard,
      padding: EdgeInsets.zero,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.square(44)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const WidgetStatePropertyAll(AppShape.control),
        animationDuration:
            _reduceMotion(context) ? Duration.zero : AppMotion.quick,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return scheme.onSurface.withValues(alpha: .38);
          }
          return selected ? scheme.onSecondaryContainer : scheme.primary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (selected) return scheme.secondaryContainer;
          if (states.contains(WidgetState.pressed)) {
            return scheme.surfaceContainerHighest.withValues(alpha: .72);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return scheme.surfaceContainerHighest.withValues(alpha: .48);
          }
          return Colors.transparent;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return scheme.primary.withValues(alpha: .13);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return scheme.primary.withValues(alpha: .08);
          }
          return Colors.transparent;
        }),
      ),
      icon: AppActionIcon(glyph),
    );
  }
}
