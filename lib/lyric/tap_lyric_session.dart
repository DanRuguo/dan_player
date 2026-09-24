import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:crypto/crypto.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';

enum TapStage { text, lines, lineReview, lineDone, words, wordReview, done }

class TapRow {
  TapRow(this.text, [this.translation = '', this.romanization = '']);
  final String text, translation, romanization;
  double? start, end;
  final List<double> wordEnds = [];
  List<String> get tokens => tapTokens(text);
  Map<String, dynamic> toJson() => {
        'text': text,
        'translation': translation,
        'romanization': romanization,
        'start': start,
        'end': end,
        'wordEnds': wordEnds,
      };
  factory TapRow.fromJson(Map<String, dynamic> json) {
    final row = TapRow(json['text'] as String, json['translation'] as String,
        json['romanization'] as String);
    row.start = (json['start'] as num?)?.toDouble();
    row.end = (json['end'] as num?)?.toDouble();
    row.wordEnds
        .addAll((json['wordEnds'] as List).map((n) => (n as num).toDouble()));
    return row;
  }
}

/// Grapheme-safe: CJK/Hangul units are individual taps; western words retain
/// their spaces/punctuation. Concatenation always reproduces the original.
List<String> tapTokens(String text) {
  final result = <String>[];
  var word = '', prefix = '';
  final cjk = RegExp(
      r'[\u3040-\u30ff\u3400-\u9fff\u1100-\u11ff\u3130-\u318f\ua960-\ua97f\uac00-\ud7ff\uf900-\ufaff]|[\u{20000}-\u{323af}]',
      unicode: true);
  void flush() {
    if (word.isNotEmpty) {
      result.add('$prefix$word');
      prefix = '';
      word = '';
    }
  }

  for (final g in text.characters) {
    if (cjk.hasMatch(g)) {
      flush();
      result.add('$prefix$g');
      prefix = '';
    } else if (RegExp(r'^[\p{L}\p{M}\p{N}]', unicode: true).hasMatch(g) ||
        ((g == "'" || g == '’') && word.isNotEmpty)) {
      word += g;
    } else {
      flush();
      if (result.isEmpty) {
        prefix += g;
      } else {
        result[result.length - 1] += g;
      }
    }
  }
  flush();
  if (prefix.isNotEmpty) result.add(prefix);
  return result;
}

String tapDelimiter(int spaces) => '${' ' * spaces}|${' ' * spaces}';

List<TapRow> parseTapText(String text, int spaces) {
  if (utf8.encode(text).length > LyricEditDraft.maxBytes ||
      spaces < 0 ||
      spaces > 32) {
    throw const FormatException('歌词文件过大');
  }
  final rows = <TapRow>[];
  final delimiter = tapDelimiter(spaces);
  // Match exactly this padding, leaving lower levels available as literal text.
  final pattern = spaces == 0
      ? RegExp(r'\|')
      : RegExp('(?<! )${RegExp.escape(delimiter)}(?! )');
  for (final raw in const LineSplitter().convert(text)) {
    if (raw.trim().isEmpty) continue;
    final parts = raw.split(pattern);
    if (parts.length > 3 || parts.first.trim().isEmpty) {
      throw const FormatException('请检查分隔符：每行最多为正文、翻译、注音三栏。');
    }
    rows.add(TapRow(parts[0].trim(), parts.length > 1 ? parts[1].trim() : '',
        parts.length > 2 ? parts[2].trim() : ''));
  }
  if (rows.isEmpty) throw const FormatException('歌词不能为空');
  if (rows.length > 4000) throw const FormatException('歌词文件过大');
  return rows;
}

({String text, int spaces}) tapTextFromLyric(Lyric lyric) {
  final rows = lyric is PlainLyric
      ? const LineSplitter()
          .convert(lyric.text)
          .where((s) => s.trim().isNotEmpty)
          .map((s) => TapRow(s))
          .toList()
      : lyric.lines
          .map((line) {
            var text = lyricLineText(line);
            var translation =
                line is SyncLyricLine ? line.translation ?? '' : '';
            if (line is UnsyncLyricLine && text.contains('┃')) {
              final parts = text.split('┃');
              text = parts.first;
              translation = parts.skip(1).join('┃');
            }
            return TapRow(text, translation, line.romanization ?? '');
          })
          .where((r) => r.text.trim().isNotEmpty)
          .toList();
  var spaces = 0;
  while (rows.any((r) => [r.text, r.translation, r.romanization]
      .any((s) => s.contains(tapDelimiter(spaces))))) {
    spaces++;
  }
  final delimiter = tapDelimiter(spaces);
  return (
    spaces: spaces,
    text: rows
        .map((r) => [
              r.text,
              if (r.translation.isNotEmpty || r.romanization.isNotEmpty)
                r.translation,
              if (r.romanization.isNotEmpty) r.romanization
            ].join(delimiter))
        .join('\n')
  );
}

