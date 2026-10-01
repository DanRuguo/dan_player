import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/play_service/playback_service.dart';

typedef LyricPracticeRange = ({double start, double end});

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
  var startSeconds =
      (line.start.inMicroseconds / 1000000).clamp(0.0, trackLength);
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
}) {
  bool current() =>
      playback.playbackSessionToken == playbackSession && isCurrentLyric();
  if (!current()) return LyricPracticeResult.stale;
  if (!playback.canUseSegmentLoop) return LyricPracticeResult.unavailable;
  final duration = playback.length;
  final range = lyricLinePracticeRange(lyric, line, duration);
  if (range == null) return LyricPracticeResult.invalidRange;
  final loop = playback.segmentLoop;
  if (!loop.setStart(range.start, duration)) {
    return LyricPracticeResult.invalidRange;
  }
  if (!current()) return LyricPracticeResult.stale;
  if (!playback.canUseSegmentLoop) return LyricPracticeResult.unavailable;
  if (!loop.setEnd(range.end, duration)) {
    return LyricPracticeResult.invalidRange;
  }
  if (!current()) return LyricPracticeResult.stale;
  return playback.setSegmentLoopEnabled(true)
      ? LyricPracticeResult.applied
      : LyricPracticeResult.unavailable;
}
