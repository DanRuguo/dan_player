import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';

class Qrc extends Lyric {
  Qrc(super.lines);

  static Qrc fromQrcText(String qrc, [String? transRawStr]) {
    final List<QrcLine> lines = [];
    final splited = qrc.split("\n");
    for (final item in splited) {
      final qrcLine = QrcLine.fromLine(item);

      if (qrcLine == null) continue;

      lines.add(qrcLine);
    }

    if (transRawStr != null) {
      final translated = <Duration, String>{};
      for (final raw in transRawStr.split('\n')) {
        final line = LrcLine.fromLine(raw);
        if (line != null && line.content.isNotEmpty) {
          translated[line.start] = line.content;
        }
      }
      for (final line in lines) {
        line.translation = translated[line.start];
      }
    }

    // 添加空白
    final List<QrcLine> fommatedLines = [];
    final firstLine = lines.firstOrNull;
    if (firstLine != null && firstLine.start > const Duration(seconds: 5)) {
      fommatedLines.add(QrcLine(Duration.zero, firstLine.start, []));
    }
    for (int i = 0; i < lines.length - 1; ++i) {
      fommatedLines.add(lines[i]);
      final transitionStart = lines[i].start + lines[i].length;
      final transitionLength = lines[i + 1].start - transitionStart;
      if (transitionLength > const Duration(seconds: 5)) {
        fommatedLines.add(QrcLine(transitionStart, transitionLength, []));
      }
    }
    final lastLine = lines.lastOrNull;
    if (lastLine != null) {
      fommatedLines.add(lastLine);
    }

    return Qrc(fommatedLines);
  }

  @override
  String toString() {
    return (lines as List<SyncLyricLine>).toString();
  }
}

class QrcLine extends SyncLyricLine {
  QrcLine(super.start, super.length, super.words, [super.translation]);

  static QrcLine? fromLine(String line, [String? translation]) {
    final header = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(line.trimLeft());
    if (header == null) return null;
    final content = line.trimLeft().substring(header.end);
    final words = <QrcWord>[
      for (final match in RegExp(r'(.*?)\((\d+),(\d+)\)').allMatches(content))
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