/// Playback is external. Every timestamp is media time, never elapsed wall time.
class TapLyricSession {
  String text = '';
  int spaces = 0, index = 0;
  double position = 0, rate = 1, mediaDuration = 0;
  TapStage stage = TapStage.text;
  List<TapRow> rows = [];
  bool wordStarted = false;
  TapRow get row => rows[index];
  double get previousEnd => index == 0 ? 0 : rows[index - 1].end!;
  double get restartPosition =>
      stage == TapStage.words || stage == TapStage.wordReview
          ? row.start!
          : (previousEnd - .5).clamp(0, double.infinity);

  void beginLines() {
    rows = parseTapText(text, spaces);
    index = 0;
    position = 0;
    stage = TapStage.lines;
  }

  bool mark(double time) {
    if (!time.isFinite || time < 0) return false;
    if (stage == TapStage.lines) {
      if (row.start == null) {
        if (time < previousEnd) return false;
        row.start = time;
      } else {
        if (time <= row.start!) return false;
        row.end = time;
        stage = TapStage.lineReview;
      }
    } else if (stage == TapStage.words && wordStarted) {
      final previous = row.wordEnds.isEmpty ? row.start! : row.wordEnds.last;
      if (time <= previous || time > row.end! + .001) return false;
      row.wordEnds.add(time.clamp(row.start!, row.end!));
      if (row.wordEnds.length == row.tokens.length) stage = TapStage.wordReview;
    } else {
      return false;
    }
    position = time;
    return true;
  }

  ({double start, double end}) reviewRange(double duration) => (
        start: stage == TapStage.lineReview
            ? previousEnd
            : (row.start! - .5).clamp(0, duration),
        end: (row.end! + .5).clamp(0, duration)
      );
  void accept() {
    final words = stage == TapStage.wordReview;
    if (!words && stage != TapStage.lineReview) return;
    index++;
    if (index == rows.length) {
      index = rows.length - 1;
      stage = words ? TapStage.done : TapStage.lineDone;
    } else {
      stage = words ? TapStage.words : TapStage.lines;
      wordStarted = false;
      position = restartPosition;
    }
  }

  void retry() {
    if (stage == TapStage.wordReview || stage == TapStage.words) {
      row.wordEnds.clear();
      wordStarted = false;
      stage = TapStage.words;
    } else {
      row.start = row.end = null;
      stage = TapStage.lines;
    }
    position = restartPosition;
  }

  void beginWords() {
    if (stage != TapStage.lineDone) return;
    index = 0;
    wordStarted = false;
    stage = TapStage.words;
    position = row.start!;
  }

