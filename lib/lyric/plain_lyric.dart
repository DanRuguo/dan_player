import 'package:dan_player/lyric/lyric.dart';

/// Lyrics that have text but no timing metadata.
///
/// The complete text is kept in one timeline item anchored at zero. This is a
/// technical display anchor only: callers must not interpret it as per-line
/// synchronization or manufacture timestamps for the individual text lines.
class PlainLyric extends Lyric {
  PlainLyric(String value)
      : text = value.trim(),
        super([
          PlainLyricLine(value.trim()),
        ]);

  final String text;

  String get firstLine => text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
}

class PlainLyricLine extends UnsyncLyricLine {
  PlainLyricLine(String content) : super(Duration.zero, content);
}
