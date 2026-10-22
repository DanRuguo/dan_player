import 'package:dan_player/library/album_identity.dart';

/// Optional native mixing. The default retains the existing output path.
enum PlaybackTransitionMode { standard, gapless, crossfade }

class PlaybackTransitionPreferences {
  const PlaybackTransitionPreferences({
    this.mode = PlaybackTransitionMode.standard,
    this.crossfadeSeconds = 3,
    this.skipSameAlbumCrossfade = false,
  });

  final PlaybackTransitionMode mode;
  final double crossfadeSeconds;
  final bool skipSameAlbumCrossfade;
  bool get enabled => mode != PlaybackTransitionMode.standard;

  /// Unknown album titles/owners cannot establish a shared release. Reuse the
  /// library identity, including its album-artist fallback, without guessing
  /// from filenames, folders or track/disc numbers.
  bool allowsCrossfade(AlbumIdentity current, AlbumIdentity next) =>
      !skipSameAlbumCrossfade ||
      current.title == null ||
      current.owner == null ||
      next.title == null ||
      next.owner == null ||
      current.id != next.id;

  static double safeSeconds(Object? value) {
    final number = value is num ? value.toDouble() : 3.0;
    return number.isFinite ? number.clamp(0.5, 12).toDouble() : 3.0;
  }

  factory PlaybackTransitionPreferences.fromJson(Object? value) {
    if (value is! Map) return const PlaybackTransitionPreferences();
    final modes =
        PlaybackTransitionMode.values.where((m) => m.name == value['mode']);
    return PlaybackTransitionPreferences(
      mode: modes.isEmpty ? PlaybackTransitionMode.standard : modes.first,
      crossfadeSeconds: safeSeconds(value['crossfadeSeconds']),
      skipSameAlbumCrossfade: value['skipSameAlbumCrossfade'] == true,
    );
  }

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'crossfadeSeconds': safeSeconds(crossfadeSeconds),
        'skipSameAlbumCrossfade': skipSameAlbumCrossfade,
      };

  PlaybackTransitionPreferences copyWith(
          {PlaybackTransitionMode? mode,
          double? crossfadeSeconds,
          bool? skipSameAlbumCrossfade}) =>
      PlaybackTransitionPreferences(
          mode: mode ?? this.mode,
          crossfadeSeconds:
              safeSeconds(crossfadeSeconds ?? this.crossfadeSeconds),
          skipSameAlbumCrossfade:
              skipSameAlbumCrossfade ?? this.skipSameAlbumCrossfade);

  @override
  bool operator ==(Object other) =>
      other is PlaybackTransitionPreferences &&
      mode == other.mode &&
      crossfadeSeconds == other.crossfadeSeconds &&
      skipSameAlbumCrossfade == other.skipSameAlbumCrossfade;
  @override
  int get hashCode =>
      Object.hash(mode, crossfadeSeconds, skipSameAlbumCrossfade);
}
