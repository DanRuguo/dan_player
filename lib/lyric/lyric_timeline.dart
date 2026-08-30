import 'package:dan_player/lyric/lyric.dart';

/// Returns the lyric line that should be active at [position].
///
/// The search uses the last line whose start time is not after the current
/// playback position. Before the first timestamp we intentionally select the
/// first line so a newly opened lyric surface always has a stable anchor.
int findCurrentLyricLineIndex(List<LyricLine> lines, Duration position) {
  if (lines.isEmpty) return -1;

  var low = 0;
  var high = lines.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (lines[middle].start <= position) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  return (low - 1).clamp(0, lines.length - 1);
}
