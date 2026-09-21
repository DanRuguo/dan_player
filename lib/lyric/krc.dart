import 'dart:convert';

import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';

class Krc extends Lyric {
  Krc(super.lines);

  static Krc fromKrcText(String krc) {
    final List<KrcLine> lines = [];
    String? languageFrame;

    final splited = const LineSplitter().convert(krc);
    for (final item in splited) {
      if (languageFrame == null &&
          item.startsWith('[language:') &&
          item.endsWith(']')) {
        languageFrame = item.substring(10, item.length - 1);
      }

      final krcLine = KrcLine.fromLine(item);

      if (krcLine == null) continue;

      lines.add(krcLine);
    }

    if (languageFrame != null) {
      // Translation metadata is optional; a broken/mismatched frame must not
      // discard the correctly timed original words.
      try {
        final decoded = json.decode(utf8.decode(base64.decode(languageFrame)));
        if (decoded is Map && decoded['content'] is List) {
          for (final item in decoded['content']) {
            if (item is! Map ||
                item['type'] != 1 ||
                item['lyricContent'] is! List) {
              continue;
            }
            final trans = item['lyricContent'] as List;
            for (var i = 0; i < lines.length && i < trans.length; i++) {
              if (trans[i] is List &&
                  (trans[i] as List).isNotEmpty &&
                  trans[i][0] is String) {
                lines[i].translation = trans[i][0];
              }
            }
            break;
          }
        }
      } catch (_) {}
    }

    // Apply position-based translation metadata before reordering its rows.
    return Krc(normalizeSyncLyricLines(
        lines, (start, length) => KrcLine(start, length, [])));
  }

  @override
  String toString() {
    return (lines as List<SyncLyricLine>).toString();
  }
}

class KrcLine extends SyncLyricLine {
  KrcLine(super.start, super.length, super.words, [super.translation]);

  static KrcLine? fromLine(String line, [String? translation]) {
    final header = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(line.trimLeft());
    if (header == null) return null;
    final start = Duration(milliseconds: int.parse(header[1]!));
    final content = line.trimLeft().substring(header.end);
    final tags = RegExp(r'<(\d+),(\d+),\d+>')
        .allMatches(content)
        .toList(growable: false);
    final words = <KrcWord>[
      for (var i = 0; i < tags.length; i++)
        KrcWord(
            start + Duration(milliseconds: int.parse(tags[i][1]!)),
            Duration(milliseconds: int.parse(tags[i][2]!)),
            content.substring(tags[i].end,
                i + 1 < tags.length ? tags[i + 1].start : content.length)),
    ];
    return KrcLine(start, Duration(milliseconds: int.parse(header[2]!)), words,
        translation);
  }
}

class KrcWord extends SyncLyricWord {
  KrcWord(super.start, super.length, super.content);

  static KrcWord? fromWord(String word, Duration lineStart) {
    final splitedWord = word.split(">");
    if (splitedWord.length != 2) return null;

    final splitedTime = splitedWord[0].split(",");

    if (splitedTime.length < 2) return null;

    final Duration start = Duration(
          milliseconds: int.tryParse(splitedTime[0]) ?? 0,
        ) +
        lineStart;
    final Duration length = Duration(
      milliseconds: int.tryParse(splitedTime[1]) ?? 0,
    );

    return KrcWord(start, length, splitedWord[1]);
  }
}
