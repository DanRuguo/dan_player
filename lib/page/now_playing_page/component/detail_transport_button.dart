import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:flutter/material.dart';

/// A detail-page treatment. All three controls share the scene's background;
/// the primary action uses its outline and icon size to establish hierarchy.
class DetailTransportButtonStyle extends ButtonStyle {
  const DetailTransportButtonStyle({
    required this.primary,
    required this.scheme,
    bool reducedMotion = false,
  }) : super(
          animationDuration:
              reducedMotion ? Duration.zero : const Duration(milliseconds: 140),
          enableFeedback: true,
          alignment: Alignment.center,
        );

  final bool primary;
  final ColorScheme scheme;

  @override
  WidgetStateProperty<Color?> get backgroundColor =>
      const WidgetStatePropertyAll(Colors.transparent);

  @override
  WidgetStateProperty<Color?> get foregroundColor =>
      WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: .38)
              : scheme.primary);

  @override
  WidgetStateProperty<Color?> get overlayColor =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return scheme.primary.withValues(alpha: .14);
        }
        if (states.contains(WidgetState.focused)) {
          return scheme.primary.withValues(alpha: .12);
        }
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: .08);
        }
        return Colors.transparent;
      });

  @override
  WidgetStateProperty<BorderSide?> get side =>
      WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.disabled)
                ? scheme.onSurface.withValues(alpha: .20)
                : scheme.primary.withValues(
                    alpha: primary || states.contains(WidgetState.focused)
                        ? 1
                        : .72),
            width: states.contains(WidgetState.focused)
                ? 2.2
                : primary
                    ? 1.8
                    : 1.25,
          ));

  @override
  WidgetStateProperty<OutlinedBorder> get shape =>
      const WidgetStatePropertyAll(AppShape.control);

  @override
  WidgetStateProperty<Size> get minimumSize =>
      WidgetStatePropertyAll(Size.square(primary ? 64 : 56));

  @override
  WidgetStateProperty<double> get iconSize =>
      WidgetStatePropertyAll(primary ? 32 : 28);

  @override
  WidgetStateProperty<EdgeInsetsGeometry> get padding =>
      const WidgetStatePropertyAll(EdgeInsets.all(12));

  @override
  WidgetStateProperty<double> get elevation => const WidgetStatePropertyAll(0);

  @override
  WidgetStateProperty<Color> get shadowColor =>
      const WidgetStatePropertyAll(Colors.transparent);

  @override
  WidgetStateProperty<Color> get surfaceTintColor =>
      const WidgetStatePropertyAll(Colors.transparent);
}

class DetailTransportButton extends StatelessWidget {
  const DetailTransportButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.buffering = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    final reduced = LyricMotion.reducedOf(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: buffering ? null : onPressed,
      style: DetailTransportButtonStyle(
          primary: primary,
          scheme: Theme.of(context).colorScheme,
          reducedMotion: reduced),
      icon: AnimatedSwitcher(
        duration: reduced ? Duration.zero : const Duration(milliseconds: 140),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: buffering
            ? SizedBox.square(
                key: const ValueKey('buffering'),
                dimension: 24,
                child: reduced
                    ? const Icon(Icons.hourglass_top_rounded, size: 24)
                    : const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, key: ValueKey(icon)),
      ),
    );
  }
}
