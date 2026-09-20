import 'dart:convert';

import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/qrc.dart';

bool hasWordTiming(Lyric? lyric) =>
    lyric?.lines.any((line) =>
        line is SyncLyricLine &&
        line.words.any((word) =>
            word.content.trim().isNotEmpty && word.length > Duration.zero)) ??
    false;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
String? _section(Object? value) =>
    value is Map ? _text(value['lyric']) : _text(value);

/// Prefer actual timed words, never a provider's label alone. An invalid word
/// variant must not discard a valid ordinary lyric in the same response.
Lyric? parseOnlineLyricPayload(Object? payload) {
  if (payload is String) {
    try {
      return parseOnlineLyricPayload(jsonDecode(payload));
    } catch (_) {}
    return _parse('lrc', payload, null);
  }
  if (payload is! Map ||
      payload['nolyric'] == true ||
      payload['uncollected'] == true) {
    return null;
  }
  final translation = _section(payload['translation']) ??
      _section(payload['translatedLyric']) ??
      _section(payload['trans']) ??
      _section(payload['tlyric']);
  final candidates = <Lyric>[];
  void add(String type, String? text, String? translated) {
    if (text == null) return;
    final result = _parse(type, text, translated);
    if (result != null) candidates.add(result);
  }

  for (final format in const ['qrc', 'krc', 'yrc']) {
    add(
        format,
        _section(payload[format]),
        format == 'yrc'
            ? _section(payload['ytlrc']) ?? translation
            : translation);
  }
  final declared = _text(payload['type']) ??
      _text(payload['format']) ??
      _text(payload['source']) ??
      'lrc';
  add(declared.toLowerCase(),
      _section(payload['lyric']) ?? _section(payload['content']), translation);
  add('lrc', _section(payload['lrc']), translation);
  final nested = payload['data'];
  if (nested != null && nested != payload) {
    final parsed = parseOnlineLyricPayload(nested);
    if (parsed != null) candidates.add(parsed);
  }
  for (final lyric in candidates) {
    if (hasWordTiming(lyric)) return lyric;
  }
  return candidates.firstOrNull;
}

Lyric? _parse(String type, String text, String? translation) {
  try {
    final Lyric? result;
    switch (type) {
      case 'qrc':
        result = Qrc.fromQrcText(text, translation);
      case 'krc':
        result = Krc.fromKrcText(text);
      case 'yrc':
        result = _yrc(text, translation);
      default:
        result = Lrc.fromLrcText(
            translation == null ? text : '$text\n$translation', LrcSource.web,
            separator: '┃');
    }
    if (result == null || result.lines.isEmpty) return null;
    if (const ['qrc', 'krc', 'yrc'].contains(type) && !hasWordTiming(result)) {
      return null;
    }
    return result;
  } catch (_) {
    return null;
  }
}

// YRC uses absolute millisecond starts, unlike KRC's line-relative offsets.
// Store it in the existing QRC model so offsets, backup and trimming retain words.
Qrc _yrc(String text, String? translation) {
  final header = RegExp(r'^\[(\d+),(\d+)\]');
  final word = RegExp(r'\((\d+),(\d+),\d+\)');
  final lines = <QrcLine>[];
  final translated = <Duration, String>{};
  for (final raw in const LineSplitter().convert(translation ?? '')) {
    final line = LrcLine.fromLine(raw);
    if (line != null) translated[line.start] = line.content;
  }
  for (final line in const LineSplitter().convert(text)) {
    final match = header.firstMatch(line);
    if (match == null) continue;
    final words = word.allMatches(line).toList(growable: false);
    if (words.isEmpty) continue;
    final start = Duration(milliseconds: int.parse(match[1]!));
    lines.add(QrcLine(
        start,
        Duration(milliseconds: int.parse(match[2]!)),
        [
          for (var i = 0; i < words.length; i++)
            QrcWord(
                Duration(milliseconds: int.parse(words[i][1]!)),
                Duration(milliseconds: int.parse(words[i][2]!)),
                line.substring(words[i].end,
                    i + 1 < words.length ? words[i + 1].start : line.length)),
        ],
        translated[start]));
  }
  lines.sort((a, b) => a.start.compareTo(b.start));
  final result = <QrcLine>[];
  var end = Duration.zero;
  for (final line in lines) {
    if (line.start - end > const Duration(seconds: 5)) {
      result.add(QrcLine(end, line.start - end, []));
    }
    result.add(line);
    if (line.start + line.length > end) end = line.start + line.length;
  }
  return Qrc(result);
}
