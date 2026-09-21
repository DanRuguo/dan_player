import 'dart:math';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as path;

class LrcLine extends UnsyncLyricLine {
  bool isBlank;
  Duration length;

  LrcLine(super.start, super.content,
      {required this.isBlank, this.length = Duration.zero});

  static LrcLine defaultLine = LrcLine(
    Duration.zero,
    "无歌词",
    isBlank: false,
    length: Duration.zero,
  );

  @override
  String toString() {
    return {"time": start.toString(), "content": content}.toString();
  }

  /// line: [mm:ss.msmsms]content
  static LrcLine? fromLine(String line, [int? offset]) =>
      fromLineAll(line, offset).firstOrNull;

  /// A chorus may use several leading timestamps for the same text. Expand
  /// each occurrence before sorting, while preserving brackets in the text.
  static List<LrcLine> fromLineAll(String line, [int? offset]) {
    if (line.trim().isEmpty) {
      return const [];
    }

    final left = line.indexOf("[");
    final right = line.indexOf("]");

    if (left == -1 || right <= left) {
      return const [];
    }
    final times = <Duration>[];
    var cursor = left;
    final pattern = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\]');
    const maxTimestampMillis = 9007199254740991;
    while (true) {
      final tag = pattern.matchAsPrefix(line, cursor);
      if (tag == null) break;
      final minute = int.tryParse(tag[1]!);
      final second = int.tryParse(tag[2]!);
      if (minute == null ||
          second == null ||
          minute > maxTimestampMillis ~/ 60000 ||
          second > maxTimestampMillis ~/ 1000) {
        break;
      }
      // Decimal parsing via double can turn 1.001 seconds into 1000 ms,
      // breaking exact translation/romanization alignment with word formats.
      final fraction = (tag[3] ?? '').padRight(3, '0').substring(0, 3);
      final millis = minute * 60000 + second * 1000 + int.parse(fraction);
      if (millis > maxTimestampMillis) break;
      times.add(Duration(milliseconds: max(millis - (offset ?? 0), 0)));
      cursor = tag.end;
      while (cursor < line.length &&
          (line.codeUnitAt(cursor) == 32 || line.codeUnitAt(cursor) == 9)) {
        cursor++;
      }
    }
    if (times.isEmpty) return const [];
    final content = line.substring(cursor).trim();
    return [
      for (final time in times)
        LrcLine(time, content, isBlank: content.isEmpty),
    ];
  }
}

enum LrcSource {
  /// mp3: USLT frame
  /// flac: LYRICS comment
  local("本地"),
  web("网络");

  final String name;

  const LrcSource(this.name);
}

class Lrc extends Lyric {
  LrcSource source;

  Lrc(super.lines, this.source);

  @override
  String toString() {
    return {"type": source, "lyric": lines}.toString();
  }

  /// Preserve the authored order of original/translation at equal timestamps.
  void _sort() {
    lines = stableSortedLyricLines(lines);
  }

  /// line_1 and line_2时间戳相同，合并成line_1[separator]line_2
  Lrc _combineLrcLine(String separator) {
    List<LrcLine> combinedLines = [];
    var buf = StringBuffer();
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].start != lines[i - 1].start) {
        buf.write((lines[i - 1] as UnsyncLyricLine).content);
        combinedLines.add(LrcLine(
          lines[i - 1].start,
          buf.toString(),
          isBlank: (lines[i - 1] as LrcLine).isBlank,
          length: (lines[i - 1] as LrcLine).length,
        ));
        buf.clear();
      } else {
        buf.write((lines[i - 1] as UnsyncLyricLine).content);
        buf.write(separator);
      }
    }
    if (lines.isNotEmpty) {
      buf.write((lines.last as UnsyncLyricLine).content);
      combinedLines.add(LrcLine(
        lines.last.start,
        buf.toString(),
        isBlank: (lines.last as LrcLine).isBlank,
        length: (lines.last as LrcLine).length,
      ));
    }

    return Lrc(combinedLines, source);
  }

  /// 如果separator为null，不合并歌词；否则，合并相同时间戳的歌词
  static Lrc? fromLrcText(String lrc, LrcSource source, {String? separator}) {
    var lrcLines = lrc.split("\n");

    int? offsetInMilliseconds;
    final offsetPattern = RegExp(r'\[\s*offset\s*:\s*([+-]?\d+)\s*\]');
    for (var line in lrcLines) {
      final matched = offsetPattern.firstMatch(line);
      if (matched == null) continue;
      offsetInMilliseconds = int.tryParse(matched.group(1) ?? "");
      break;
    }

    var lines = <LrcLine>[];
    for (int i = 0; i < lrcLines.length; i++) {
      lines.addAll(LrcLine.fromLineAll(lrcLines[i], offsetInMilliseconds));
    }

    if (lines.isEmpty) {
      return null;
    }

    var result = Lrc(lines, source);
    result._sort();
    if (separator != null) result = result._combineLrcLine(separator);
    // Editing timestamps can reorder lines. Compute animation lengths only
    // after stable sorting and combining translations at the same timestamp.
    for (var i = 0; i < result.lines.length - 1; i++) {
      (result.lines[i] as LrcLine).length =
          result.lines[i + 1].start - result.lines[i].start;
    }
    (result.lines.last as LrcLine).length = Duration.zero;
    return result;
  }

  /// 只支持读取 ID3V2, VorbisComment, Mp4Ilst 存储的内嵌歌词
  /// 以及相同目录相同文件名的 .lrc 外挂歌词（utf-8 or utf-16）
  static Future<Lrc?> fromAudioPath(
    Audio belongTo, {
    String? separator = "┃",
  }) async {
    // A whole-file sidecar uses a different timeline from a CUE segment. CUE
    // revisions live in the application document under the segment identity.
    if (belongTo.isOnline || belongTo.isCueTrack) return null;
    // A user-edited sidecar is an explicit local override. Embedded tags must
    // not hide it immediately after the editor has saved it.
    final sidecar = File(path.setExtension(belongTo.path, '.lrc'));
    try {
      if (await sidecar.exists()) {
        final local = Lrc.fromLrcText(
          decodeLyricText(await sidecar.readAsBytes()),
          LrcSource.local,
          separator: separator,
        );
        if (local != null) return local;
      }
    } catch (error) {
      LOGGER.w('[lyric] sidecar could not be read: $error');
    }
    Lrc? lyric = await getLyricFromPath(path: belongTo.path).then((value) {
      if (value == null) {
        return null;
      }
      return Lrc.fromLrcText(value, LrcSource.local, separator: separator);
    });

    return lyric;
  }
}
