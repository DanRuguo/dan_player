import 'dart:convert';

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';

final _transOffsetPattern =
    RegExp(r'\[\s*offset\s*:\s*([+-]?\d+)\s*\]', caseSensitive: false);

/// Aligns LRC-formatted auxiliary lines (`trans`, `tlyric`, `ytlrc`, `romalrc`)
/// onto [lines] (such as millisecond-precise QRC/YRC/KRC lines).
///
/// Exact timestamp matches always win first; remaining non-blank lines match
/// their mutual nearest unassigned auxiliary entry within [tolerance] (default
/// 450ms) so 2-digit centisecond LRC tags (`[00:12.34]` = 12340ms) and slight
/// provider timing drift never drop translations on `[12346,3210]` lines.
void alignLyricAuxiliaryLines(
  List<LyricLine> lines,
  String? rawAuxiliaryText, {
  required String? Function(LyricLine line) readExisting,
  required void Function(LyricLine line, String value) assign,
  Duration tolerance = const Duration(milliseconds: 450),
}) {
  if (rawAuxiliaryText == null ||
      rawAuxiliaryText.trim().isEmpty ||
      lines.isEmpty) {
    return;
  }
  final rawRows = const LineSplitter().convert(rawAuxiliaryText);
  int? offsetMs;
  for (final row in rawRows) {
    final matched = _transOffsetPattern.firstMatch(row);
    if (matched != null) {
      offsetMs = int.tryParse(matched.group(1) ?? '');
      break;
    }
  }
  final grouped = <Duration, List<String>>{};
  for (final raw in rawRows) {
    for (final parsed in LrcLine.fromLineAll(raw, offsetMs)) {
      final trimmed = parsed.content.trim();
      if (trimmed.isEmpty || trimmed == '//') continue;
      final bucket = grouped.putIfAbsent(parsed.start, () => <String>[]);
      if (!bucket.contains(trimmed)) bucket.add(trimmed);
    }
  }
  if (grouped.isEmpty) return;

  final entries = <({Duration start, String text})>[
    for (final key in grouped.keys.toList()..sort())
      (start: key, text: grouped[key]!.join('\n')),
  ];
  final byExact = <Duration, int>{
    for (var i = 0; i < entries.length; i++) entries[i].start: i,
  };
  final usedEntries = List<bool>.filled(entries.length, false);

  bool isNonBlankLine(LyricLine line) => switch (line) {
        SyncLyricLine() => line.content.trim().isNotEmpty,
        UnsyncLyricLine() => line.content.split('┃').first.trim().isNotEmpty,
        _ => false,
      };

  // Pass 1: exact timestamp match.
  for (final line in lines) {
    final existing = readExisting(line);
    if (existing != null && existing.trim().isNotEmpty) continue;
    final exactIdx = byExact[line.start];
    if (exactIdx != null) {
      assign(line, entries[exactIdx].text);
      usedEntries[exactIdx] = true;
    }
  }

  // Pass 2: mutual nearest neighbor within tolerance for non-blank lines.
  final maxMicros = tolerance.inMicroseconds;
  if (maxMicros <= 0) return;
  for (var lineIdx = 0; lineIdx < lines.length; lineIdx++) {
    final line = lines[lineIdx];
    final existing = readExisting(line);
    if ((existing != null && existing.trim().isNotEmpty) ||
        !isNonBlankLine(line)) {
      continue;
    }
    final targetMicros = line.start.inMicroseconds;
    int? bestEntryIdx;
    var bestDelta = maxMicros + 1;
    for (var i = 0; i < entries.length; i++) {
      if (usedEntries[i]) continue;
      final delta = (entries[i].start.inMicroseconds - targetMicros).abs();
      if (delta <= maxMicros && delta < bestDelta) {
        bestDelta = delta;
        bestEntryIdx = i;
      }
    }
    if (bestEntryIdx == null) continue;

    // Confirm no other non-blank lyric line is strictly closer to this entry.
    final entryMicros = entries[bestEntryIdx].start.inMicroseconds;
    var closerOtherLine = false;
    for (var otherIdx = 0; otherIdx < lines.length; otherIdx++) {
      if (otherIdx == lineIdx || !isNonBlankLine(lines[otherIdx])) continue;
      final otherDelta =
          (lines[otherIdx].start.inMicroseconds - entryMicros).abs();
      if (otherDelta < bestDelta) {
        closerOtherLine = true;
        break;
      }
    }
    if (!closerOtherLine) {
      assign(line, entries[bestEntryIdx].text);
      usedEntries[bestEntryIdx] = true;
    }
  }
}

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

    alignLyricAuxiliaryLines(
      lines,
      transRawStr,
      readExisting: (line) => (line as QrcLine).translation,
      assign: (line, value) => (line as QrcLine).translation = value,
    );

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
