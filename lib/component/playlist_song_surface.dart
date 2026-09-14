import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/cover_caption_colors.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:flutter/material.dart';

/// Visible song cards share the bounded artwork/caption cache. No polling and
/// no full-size image decode is added for card backgrounds.
class PlaylistSongSurface extends StatefulWidget {
  const PlaylistSongSurface(
      {super.key,
      required this.audio,
      required this.artworkColors,
      required this.child,
      this.loadArtwork = true});
  final Audio audio;
  final bool artworkColors, loadArtwork;
  final Widget child;
  @override
  State<PlaylistSongSurface> createState() => _PlaylistSongSurfaceState();
}

class _PlaylistSongSurfaceState extends State<PlaylistSongSurface> {
  Object? _key;
  Future<CoverCaptionColors?>? _colors;
  Object? _surfaceKey;
  late ColorScheme _scheme;
  late Color _surface;
  @override
  Widget build(BuildContext context) {
    final key = (
      widget.audio.path,
      widget.audio.modified,
      widget.audio.coverFingerprint,
      widget.loadArtwork
    );
    if (_key != key) {
      _key = key;
      _colors = widget.loadArtwork
          ? widget.audio
              .artworkForSize(const ArtworkSize(48, 48))
              .then<CoverCaptionColors?>((image) =>
                  image == null ? null : CoverCaptionCache.resolve(image, 1))
              .catchError((_) => null)
          : Future.value(null);
    }
    return FutureBuilder<CoverCaptionColors?>(
        future: _colors,
        builder: (context, value) {
          final theme = Theme.of(context);
          final original = theme.colorScheme;
          final seed = value.data?.seed ?? original.primary;
          final surfaceKey = (original, seed, widget.artworkColors);
          if (_surfaceKey != surfaceKey) {
            _surfaceKey = surfaceKey;
            _scheme = widget.artworkColors
                ? ColorScheme.fromSeed(
                    seedColor: seed, brightness: Brightness.light)
                : original;
            final brightness = seed.computeLuminance();
            _surface = widget.artworkColors
                ? _scheme.surfaceContainerHighest
                : HSLColor.fromColor(original.primary)
                    .withSaturation(.20)
                    .withLightness(original.brightness == Brightness.dark
                        ? .10 + brightness * .08
                        : .90 + brightness * .06)
                    .toColor();
          }
          return Ink(
              decoration: BoxDecoration(
                  color: _surface, borderRadius: AppShape.controlRadius),
              child: Theme(
                  data: theme.copyWith(colorScheme: _scheme),
                  child: widget.child));
        });
  }
}
