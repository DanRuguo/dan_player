import 'dart:io';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Custom playlist art takes precedence. A missing or temporarily unavailable
/// image falls back for display without erasing the user's persisted path.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    this.size = 48,
    this.loadSongArtwork = true,
  });

  final Playlist playlist;
  final double size;
  final bool loadSongArtwork;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.queue_music,
                size: size * .58, color: scheme.primary),
          ),
        );
    Widget songArt() {
      if (!loadSongArtwork) return placeholder();
      final Audio? firstSong = playlist.firstAudioOrNull;
      if (firstSong == null) return placeholder();
      return AudioArtwork(
        audio: firstSong,
        size: size,
        placeholder: placeholder(),
      );
    }

    final path = playlist.imagePath;
    return Semantics(
      image: true,
      label: ui("{0}的歌单封面", [playlist.name]),
      child: SizedBox.square(
        dimension: size,
        child: ClipRRect(
          borderRadius: AppShape.smallRadius,
          child: path == null || path.isEmpty
              ? songArt()
              : ArtworkImage(
                  image: FileImage(File(path)),
                  size: size,
                  revision: playlist.modifiedAt,
                  errorBuilder: (_, __, ___) => songArt(),
                ),
        ),
      ),
    );
  }
}
