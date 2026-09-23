import 'dart:convert';
import 'dart:io';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/krc_decoder.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_text_codec.dart';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';

enum LyricEditFormat {
  lrc('LRC · 逐句', 'lrc'),
  enhanced('增强 LRC · 逐字', 'elrc'),
  qrc('QRC · 逐字（文本）', 'qrc'),
  krc('KRC · 逐字', 'krc'),
  yrc('YRC · 逐字', 'yrc'),
  plain('纯文本', 'txt'),
  lossless('播放器无损副本', 'danlyrics.json');

  const LyricEditFormat(this.label, this.extension);
  final String label, extension;
  bool get timedWords => const [enhanced, qrc, krc, yrc].contains(this);
  String get example => switch (this) {
        lrc => '[00:01.000]Hello world',
        enhanced => '[00:01.000]<00:01.000>Hello <00:01.600>world<00:02.000>',
        qrc => '[1000,1000]Hello (1000,600)world(1600,400)',
        krc => '[1000,1000]<0,600,0>Hello <600,400,0>world',
        yrc => '[1000,1000](1000,600,0)Hello (1600,400,0)world',
        plain => 'Hello world',
        lossless => '{"format":"dan-player-lyrics","version":1,"lyric":{…}}',
      };
}

String lyricStamp(Duration time) {
  final ms = time.inMilliseconds;
  if (ms < 0) throw const FormatException('时间不能为负数');
  return '${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}

String lyricLineText(LyricLine line) => switch (line) {
      UnsyncLyricLine() => line.content,
      SyncLyricLine() => line.content,
      _ => '',
    };

/// Original, translation and romanization remain separate throughout editing.
/// Conversion is explicit; persistence always captures the full parsed model.
class LyricEditDraft {
  const LyricEditDraft(this.format, this.original,
      {this.translation = '', this.romanization = ''});
  final LyricEditFormat format;
  final String original, translation, romanization;
  static const maxBytes = 2 * 1024 * 1024;

  factory LyricEditDraft.fromLyric(Lyric lyric, LyricEditFormat format) {
    if (format == LyricEditFormat.lossless) {
      return LyricEditDraft(
          format,
          const JsonEncoder.withIndent('  ').convert({
            'format': 'dan-player-lyrics',
            'version': 1,
            'lyric': LyricSnapshot.capture(lyric).toJson(),
          }));
    }
    if (format == LyricEditFormat.plain) {
      return LyricEditDraft(
          format,
          lyric is PlainLyric
              ? lyric.text
              : lyric.lines
                  .map(lyricLineText)
                  .where((s) => s.trim().isNotEmpty)
                  .join('\n'));
    }
    if (lyric is PlainLyric) {
      final rows = const LineSplitter()
          .convert(lyric.text)
          .map((text) => '[00:00.000]$text')
          .join('\n');
      final lines = Lrc.fromLrcText(rows, LrcSource.local)!;
      return LyricEditDraft.fromLyric(lines, format);
    }
    final main = <String>[], trans = <String>[], roma = <String>[];
    for (final line in lyric.lines) {
      var text = lyricLineText(line);
      String? translated = line is SyncLyricLine ? line.translation : null;
      if (line is UnsyncLyricLine && text.contains('┃')) {
        final parts = text.split('┃');
        text = parts.first;
        translated = parts.skip(1).join('┃');
      }
      final stamp = lyricStamp(line.start);
      if (translated?.trim().isNotEmpty == true) {
        trans.add('[$stamp]$translated');
      }
      if (line.romanization?.trim().isNotEmpty == true) {
        roma.add('[$stamp]${line.romanization}');
      }
      if (format == LyricEditFormat.lrc) {
        main.add('[$stamp]$text');
        continue;
      }
      final words = line is SyncLyricLine
          ? line.words
          : <SyncLyricWord>[
              if (text.isNotEmpty)
                QrcWord(line.start,
                    line is LrcLine ? line.length : Duration.zero, text)
            ];
      final duration = line is SyncLyricLine
          ? line.length
          : line is LrcLine
              ? line.length
              : Duration.zero;
      final start = line.start.inMilliseconds, length = duration.inMilliseconds;
      if (format == LyricEditFormat.enhanced) {
        final out = StringBuffer('[$stamp]');
        for (final word in words) {
          out.write(
              '<${lyricStamp(word.start)}>${word.content}<${lyricStamp(word.start + word.length)}>');
        }
        main.add(out.toString());
      } else {
        final out = StringBuffer('[$start,$length]');
        for (final word in words) {
          final ms = word.start.inMilliseconds,
              span = word.length.inMilliseconds;
          out.write(switch (format) {
            LyricEditFormat.qrc => '${word.content}($ms,$span)',
            LyricEditFormat.krc => '<${ms - start},$span,0>${word.content}',
            _ => '($ms,$span,0)${word.content}',
          });
        }
        main.add(out.toString());
      }
    }
    return LyricEditDraft(format, main.join('\n'),
        translation: trans.join('\n'), romanization: roma.join('\n'));
  }

  Lyric parse() {
    if (utf8.encode('$original$translation$romanization').length > maxBytes) {
      throw const FormatException('歌词文件过大');
    }
    if (original.trim().isEmpty) throw const FormatException('歌词不能为空');
    if (format == LyricEditFormat.lossless) {
      final data = jsonDecode(original);
      if (data is! Map ||
          data['format'] != 'dan-player-lyrics' ||
          data['version'] != 1) {
        throw const FormatException('无法识别歌词格式');
      }
      if (data['lyric'] is! Map ||
          !const ['plain', 'lrc', 'qrc', 'krc']
              .contains(data['lyric']['format'])) {
        throw const FormatException('无法识别歌词格式');
      }
      final lyric = LyricSnapshot.fromJson(data['lyric'])?.toLyric();
      if (lyric == null || !hasLyricContent(lyric)) {
        throw const FormatException('歌词不能为空');
      }
      validateLyricForEditing(lyric);
      return lyric;
    }
    if (format == LyricEditFormat.plain) {
      if (translation.trim().isNotEmpty || romanization.trim().isNotEmpty) {
        throw const FormatException('纯文本格式不支持辅助时间轴');
      }
      return PlainLyric(original);
    }
    _validateRows(original, format);
    Lyric? lyric = switch (format) {
      LyricEditFormat.lrc =>
        Lrc.fromLrcText(original, LrcSource.local, separator: '┃'),
      LyricEditFormat.enhanced => _parseEnhanced(original),
      LyricEditFormat.qrc => Qrc.fromQrcText(original),
      LyricEditFormat.krc => Krc.fromKrcText(original),
      LyricEditFormat.yrc =>
        parseOnlineLyricPayload({'type': 'yrc', 'lyric': original}),
      _ => null,
    };
    if (lyric == null || !hasLyricContent(lyric)) {
      throw const FormatException('没有识别到有效歌词');
    }
    _applyAux(lyric, translation, false);
    _applyAux(lyric, romanization, true);
    validateLyricForEditing(lyric);
    return lyric;
  }

  static LyricEditDraft importBytes(List<int> bytes, String name) {
    if (bytes.length > maxBytes) throw const FormatException('歌词文件过大');
    final text = bytes.length >= 4 &&
            utf8.decode(bytes.take(4).toList(), allowMalformed: true) == 'krc1'
        ? decodeKrcContainer(base64Encode(bytes))
        : decodeLyricText(bytes);
    final lower = name.toLowerCase();
    final format = lower.endsWith('.json')
        ? LyricEditFormat.lossless
        : lower.endsWith('.txt')
            ? LyricEditFormat.plain
            : lower.endsWith('.qrc')
                ? LyricEditFormat.qrc
                : lower.endsWith('.krc')
                    ? LyricEditFormat.krc
                    : lower.endsWith('.yrc')
                        ? LyricEditFormat.yrc
                        : RegExp(r'<\d+:\d+(?:\.\d+)?>').hasMatch(text)
                            ? LyricEditFormat.enhanced
                            : LyricEditFormat.lrc;
    final result = LyricEditDraft(format, text);
    result.parse();
    return result;
  }

  /// Companion tracks use explicit suffixes instead of ambiguous duplicated rows.
  Map<String, List<int>> exportFiles(String path) {
    final lyric = parse();
    if (format == LyricEditFormat.lossless) {
      return {
        path: utf8.encode(LyricEditDraft.fromLyric(lyric, format).original)
      };
    }
    return {
      path: format == LyricEditFormat.krc
          ? encodeKrcContainer(original)
          : utf8.encode(original),
      if (format != LyricEditFormat.plain)
        '$path.translation.lrc': utf8.encode(translation),
      if (format != LyricEditFormat.plain)
        '$path.romanization.lrc': utf8.encode(romanization),
    };
  }
}

void _validateRows(String text, LyricEditFormat format) {
  final metadata = RegExp(
      r'^\[(?:ar|ti|al|by|offset|length|re|ve|language):[^\r\n]*\]$',
      caseSensitive: false);
  final timed =
      format == LyricEditFormat.lrc || format == LyricEditFormat.enhanced;
  final header =
      timed ? RegExp(r'^\[\d+:\d+(?:\.\d+)?\]') : RegExp(r'^\[\d+,\d+\]');
  var number = 0;
  for (final raw in const LineSplitter().convert(text)) {
    number++;
    final row = raw.trim();
    if (row.isEmpty || metadata.hasMatch(row)) continue;
    if (!header.hasMatch(row)) throw FormatException('歌词行格式无效', number);
    if (!timed) {
      final rest = row.substring(header.firstMatch(row)!.end);
      final word = switch (format) {
        LyricEditFormat.qrc => RegExp(r'.*?\(\d+,\d+\)'),
        LyricEditFormat.krc => RegExp(r'<\d+,\d+,\d+>.*?(?=<\d+,\d+,\d+>|$)'),
        _ => RegExp(r'\(\d+,\d+,\d+\).*?(?=\(\d+,\d+,\d+\)|$)'),
      };
      final numbers = RegExp(r'^\[(\d+),(\d+)\]').firstMatch(row)!;
      final start = int.parse(numbers[1]!),
          end = int.parse(numbers[1]!) + int.parse(numbers[2]!);
      final times = (format == LyricEditFormat.krc
              ? RegExp(r'<(\d+),(\d+),\d+>')
              : format == LyricEditFormat.yrc
                  ? RegExp(r'\((\d+),(\d+),\d+\)')
                  : RegExp(r'\((\d+),(\d+)\)'))
          .allMatches(rest);
      var previous = start;
      for (final time in times) {
        final from =
            int.parse(time[1]!) + (format == LyricEditFormat.krc ? start : 0);
        final to = from + int.parse(time[2]!);
        if (from < previous || from < start || to > end) {
          throw FormatException('逐字时间超出所在行范围', number);
        }
        previous = from;
      }
      final matches = word.allMatches(rest).toList();
      if (rest.isNotEmpty &&
          (matches.isEmpty ||
              matches.first.start != 0 ||
              matches.last.end != rest.length)) {
        throw FormatException('歌词行格式无效', number);
      }
    }
  }
}

Qrc _parseEnhanced(String text) {
  final stamp = RegExp(r'<(\d+):(\d+)(?:\.(\d+))?>');
  final lines = <LyricLine>[];
  Duration time(RegExpMatch m) => Duration(
      milliseconds: int.parse(m[1]!) * 60000 +
          int.parse(m[2]!) * 1000 +
          int.parse((m[3] ?? '').padRight(3, '0').substring(0, 3)));
  for (final raw in const LineSplitter().convert(text)) {
    final row = LrcLine.fromLine(raw);
    if (row == null) continue;
    final tags = stamp.allMatches(row.content).toList();
    if (tags.isNotEmpty && tags.first.start != 0) {
      throw const FormatException('歌词行格式无效');
    }
    for (var i = 1; i < tags.length; i++) {
      if (time(tags[i]) < time(tags[i - 1])) {
        throw const FormatException('结束时间不能早于开始时间');
      }
    }
    if (tags.length < 2 && row.content.isNotEmpty) {
      throw const FormatException('逐字歌词需要结束时间');
    }
    final words = <SyncLyricWord>[];
    for (var i = 0; i + 1 < tags.length; i++) {
      final content = row.content.substring(tags[i].end, tags[i + 1].start);
      if (content.isEmpty) continue;
      words.add(
          QrcWord(time(tags[i]), time(tags[i + 1]) - time(tags[i]), content));
    }
    if (tags.isNotEmpty &&
        row.content.substring(tags.last.end).trim().isNotEmpty) {
      throw const FormatException('逐字歌词需要结束时间');
    }
    final end =
        words.isEmpty ? row.start : words.last.start + words.last.length;
    lines.add(QrcLine(row.start, end - row.start, words));
  }
  return Qrc(lines);
}

void _applyAux(Lyric lyric, String text, bool romanization) {
  if (text.trim().isEmpty) return;
  _validateRows(text, LyricEditFormat.lrc);
  final available = {for (final line in lyric.lines) line.start};
  final values = <Duration, List<String>>{};
  final parsed = Lrc.fromLrcText(text, LrcSource.local);
  for (final line in parsed?.lines.whereType<LrcLine>() ?? <LrcLine>[]) {
    if (!available.contains(line.start)) {
      throw const FormatException('翻译或注音时间未匹配原文');
    }
    (values[line.start] ??= []).add(line.content);
  }
  for (final line in lyric.lines) {
    final value = values[line.start]?.join('┃');
    if (value == null) continue;
    if (romanization) {
      line.romanization = value;
    } else if (line is SyncLyricLine) {
      line.translation = value;
    } else if (line is UnsyncLyricLine) {
      line.content = '${line.content.split('┃').first}┃$value';
    }
  }
}

void validateLyricForEditing(Lyric lyric) {
  if (!hasLyricContent(lyric)) throw const FormatException('歌词不能为空');
  if (lyric.lines.length > 20000) throw const FormatException('歌词文件过大');
  var previousLine = Duration.zero;
  for (final line in lyric.lines) {
    if (line.start.isNegative) throw const FormatException('时间不能为负数');
    if (line.start < previousLine) throw const FormatException('歌词行时间必须顺序排列');
    previousLine = line.start;
    if (line is SyncLyricLine) {
      if (line.length.isNegative) throw const FormatException('结束时间不能早于开始时间');
      var previous = line.start;
      for (final word in line.words) {
        if (word.start < previous ||
            word.length.isNegative ||
            word.start < line.start ||
            word.start + word.length > line.start + line.length) {
          throw const FormatException('逐字时间超出所在行范围');
        }
        previous = word.start;
      }
    }
  }
}

/// Compare the information a format can actually round-trip, not its extension.
bool lyricConversionPreservesData(Lyric source, LyricEditFormat format) {
  try {
    final copy = LyricEditDraft.fromLyric(source, format).parse();
    if (source is PlainLyric || copy is PlainLyric) {
      return source is PlainLyric &&
          copy is PlainLyric &&
          source.text == copy.text;
    }
    final before =
        source.lines.where((l) => lyricLineText(l).trim().isNotEmpty).toList();
    final after =
        copy.lines.where((l) => lyricLineText(l).trim().isNotEmpty).toList();
    if (before.length != after.length) return false;
    String? translation(LyricLine l) => l is SyncLyricLine
        ? l.translation
        : lyricLineText(l).split('┃').skip(1).join('┃');
    for (var i = 0; i < before.length; i++) {
      final a = before[i], b = after[i];
      if (a.start != b.start ||
          lyricLineText(a).split('┃').first !=
              lyricLineText(b).split('┃').first ||
          (a.romanization ?? '') != (b.romanization ?? '') ||
          (translation(a) ?? '') != (translation(b) ?? '')) {
        return false;
      }
      if (a is SyncLyricLine) {
        if (b is! SyncLyricLine ||
            a.length != b.length ||
            a.words.length != b.words.length) {
          return false;
        }
        for (var j = 0; j < a.words.length; j++) {
          final x = a.words[j], y = b.words[j];
          if (x.start != y.start ||
              x.length != y.length ||
              x.content != y.content) {
            return false;
          }
        }
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Re-time a whole row. Existing word offsets move with their line; typing a
/// timestamp in the middle of a QRC/YRC row must never split a word marker.
String retimeLyricEditorRow(
    String row, LyricEditFormat format, int startMs, int endMs) {
  if (startMs < 0 || endMs < startMs) {
    throw const FormatException('结束时间不能早于开始时间');
  }
  if (format == LyricEditFormat.plain || format == LyricEditFormat.lossless) {
    throw const FormatException('无法识别歌词格式');
  }
  if (format == LyricEditFormat.lrc) {
    final text = row.replaceFirst(RegExp(r'^(?:\[\d+:\d+(?:\.\d+)?\])+'), '');
    return '[${lyricStamp(Duration(milliseconds: startMs))}]$text';
  }
  final header = format == LyricEditFormat.enhanced
      ? RegExp(r'^\[\d+:\d+(?:\.\d+)?\]')
      : RegExp(r'^\[\d+,\d+\]');
  if (header.hasMatch(row) &&
      row.substring(header.firstMatch(row)!.end).trim().isNotEmpty) {
    final old = LyricEditDraft(format, row).parse();
    final line = old.lines
        .whereType<SyncLyricLine>()
        .firstWhere((l) => l.words.isNotEmpty);
    final delta = Duration(milliseconds: startMs) - line.start;
    line.start += delta;
    for (final word in line.words) {
      word.start += delta;
    }
    line.length = Duration(milliseconds: endMs - startMs);
    validateLyricForEditing(Qrc([line]));
    return LyricEditDraft.fromLyric(Qrc([line]), format).original;
  }
  final content = row.replaceFirst(header, '');
  final start = Duration(milliseconds: startMs),
      length = Duration(milliseconds: endMs - startMs);
  return LyricEditDraft.fromLyric(
          Qrc([
            QrcLine(start, length, [QrcWord(start, length, content)])
          ]),
          format)
      .original;
}

String timedLyricWord(
    String text, LyricEditFormat format, int startMs, int endMs,
    {required int lineStartMs}) {
  if (startMs < lineStartMs || endMs < startMs) {
    throw const FormatException('逐字时间超出所在行范围');
  }
  if (text.isEmpty ||
      text.contains('\n') ||
      RegExp(r'<\d+:|[<(]\d+,').hasMatch(text)) {
    throw const FormatException('请选择不含时间标记的文字');
  }
  final length = endMs - startMs;
  return switch (format) {
    LyricEditFormat.enhanced =>
      '<${lyricStamp(Duration(milliseconds: startMs))}>$text<${lyricStamp(Duration(milliseconds: endMs))}>',
    LyricEditFormat.qrc => '$text($startMs,$length)',
    LyricEditFormat.krc => '<${startMs - lineStartMs},$length,0>$text',
    LyricEditFormat.yrc => '($startMs,$length,0)$text',
    _ => throw const FormatException('无法识别歌词格式'),
  };
}

/// Write only explicitly selected export files, rolling back the whole group.
Future<void> writeLyricExport(Map<String, List<int>> files) async {
  final installed = <String>[], backedUp = <String>[];
  final suffix = '.$pid.${DateTime.now().microsecondsSinceEpoch}';
  try {
    for (final entry in files.entries) {
      final target = File(entry.key), temp = File('${entry.key}$suffix.tmp');
      await temp.writeAsBytes(entry.value, flush: true);
      if (await target.exists()) {
        await target.copy('${entry.key}$suffix.bak');
        backedUp.add(entry.key);
      }
      await temp.rename(target.path);
      installed.add(entry.key);
    }
  } catch (_) {
    for (final name in installed.reversed) {
      final target = File(name);
      if (await target.exists()) await target.delete();
    }
    for (final name in backedUp.reversed) {
      await File('$name$suffix.bak').copy(name);
    }
    rethrow;
  } finally {
    for (final name in files.keys) {
      final temp = File('$name$suffix.tmp');
      if (await temp.exists()) await temp.delete();
    }
  }
}

Future<LyricEditDraft> readLyricEditFile(File file) async {
  Future<List<int>> bounded(File item) async {
    if (await item.length() > LyricEditDraft.maxBytes) {
      throw const FormatException('歌词文件过大');
    }
    return item.readAsBytes();
  }

  final draft = LyricEditDraft.importBytes(await bounded(file), file.path);
  Future<String> aux(String suffix) async {
    final item = File('${file.path}.$suffix.lrc');
    return await item.exists() ? decodeLyricText(await bounded(item)) : '';
  }

  final result = LyricEditDraft(draft.format, draft.original,
      translation: await aux('translation'),
      romanization: await aux('romanization'));
  result.parse();
  return result;
}

/// Small authored example; no provider lookup or copyrighted song is needed.
LyricEditDraft lyricEditingExample(LyricEditFormat format) {
  final lyric = Qrc([
    QrcLine(
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        [
          QrcWord(const Duration(seconds: 1), const Duration(milliseconds: 700),
              'Hello '),
          QrcWord(const Duration(milliseconds: 1700),
              const Duration(milliseconds: 1300), 'world'),
        ],
        '你好，世界')
      ..romanization = 'həˈləʊ wɜːld',
    QrcLine(
        const Duration(seconds: 4),
        const Duration(seconds: 2),
        [
          QrcWord(const Duration(seconds: 4), const Duration(milliseconds: 800),
              'A new '),
          QrcWord(const Duration(milliseconds: 4800),
              const Duration(milliseconds: 1200), 'day'),
        ],
        '新的一天')
      ..romanization = 'ə njuː deɪ',
  ]);
  return LyricEditDraft.fromLyric(lyric, format);
}

String replaceTimedLyricWord(String row, LyricEditFormat format,
    int selectionStart, int selectionEnd, int startMs, int endMs,
    {required int lineStartMs}) {
  final text = row.substring(selectionStart, selectionEnd);
  final word =
      timedLyricWord(text, format, startMs, endMs, lineStartMs: lineStartMs);
  var from = selectionStart, to = selectionEnd;
  final prefix = switch (format) {
    LyricEditFormat.krc => RegExp(r'<\d+,\d+,\d+>$'),
    LyricEditFormat.yrc => RegExp(r'\(\d+,\d+,\d+\)$'),
    LyricEditFormat.enhanced => RegExp(r'<\d+:\d+(?:\.\d+)?>$'),
    _ => null,
  };
  final before = prefix?.firstMatch(row.substring(0, from));
  if (before != null) from = before.start;
  final suffix = switch (format) {
    LyricEditFormat.qrc => RegExp(r'^\(\d+,\d+\)'),
    LyricEditFormat.enhanced => RegExp(r'^<\d+:\d+(?:\.\d+)?>'),
    _ => null,
  };
  final after = suffix?.firstMatch(row.substring(to));
  if (after != null) to += after.end;
  final result = row.replaceRange(from, to, word);
  LyricEditDraft(format, result).parse();
  return result;
}

LyricEditFormat preferredLyricEditingFormat(Lyric lyric) {
  for (final format in [
    if (lyric is PlainLyric) LyricEditFormat.plain,
    if (lyric is Krc) LyricEditFormat.krc,
    if (lyric is Lrc) LyricEditFormat.lrc,
    LyricEditFormat.qrc,
  ]) {
    if (lyricConversionPreservesData(lyric, format)) return format;
  }
  return LyricEditFormat.lossless;
}

String retimeLyricAuxiliaryRows(String text, int oldMs, int newMs) {
  if (text.trim().isEmpty || oldMs == newMs) return text;
  final lines =
      Lrc.fromLrcText(text, LrcSource.local)?.lines.whereType<LrcLine>();
  if (lines == null) throw const FormatException('歌词行格式无效');
  return lines
      .map((line) =>
          '[${lyricStamp(line.start.inMilliseconds == oldMs ? Duration(milliseconds: newMs) : line.start)}]${line.content}')
      .join('\n');
}
