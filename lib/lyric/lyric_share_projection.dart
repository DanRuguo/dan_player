import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/plain_lyric.dart';

/// Capture the displayed text once, keeping the current line's index after
/// empty timing/spacer lines have been removed. No lyric model is changed.
({List<String> lines, int initialIndex}) lyricShareProjection(
  Lyric lyric, {
  required Duration position,
  required String Function(LyricLine) project,
}) {
  if (lyric is PlainLyric) {
    final rows = [
      for (final line in lyric.text.split(RegExp(r'\r?\n')))
        if (line.trim().isNotEmpty) project(PlainLyricLine(line)),
    ];
    return (lines: List.unmodifiable(rows), initialIndex: 0);
  }
  final current = findCurrentLyricLineIndex(lyric.lines, position);
  final rows = <String>[];
  var initial = 0;
  for (var index = 0; index < lyric.lines.length; index++) {
    final text = project(lyric.lines[index]);
    if (text.trim().isEmpty) continue;
    if (index <= current) initial = rows.length;
    rows.add(text);
  }
  return (lines: List.unmodifiable(rows), initialIndex: initial);
}
