import 'package:dan_player/component/brand_logo.dart';
import 'package:flutter/material.dart';

/// A quiet signature below the support row, without an extra card or background.
class AboutBrand extends StatelessWidget {
  const AboutBrand({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(0.0, 216.0);
          return Center(
            child: BrandLogo(
              brand: AppBrand.rce,
              width: width,
              height: width * 679 / 1104,
            ),
          );
        },
      ),
    );
  }
}
