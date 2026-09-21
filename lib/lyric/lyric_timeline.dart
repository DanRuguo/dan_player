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

/// Authored overlaps can keep the previous voice singing after the next line
/// starts. Cache ends once; each frame examines only the nearby visual band.
/// Tiny provider timing overlaps do not turn ordinary handoffs into duets.
class LyricOverlapTimeline {
  LyricOverlapTimeline(this.lines)
      : ends = [
          for (final line in lines)
            if (line is SyncLyricLine && line.content.trim().isNotEmpty)
              line.words.fold<Duration>(
                  line.start + line.length,
                  (end, word) => word.start + word.length > end
                      ? word.start + word.length
                      : end)
            else
              null
        ];
  final List<LyricLine> lines;
  final List<Duration?> ends;

  Set<int> activeIndices(Duration position, int anchor) {
    if (anchor < 0 || anchor >= lines.length) return const {};
    final result = <int>{anchor};
    for (var i = anchor - 1; i >= 0 && i >= anchor - 24; i--) {
      final end = ends[i];
      if (end != null &&
          lines[i].start <= position &&
          end > position &&
          end - lines[i + 1].start >= const Duration(milliseconds: 500)) {
        result.add(i);
      }
    }
    return result;
  }
}
