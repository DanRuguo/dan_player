import 'dart:convert';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/local_lyric_preferences.dart';
import 'package:dan_player/lyric/qrc.dart';
export 'package:dan_player/lyric/local_lyric_preferences.dart';

Lyric? parseLocalLyricText(String text,
    {String extension = '.lrc',
    LocalLyricLineOrder lineOrder = LocalLyricLineOrder.automatic}) {
  if (utf8.encode(text).length > LyricEditDraft.maxBytes) {
    throw const FormatException('歌词文件过大');
  }
  extension = extension.toLowerCase();
  if (extension == '.qrc' && text.trimLeft().startsWith('<')) {
    final content = RegExp(r'''LyricContent\s*=\s*(["'])(.*?)\1''',
            dotAll: true, caseSensitive: false)
        .firstMatch(text)?[2];
    if (content == null) throw const FormatException('无法识别文本 QRC');
    text = content
        .replaceAllMapped(RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false),
            (match) {
          final number = match[1]!;
          final code = int.parse(
              number.startsWith(RegExp('[xX]')) ? number.substring(1) : number,
              radix: number.startsWith(RegExp('[xX]')) ? 16 : 10);
          return String.fromCharCode(code);
        })
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
  // Exporters add descriptive tags which must never appear as lyric content.
  final rows = const LineSplitter()
      .convert(text)
      .where((row) =>
          !RegExp(r'^\s*\[[a-z_]+:[^\r\n]*\]\s*$', caseSensitive: false)
              .hasMatch(row))
      .join('\n');
  if (const ['.qrc', '.krc', '.yrc'].contains(extension)) {
    final format = switch (extension) {
      '.qrc' => LyricEditFormat.qrc,
      '.krc' => LyricEditFormat.krc,
      _ => LyricEditFormat.yrc,
    };
    // KRC's language tag carries actual translation/romanization; other tags
    // remain descriptive and need not pass the authored editor's validation.
    final body = extension == '.krc'
        ? const LineSplitter()
            .convert(text)
            .where((row) =>
                row.trimLeft().startsWith('[language:') ||
                !RegExp(r'^\s*\[[a-z_]+:[^\r\n]*\]\s*$', caseSensitive: false)
                    .hasMatch(row))
            .join('\n')
        : rows;
    return LyricEditDraft(format, body).parse();
  }
  final offset = int.tryParse(
          RegExp(r'\[\s*offset\s*:\s*([+-]?\d+)\s*\]', caseSensitive: false)
                  .firstMatch(text)?[1] ??
              '') ??
      0;
  final parsed = <LyricLine>[];
  for (final raw in const LineSplitter().convert(rows)) {
    final line = raw.trim();
    final leading = _squareStamp.matchAsPrefix(line);
    if (leading == null) continue;
    final remainder = line.substring(leading.end);
    // Several adjacent leading tags with text afterwards are chorus repeats.
    final wordTiming = _angleStamp.hasMatch(remainder) ||
        (remainder.isNotEmpty &&
            !remainder.startsWith('[') &&
            _squareStamp.hasMatch(remainder));
    if (!wordTiming) {
      parsed.addAll(LrcLine.fromLineAll(line, offset));
      continue;
    }
    final start = _time(leading, offset);
    final tags = (_angleStamp.hasMatch(remainder) ? _angleStamp : _squareStamp)
        .allMatches(remainder)
        .toList();
    var cursor = 0;
    var from = start;
    final words = <SyncLyricWord>[];
    for (final tag in tags) {
      final to = _time(tag, offset);
      final content = remainder.substring(cursor, tag.start);
      if (to < from) throw const FormatException('结束时间不能早于开始时间');
      if (content.isNotEmpty) words.add(QrcWord(from, to - from, content));
      from = to;
      cursor = tag.end;
    }
    if (remainder.substring(cursor).trim().isNotEmpty) {
      throw const FormatException('逐字歌词需要结束时间');
    }
    if (words.isNotEmpty && words.first.start < start) {
      throw const FormatException('逐字时间超出所在行范围');
    }
    parsed.add(QrcLine(start, from - start, words));
  }
  if (parsed.isEmpty) return null;
  final grouped = <Duration, List<LyricLine>>{};
  for (final line in parsed) {
    (grouped[line.start] ??= []).add(line);
  }
  final result = <LyricLine>[];
  for (final time in grouped.keys.toList()..sort()) {
    final candidates = grouped[time]!;
    final visible =
        candidates.where((line) => _text(line).trim().isNotEmpty).toList();
    if (visible.isEmpty) {
      result.add(candidates.first);
      continue;
    }
    var original = 0;
    int? romanization;
    final translations = <int>[];
    if (lineOrder == LocalLyricLineOrder.romanizationOriginalTranslation &&
        visible.length >= 2 &&
        visible.length <= 3) {
      romanization = 0;
      original = 1;
      if (visible.length == 3) translations.add(2);
    } else {
      if (lineOrder == LocalLyricLineOrder.originalTranslationRomanization &&
          visible.length == 3) {
        romanization = 2;
      }
      for (var i = 1; i < visible.length; i++) {
        if (i != romanization) translations.add(i);
      }
    }
    final main = visible[original];
    final translated =
        translations.map((index) => _text(visible[index])).join('┃');
    if (translated.isNotEmpty) {
      if (main is SyncLyricLine) main.translation = translated;
      if (main is UnsyncLyricLine) main.content = '${main.content}┃$translated';
    }
    if (romanization != null) main.romanization = _text(visible[romanization]);
    result.add(main);
  }
  final words = result.any((line) => line is SyncLyricLine);
  for (var i = 0; i < result.length; i++) {
    final line = result[i];
    if (line is LrcLine) {
      line.length = i + 1 < result.length
          ? result[i + 1].start - line.start
          : Duration.zero;
      if (words) {
        final parts = line.content.split('┃');
        result[i] = QrcLine(
            line.start,
            line.length,
            [QrcWord(line.start, line.length, parts.first)],
            parts.length > 1 ? parts.skip(1).join('┃') : null)
          ..romanization = line.romanization;
      }
    }
  }
  final lyric = words ? Qrc(result) : Lrc(result, LrcSource.local);
  if (!hasLyricContent(lyric)) return null;
  validateLyricForEditing(lyric);
  return lyric;
}

final _squareStamp = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\]');
final _angleStamp = RegExp(r'<(\d+):(\d+)(?:\.(\d+))?>');
Duration _time(Match match, int offset) {
  final minutes = int.parse(match[1]!);
  final seconds = int.parse(match[2]!);
  final millis = minutes * 60000 +
      seconds * 1000 +
      int.parse((match[3] ?? '').padRight(3, '0').substring(0, 3)) -
      offset;
  if (millis.abs() > 9007199254740991) {
    throw const FormatException('歌词时间超出范围');
  }
  return Duration(milliseconds: millis < 0 ? 0 : millis);
}

String _text(LyricLine line) => switch (line) {
      UnsyncLyricLine() => line.content,
      SyncLyricLine() => line.content,
      _ => '',
    };
