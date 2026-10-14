import 'package:dan_player/lyric/lyric.dart';

/// The unchanged source range painted as the primary lyric. Untimed rows keep
/// their auxiliary tracks after the existing separator; word-timed rows have a
/// separate translation field and may contain an authored literal separator.
String lyricPrimaryText(LyricLine line) {
  if (line is UnsyncLyricLine) {
    final separator = line.content.indexOf('┃');
    return separator < 0 ? line.content : line.content.substring(0, separator);
  }
  return line is SyncLyricLine ? line.content : '';
}