  Lyric lyric({bool words = false, bool onlyCurrent = false}) =>
      Qrc((onlyCurrent ? [row] : rows).map((r) {
        final start = r.start!, end = r.end!;
        Duration stamp(double t) => Duration(microseconds: (t * 1e6).round());
        var cursor = start;
        final tokens = words ? r.tokens : [r.text];
        final ends = words ? r.wordEnds : [end];
        final result = <QrcWord>[];
        for (var i = 0; i < tokens.length; i++) {
          result
              .add(QrcWord(stamp(cursor), stamp(ends[i] - cursor), tokens[i]));
          cursor = ends[i];
        }
        return QrcLine(stamp(start), stamp(end - start), result,
            r.translation.isEmpty ? null : r.translation)
          ..romanization = r.romanization.isEmpty ? null : r.romanization;
      }).toList());
  Map<String, dynamic> toJson() => {
        'version': 1,
        'text': text,
        'spaces': spaces,
        'index': index,
        'position': position,
        'rate': rate,
        'mediaDuration': mediaDuration,
        'stage': stage.name,
        'wordStarted': wordStarted,
        'rows': rows.map((r) => r.toJson()).toList()
      };
  factory TapLyricSession.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) throw const FormatException('无法读取点按进度');
    final s = TapLyricSession()
      ..text = data['text'] as String
      ..spaces = data['spaces'] as int
      ..index = data['index'] as int
      ..position = (data['position'] as num).toDouble()
      ..rate = (data['rate'] as num).toDouble()
      ..mediaDuration = (data['mediaDuration'] as num? ?? 0).toDouble()
      ..stage = TapStage.values.byName(data['stage'] as String)
      ..wordStarted = data['wordStarted'] as bool
      ..rows = (data['rows'] as List)
          .map((r) => TapRow.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    if (s.text.length > LyricEditDraft.maxBytes ||
        s.spaces < 0 ||
        s.spaces > 32 ||
        ![.25, .5, .75, 1.0].contains(s.rate) ||
        !s.position.isFinite ||
        s.position < 0 ||
        !s.mediaDuration.isFinite ||
        s.mediaDuration < 0 ||
        s.rows.length > 4000 ||
        (s.stage != TapStage.text &&
            (s.rows.isEmpty || s.index < 0 || s.index >= s.rows.length))) {
      throw const FormatException('无法读取点按进度');
    }
    double previous = 0;
    for (final r in s.rows) {
      if (r.text.trim().isEmpty ||
          r.start != null && (!r.start!.isFinite || r.start! < previous) ||
          r.end != null &&
              (r.start == null || !r.end!.isFinite || r.end! <= r.start!)) {
        throw const FormatException('无法读取点按进度');
      }
      var wordEnd = r.start ?? 0;
      for (final end in r.wordEnds) {
        if (!end.isFinite || end <= wordEnd || r.end == null || end > r.end!) {
          throw const FormatException('无法读取点按进度');
        }
        wordEnd = end;
      }
      if (r.wordEnds.length > r.tokens.length) {
        throw const FormatException('无法读取点按进度');
      }
      previous = r.end ?? previous;
    }
    final requiresLines = [
      TapStage.lineDone,
      TapStage.words,
      TapStage.wordReview,
      TapStage.done
    ].contains(s.stage);
    if (requiresLines && s.rows.any((r) => r.start == null || r.end == null) ||
        s.stage == TapStage.lineReview && s.row.end == null ||
        s.stage == TapStage.done &&
            s.rows.any((r) => r.wordEnds.length != r.tokens.length)) {
      throw const FormatException('无法读取点按进度');
    }
    if (s.stage != TapStage.text) {
      final parsed = parseTapText(s.text, s.spaces);
      if (parsed.length != s.rows.length) {
        throw const FormatException('无法读取点按进度');
      }
      for (var i = 0; i < parsed.length; i++) {
        final a = parsed[i], b = s.rows[i];
        if (a.text != b.text ||
            a.translation != b.translation ||
            a.romanization != b.romanization ||
            i < s.index && b.end == null) {
          throw const FormatException('无法读取点按进度');
        }
        if ([TapStage.words, TapStage.wordReview].contains(s.stage) &&
            i < s.index &&
            b.wordEnds.length != b.tokens.length) {
          throw const FormatException('无法读取点按进度');
        }
      }
      if (s.stage == TapStage.wordReview &&
              s.row.wordEnds.length != s.row.tokens.length ||
          s.stage == TapStage.words &&
              s.row.wordEnds.length == s.row.tokens.length ||
          s.stage == TapStage.lines &&
              s.row.start != null &&
              s.position < s.row.start!) {
        throw const FormatException('无法读取点按进度');
      }
    }
    return s;
  }
  TapLyricSession();
}

class TapProgressStore {
  TapProgressStore(this.directory, this.trackId);
  final Directory directory;
  final String trackId;
  File get file =>
      File('${directory.path}/${sha256.convert(utf8.encode(trackId))}.json');
  Future<void> save(TapLyricSession session) async {
    final encoded =
        jsonEncode({'trackId': trackId, 'session': session.toJson()});
    if (utf8.encode(encoded).length > 8 * 1024 * 1024) {
      throw const FormatException('歌词文件过大');
    }
    await directory.create(recursive: true);
    final tmp = File('${file.path}.tmp'), backup = File('${file.path}.bak');
    await tmp.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    }
  }

  Future<TapLyricSession?> load() async {
    Object? error;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > 8 * 1024 * 1024) {
          throw const FormatException('无法读取点按进度');
        }
        final data = jsonDecode(await candidate.readAsString()) as Map;
        if (data['trackId'] != trackId) throw const FormatException('无法读取点按进度');
        return TapLyricSession.fromJson(
            Map<String, dynamic>.from(data['session'] as Map));
      } catch (e) {
        error = e;
      }
    }
    if (error != null) throw const FormatException('无法读取点按进度');
    return null;
  }
}
