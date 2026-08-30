import 'package:flutter/material.dart';

enum AppBrand { rce, danRuguo }

/// Theme-aware, transparent brand artwork shared by startup and About.
///
/// No backing colour is painted here: transparent pixels always show the
/// surrounding surface, including custom/dynamic themes.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.brand,
    required this.width,
    this.height,
    this.imageProvider,
  });

  static const rceLightAsset = 'assets/images/RCE_logo_transparent.png';
  static const rceDarkAsset = 'assets/images/RCE_logo_white.png';
  static const danRuguoLightAsset = 'assets/branding/danruguo_light.png';
  static const danRuguoDarkAsset = 'assets/branding/danruguo_dark.png';

  final AppBrand brand;
  final double width;
  final double? height;

  /// Allows previews and tests to provide decoded or deliberately missing art.
  final ImageProvider? imageProvider;

  String get label => switch (brand) {
        AppBrand.rce => 'RCE',
        AppBrand.danRuguo => 'DanRuguo',
      };

  static String assetFor(AppBrand brand, Brightness brightness) =>
      switch ((brand, brightness)) {
        (AppBrand.rce, Brightness.light) => rceLightAsset,
        (AppBrand.rce, Brightness.dark) => rceDarkAsset,
        (AppBrand.danRuguo, Brightness.light) => danRuguoLightAsset,
        (AppBrand.danRuguo, Brightness.dark) => danRuguoDarkAsset,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      image: true,
      child: ExcludeSemantics(
        child: Image(
          image: imageProvider ?? AssetImage(assetFor(brand, theme.brightness)),
          width: width,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
