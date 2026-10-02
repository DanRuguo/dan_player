import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/play_service/playback_service.dart';

typedef LyricPracticeRange = ({double start, double end});

bool isTimedLyricPracticeLine(LyricLine line) => switch (line) {
      LrcLine() =>
        !line.isBlank && line.content.split('┃').first.trim().isNotEmpty,
      SyncLyricLine() => line.content.trim().isNotEmpty,
      _ => false,
    };

/// Select a continuous span in the displayed document, even when its two
/// endpoints are picked in reverse order. Empty interludes are not endpoints;
/// short phrases can form a valid longer span without stretching their timing.
LyricPracticeRange? lyricSegmentPracticeRange(
    Lyric lyric, LyricLine first, LyricLine last, double trackLength) {
  if (lyric is PlainLyric ||
      !trackLength.isFinite ||
      trackLength < 1 ||
      !isTimedLyricPracticeLine(first) ||
      !isTimedLyricPracticeLine(last)) {
    return null;
  }
  final firstIndex = lyric.lines.indexWhere((line) => identical(line, first));
  final lastIndex = lyric.lines.indexWhere((line) => identical(line, last));
  if (firstIndex < 0 || lastIndex < 0) return null;
  if (firstIndex == lastIndex) {
    return lyricLinePracticeRange(lyric, first, trackLength);
  }
  final from = firstIndex < lastIndex ? firstIndex : lastIndex;
  final to = firstIndex > lastIndex ? firstIndex : lastIndex;
  Duration? start, end, latestOpenStart;
  for (var index = from; index <= to; index++) {
    final line = lyric.lines[index];
    if (!isTimedLyricPracticeLine(line)) continue;
    if (start == null || line.start < start) start = line.start;
    final Duration lineEnd;
    switch (line) {
      case LrcLine():
        if (line.length.isNegative) return null;
        if (line.length == Duration.zero) {
          if (latestOpenStart == null || line.start > latestOpenStart) {
            latestOpenStart = line.start;
          }
          continue;
        }
        lineEnd = line.start + line.length;
      case SyncLyricLine():
        if (line.length.isNegative ||
            line.words.any((word) => word.length.isNegative)) {
          return null;
        }
        lineEnd = syncLyricLineEnd(line);
      default:
        return null;
    }
    if (end == null || lineEnd > end) end = lineEnd;
  }
  // The latest selected open LRC row also has the latest inferred end. Scan
  // once, instead of searching the whole document again for every chosen row.
  if (latestOpenStart != null) {
    Duration? next;
    for (final line in lyric.lines) {
      if (line.start > latestOpenStart && (next == null || line.start < next)) {
        next = line.start;
      }
    }
    final openEnd = next == null
        ? trackLength
        : next.inMicroseconds / Duration.microsecondsPerSecond;
    return _boundedPracticeRange(start!,
        end == null ? openEnd : _laterSeconds(end, openEnd), trackLength);
  }
  return start == null || end == null
      ? null
      : _boundedPracticeRange(start,
          end.inMicroseconds / Duration.microsecondsPerSecond, trackLength);
}

double _laterSeconds(Duration authored, double inferred) {
  final seconds = authored.inMicroseconds / Duration.microsecondsPerSecond;
  return seconds > inferred ? seconds : inferred;
}

/// Uses the displayed lyric clock, which already includes its offset. A final
/// LRC line has no authored end; use the track end, never invent a plain-text
/// timestamp or stretch a sub-second phrase to satisfy the transport minimum.
LyricPracticeRange? lyricLinePracticeRange(
    Lyric lyric, LyricLine line, double trackLength) {
  if (lyric is PlainLyric ||
      !lyric.lines.any((item) => identical(item, line)) ||
      !trackLength.isFinite ||
      trackLength < 1) {
    return null;
  }
  final double end;
  switch (line) {
    case LrcLine():
      if (line.isBlank || line.content.split('┃').first.trim().isEmpty) {
        return null;
      }
      if (line.length > Duration.zero) {
        end = (line.start + line.length).inMicroseconds / 1000000;
      } else {
        final next = lyric.lines
            .where((item) => item.start > line.start)
            .map((item) => item.start)
            .fold<Duration?>(
                null,
                (earliest, time) =>
                    earliest == null || time < earliest ? time : earliest);
        end = next == null ? trackLength : next.inMicroseconds / 1000000;
      }
    case SyncLyricLine():
      if (line.content.trim().isEmpty) return null;
      end = syncLyricLineEnd(line).inMicroseconds / 1000000;
    default:
      return null;
  }
  return _boundedPracticeRange(line.start, end, trackLength);
}

LyricPracticeRange? _boundedPracticeRange(
    Duration start, double end, double trackLength) {
  var startSeconds = (start.inMicroseconds / 1000000).clamp(0.0, trackLength);
  final endSeconds = end.clamp(0.0, trackLength);
  final span = endSeconds - startSeconds;
  if (span < 1) {
    // Millisecond/microsecond timestamps can subtract to 0.9999999999999998
    // after conversion. Keep B inside the track and normalize only rounding
    // below a nanosecond; an authored sub-second line still fails unchanged.
    if (span < 1 - 1e-9) return null;
    startSeconds = endSeconds - 1;
  }
  return (start: startSeconds, end: endSeconds);
}

enum LyricPracticeResult { applied, stale, unavailable, invalidRange }

/// Keep source ownership checks around synchronous controller notifications:
/// listeners may replace a song while the range is being set. Starting the
/// existing loop seeks to A but never starts a paused transport.
LyricPracticeResult practiceLyricLine({
  required PlaybackService playback,
  required Lyric lyric,
  required LyricLine line,
  required int playbackSession,
  required bool Function() isCurrentLyric,
}) =>
    _applyPracticeRange(
      playback: playback,
      range: (duration) => lyricLinePracticeRange(lyric, line, duration),
      playbackSession: playbackSession,
      isCurrentLyric: isCurrentLyric,
    );

LyricPracticeResult practiceLyricSegment({
  required PlaybackService playback,
  required Lyric lyric,
  required LyricLine first,
  required LyricLine last,
  required int playbackSession,
  required bool Function() isCurrentLyric,
}) =>
    _applyPracticeRange(
      playback: playback,
      range: (duration) =>
          lyricSegmentPracticeRange(lyric, first, last, duration),
      playbackSession: playbackSession,
      isCurrentLyric: isCurrentLyric,
    );

LyricPracticeResult _applyPracticeRange({
  required PlaybackService playback,
  required LyricPracticeRange? Function(double duration) range,
  required int playbackSession,
  required bool Function() isCurrentLyric,
}) {
  bool current() =>
      playback.playbackSessionToken == playbackSession && isCurrentLyric();
  if (!current()) return LyricPracticeResult.stale;
  if (!playback.canUseSegmentLoop) return LyricPracticeResult.unavailable;
  final duration = playback.length;
  final selected = range(duration);
  if (selected == null) return LyricPracticeResult.invalidRange;
  final loop = playback.segmentLoop;
  if (!loop.setStart(selected.start, duration)) {
    return LyricPracticeResult.invalidRange;
  }
  if (!current()) return LyricPracticeResult.stale;
  if (!playback.canUseSegmentLoop) return LyricPracticeResult.unavailable;
  if (!loop.setEnd(selected.end, duration)) {
    return LyricPracticeResult.invalidRange;
  }
  if (!current()) return LyricPracticeResult.stale;
  return playback.setSegmentLoopEnabled(true)
      ? LyricPracticeResult.applied
      : LyricPracticeResult.unavailable;
}
