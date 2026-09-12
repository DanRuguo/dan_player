import 'dart:ui' as ui;
import 'package:dan_player/component/artwork_handoff.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/material.dart';

/// Filters only this header's artwork. Sampling the route's backdrop instead
/// changes the filter input when Flutter removes its transition opacity layer.
class DetailHeaderBackdrop extends StatelessWidget {
  const DetailHeaderBackdrop({super.key, required this.artwork});
  final Future<ImageProvider?> artwork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blur = RenderingPreferencesScope.of(context).surfaceBlur;
    return IgnorePointer(
        child: ExcludeSemantics(
            child: RepaintBoundary(
      child: Stack(fit: StackFit.expand, children: [
        ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
        ArtworkHandoff(
          artworkKey: artwork,
          loadArtwork: () async {
            final image = await artwork;
            return image == null
                ? null
                : ResizeImage(image,
                    width: 512, height: 512, policy: ResizeImagePolicy.fit);
          },
          placeholder: const SizedBox.expand(),
          imageBuilder: (provider) => ImageFiltered(
            enabled: blur,
            imageFilter: ui.ImageFilter.blur(
                sigmaX: 100, sigmaY: 100, tileMode: ui.TileMode.clamp),
            child: Image(
                image: provider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.expand()),
          ),
        ),
        ColoredBox(
            color: theme.brightness == Brightness.dark
                ? Colors.black38
                : Colors.white30),
      ]),
    )));
  }
}
