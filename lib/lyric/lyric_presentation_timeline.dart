import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

typedef _Interval = ({Duration start, Duration end});

/// Cached media-time intervals that can change an already shaped lyric row.
/// Idle gaps need only the normal player position stream, not a display ticker.
class LyricPresentationTimeline {
  LyricPresentationTimeline(List<LyricLine> lines)
      : _rows = [for (final line in lines) _intervals(line)];

  final List<List<_Interval>> _rows;

  Duration endFor(int index) =>
      _rows[index].isEmpty ? Duration.zero : _rows[index].last.end;

  bool needsFrames(int index, Duration position) {
    final intervals = _rows[index];
    var low = 0;
    var high = intervals.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (intervals[middle].end <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    // The native position stream is sampled every 33 ms. Wake one sample in
    // advance so the next word's actual lead starts on a display frame.
    return low < intervals.length &&
        intervals[low].start <= position + const Duration(milliseconds: 34);
  }

  static List<_Interval> _intervals(LyricLine line) {
    final intervals = <_Interval>[];
    if (line is SyncLyricLine && line.content.trim().isNotEmpty) {
      final last =
          line.words.lastIndexWhere((word) => word.content.trim().isNotEmpty);
      // Match the painter's shaping groups. A provider may split one grapheme
      // into several short timings whose combined span is a held final note.
      final boundaries = <int>{0};
      var boundary = 0;
      for (final character in line.content.characters) {
        boundary += character.length;
        boundaries.add(boundary);
      }
      var offset = 0;
      for (var i = 0; i < line.words.length; i++) {
        final word = line.words[i];
        final startOffset = offset;
        var start = word.start;
        var end = word.start + word.length;
        offset += word.content.length;
        while (!boundaries.contains(offset) && i + 1 < line.words.length) {
          final next = line.words[++i];
          if (next.start < start) start = next.start;
          if (next.start + next.length > end) end = next.start + next.length;
          offset += next.content.length;
        }
        final length = end - start;
        if (line.content.substring(startOffset, offset).trim().isEmpty ||
            length <= Duration.zero) {
          continue;
        }
        final lead = Duration(
            microseconds: (1000 *
                    LyricWordEffects.presentationLeadMs(
                        length.inMilliseconds, i == last))
                .round());
        final tail = Duration(
            microseconds: (1000 *
                    LyricWordEffects.presentationTailMs(
                        length.inMilliseconds, i == last))
                .round());
        intervals.add((start: start - lead, end: end + tail));
      }
    } else {
      final length = switch (line) {
        SyncLyricLine value when value.content.trim().isEmpty => value.length,
        LrcLine value when value.content.trim().isEmpty => value.length,
        _ => Duration.zero,
      };
      if (length > const Duration(seconds: 5)) {
        intervals.add((start: line.start, end: line.start + length));
      }
    }
    intervals.sort((a, b) => a.start.compareTo(b.start));
    final merged = <_Interval>[];
    for (final interval in intervals) {
      if (merged.isEmpty || merged.last.end < interval.start) {
        merged.add(interval);
      } else if (interval.end > merged.last.end) {
        merged[merged.length - 1] =
            (start: merged.last.start, end: interval.end);
      }
    }
    return merged;
  }
}
