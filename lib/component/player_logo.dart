import 'package:flutter/material.dart';

/// The player emblem, distinct from the RCE and DanRuguo startup signatures.
///
/// Share one theme choice across the title bar, onboarding and splash footer.
/// Decode at the rendered physical size instead of retaining a full-size image
/// for the small title-bar decoration.
class PlayerLogo extends StatelessWidget {
  const PlayerLogo({super.key, this.size = 24});

  static const normalAsset = 'app_icon.ico';
  static const darkAsset = 'app_icon_dark.ico';

  static String assetFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAsset : normalAsset;

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pixels =
        (size * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(1, 256);
    return Image.asset(
      assetFor(theme.brightness),
      width: size,
      height: size,
      cacheWidth: pixels,
      cacheHeight: pixels,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.music_note,
        size: size,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
