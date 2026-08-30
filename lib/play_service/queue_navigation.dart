import 'package:dan_player/library/audio_library.dart';

/// Locate a track in the current queue, keeping a duplicate's position only
/// while the old index still points to that track. Queues can change while an
/// online source is opening, so a saved numeric index alone is not safe.
int queueIndexForTrack(List<Audio> queue, String? trackPath,
    {int? preferredIndex}) {
  if (trackPath == null) return -1;
  if (preferredIndex != null &&
      preferredIndex >= 0 &&
      preferredIndex < queue.length &&
      queue[preferredIndex].path == trackPath) {
    return preferredIndex;
  }
  return queue.indexWhere((audio) => audio.path == trackPath);
}

/// Map a saved occurrence through a path-only filter. A path can appear in
/// multiple branches of a nested playlist; indexWhere(path) would wrongly
/// select its first occurrence. Count retained entries before the saved one
/// instead, using the same predicate that constructs the restored queue.
///
/// -1 means the saved occurrence is unavailable/invalid, so the caller must
/// choose an explicit fallback and must not reuse that song's saved position.
int queueIndexAfterFiltering(
  List<String> savedPaths,
  int savedIndex, {
  required bool Function(String path) keepPath,
}) {
  if (savedIndex < 0 ||
      savedIndex >= savedPaths.length ||
      !keepPath(savedPaths[savedIndex])) {
    return -1;
  }
  var filteredIndex = 0;
  for (var index = 0; index < savedIndex; index++) {
    if (keepPath(savedPaths[index])) filteredIndex++;
  }
  return filteredIndex;
}
