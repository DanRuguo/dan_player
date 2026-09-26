import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';

/// Indexed tracks plus virtual CUE tracks explicitly kept in ordinary playlists.
/// This does not import unindexed file references, resolve providers or probe
/// storage. Indexed objects win when the same stable identity is already known.
List<Audio> smartLibraryCandidates(Iterable<Audio> indexed,
    {PlaylistTree? tree}) {
  final result = <Audio>[];
  final seen = <String>{};
  void include(Audio audio) {
    if (seen.add(audio.stableTrackId)) result.add(audio);
  }

  for (final audio in indexed) {
    include(audio);
  }
  for (final playlist in (tree ?? playlistTree).allPlaylists) {
    // Visit each node once. Flattening every ancestor would revisit descendants
    // and unnecessarily expand ordinary missing or online references.
    for (final entry in playlist.entries) {
      final audio = entry.audio;
      if (audio != null && audio.isLocal && audio.isCueTrack) include(audio);
    }
  }
  return List.unmodifiable(result);
}
