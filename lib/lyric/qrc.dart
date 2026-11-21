import 'dart:convert';

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';

class Qrc extends Lyric {
  Qrc(super.lines);

  static Qrc fromQrcText(String qrc, [String? transRawStr]) {
    final List<QrcLine> lines = [];
    final splited = const LineSplitter().convert(qrc);
    for (final item in splited) {
      final qrcLine = QrcLine.fromLine(item);

      if (qrcLine == null) continue;

      lines.add(qrcLine);
    }

    if (transRawStr != null) {
      final translated = <Duration, String>{};
      for (final raw in const LineSplitter().convert(transRawStr)) {
        for (final line in LrcLine.fromLineAll(raw)) {
          if (line.content.isNotEmpty) translated[line.start] = line.content;
        }
      }
      for (final line in lines) {
        line.translation = translated[line.start];
      }
    }

    return Qrc(normalizeSyncLyricLines(
        lines, (start, length) => QrcLine(start, length, [])));
  }

  @override
  String toString() {
    return (lines as List<SyncLyricLine>).toString();
  }
}

class QrcLine extends SyncLyricLine {
  QrcLine(super.start, super.length, super.words, [super.translation]);

  static final _headerPattern = RegExp(r'^\[(\d+),(\d+)\]');
  static final _wordPattern = RegExp(r'(.*?)\((\d+),(\d+)\)');

  static QrcLine? fromLine(String line, [String? translation]) {
    final trimmed = line.trimLeft();
    final header = _headerPattern.firstMatch(trimmed);
    if (header == null) return null;
    final content = trimmed.substring(header.end);
    final words = <QrcWord>[
      for (final match in _wordPattern.allMatches(content))
        QrcWord(Duration(milliseconds: int.parse(match[2]!)),
            Duration(milliseconds: int.parse(match[3]!)), match[1]!),
    ];
    return QrcLine(Duration(milliseconds: int.parse(header[1]!)),
        Duration(milliseconds: int.parse(header[2]!)), words, translation);
  }
}

class QrcWord extends SyncLyricWord {
  QrcWord(super.start, super.length, super.content);

  static QrcWord? fromWord(String word) {
    final splitedWord = word.split("(");
    if (splitedWord.length != 2) return null;

    final splitedTime = splitedWord[1].split(",");

    if (splitedTime.length != 2) return null;

    final Duration start = Duration(
      milliseconds: int.tryParse(splitedTime[0]) ?? 0,
    );
    final Duration length = Duration(
      milliseconds: int.tryParse(splitedTime[1]) ?? 0,
    );

    return QrcWord(start, length, splitedWord[0]);
  }
}
