import 'dart:io';
import 'dart:convert';
import 'package:dan_player/lyric/tap_lyric_session.dart';
import 'package:dan_player/lyric/lyric_edit_codec.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/data/backup_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved timing work belongs to library backups', () {
    expect(backupComponentForPath('lyric_tap_progress/abc.json'),
        BackupComponent.library);
    expect(backupComponentForPath(r'lyric_tap_progress\abc.json.bak'),
        BackupComponent.library);
  });
  test(
      'text columns preserve missing translation and require explicit collision level',
      () {
    final rows = parseTapText('你好||ni hao\nHello|你好\nAlone', 0);
    expect(rows[0].translation, '');
    expect(rows[0].romanization, 'ni hao');
    expect(rows[1].translation, '你好');
    expect(rows[1].romanization, '');
    expect(rows[2].text, 'Alone');
    expect(() => parseTapText('a|b|c|d', 0), throwsFormatException);
    final literal = parseTapText('a|b | c|d | e', 1).single;
    expect(literal.text, 'a|b');
    expect(literal.translation, 'c|d');
    final extreme = parseTapText('a | b  |  c | d  |  e', 2).single;
    expect(extreme.text, 'a | b');
    expect(extreme.translation, 'c | d');
  });
  test(
      'online flattening picks a collision-free delimiter and retains auxiliary tracks',
      () {
    final lyric = Qrc([
      QrcLine(
          Duration.zero,
          const Duration(seconds: 1),
          [QrcWord(Duration.zero, const Duration(seconds: 1), 'a|b | c')],
          '译|文')
        ..romanization = '注 | 音'
    ]);
    final result = tapTextFromLyric(lyric);
    expect(result.spaces, 2);
    final row = parseTapText(result.text, result.spaces).single;
    expect(row.text, 'a|b | c');
    expect(row.translation, '译|文');
    expect(row.romanization, '注 | 音');
  });
  test('online flattening rejects lyrics the tap text form cannot represent',
      () {
    Qrc single(String value) => Qrc([
          QrcLine(Duration.zero, const Duration(seconds: 1),
              [QrcWord(Duration.zero, const Duration(seconds: 1), value)])
        ]);
    final lastSupported = tapTextFromLyric(single(
        List.generate(32, (spaces) => 'A${' ' * spaces}|${' ' * spaces}B')
            .join(' / ')));
    expect(lastSupported.spaces, 32);
    expect(parseTapText(lastSupported.text, lastSupported.spaces).single.text,
        lastSupported.text);
    final heavilyPadded = tapTextFromLyric(single('A${' ' * 32}|${' ' * 32}B'));
    expect(heavilyPadded.spaces, 1);
    expect(parseTapText(heavilyPadded.text, heavilyPadded.spaces).single.text,
        heavilyPadded.text);
    expect(
        () => tapTextFromLyric(single(
            List.generate(33, (spaces) => 'A${' ' * spaces}|${' ' * spaces}B')
                .join(' / '))),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('分隔符冲突'))));
    expect(
        () => tapTextFromLyric(single('A\nB')),
        throwsA(isA<FormatException>()
            .having((error) => error.message, 'message', contains('换行内容'))));
  });
  test('asymmetric pipe padding remains literal at the chosen exact level', () {
    for (final content in ['a |  b', 'a  | b']) {
      final lyric = Qrc([
        QrcLine(Duration.zero, const Duration(seconds: 1),
            [QrcWord(Duration.zero, const Duration(seconds: 1), content)])
      ]);
      final result = tapTextFromLyric(lyric);
      expect(result.spaces, 1);
      expect(parseTapText(result.text, result.spaces).single.text, content);
    }
  });
  test(
      'CJK graphemes and western words preserve all characters and punctuation',
      () {
    for (final text in [
      '你好，世界！',
      '青い鳥',
      '한글 노래',
      "L’été, don't go!",
      'e\u0301lan 世界👨‍👩‍👧‍👦 𠀀'
    ]) {
      expect(tapTokens(text).join(), text);
    }
    expect(tapTokens('你好 world!'), ['你', '好 ', 'world!']);
    expect(tapTokens("don't go"), ["don't ", 'go']);
    expect(tapTokens('e\u0301lan'), ['e\u0301lan']);
    final row = TapRow('你好 world!');
    expect(identical(row.tokens, row.tokens), isTrue,
        reason: 'clock updates reuse immutable tokens for the current line');
    expect(() => row.tokens.add('changed'), throwsUnsupportedError);
  });
  test(
      'line review bounds and next pre-roll are based on confirmed previous end',
      () {
    final s = TapLyricSession()..text = 'a\nb';
    s.beginLines();
    expect(s.mark(.2), isTrue);
    expect(s.mark(.2), isFalse);
    expect(s.mark(1), isTrue);
    expect(s.stage, TapStage.lineReview);
    expect(s.reviewRange(8), (start: 0.0, end: 1.5));
    s.accept();
    expect(s.position, .5);
    expect(s.mark(.8), isFalse);
    s.mark(2);
    s.mark(7.8);
    expect(s.reviewRange(8), (start: 1.0, end: 8.0));
    s.retry();
    expect(s.position, .5);
    expect(s.rows.first.end, 1);
    expect(s.row.start, isNull);
    s.mark(2);
    s.mark(7.8);
    s.accept();
    expect(s.stage, TapStage.lineDone);
  });
  test('word timing advances only by valid taps and round-trips final word',
      () {
    final s = TapLyricSession()..text = '你 好';
    s.beginLines();
    s.mark(.3);
    s.mark(2);
    s.accept();
    s.beginWords();
    expect(s.position, .3);
    expect(s.mark(.5), isFalse);
    s.wordStarted = true;
    expect(s.mark(.8), isTrue);
    expect(s.mark(.8), isFalse);
    expect(s.mark(2.6), isFalse);
    s.position = 2;
    expect(s.stage, TapStage.words);
    s.mark(1.8);
    expect(s.stage, TapStage.wordReview);
    expect(s.reviewRange(8), (start: 0.0, end: 2.5));
    s.retry();
    expect(s.row.wordEnds, isEmpty);
    expect(s.wordStarted, isFalse);
    s.wordStarted = true;
    s.mark(.9);
    s.mark(2);
    s.accept();
    expect(s.stage, TapStage.done);
    final lyric = s.lyric(words: true);
    final snapshot =
        LyricEditDraft.fromLyric(lyric, LyricEditFormat.lossless).parse();
    expect((snapshot.lines.single as QrcLine).words.last.length.inMilliseconds,
        1100);
  });
  test('late manual tap may end only the final word at the exact line end', () {
    final s = TapLyricSession()..text = '你 好';
    s.beginLines();
    s.mark(.3);
    s.mark(2);
    s.accept();
    s.beginWords();
    s.mediaDuration = 2.3;
    s.wordStarted = true;
    s.mark(.8);
    expect(s.mark(2.3), isTrue);
    expect(s.row.wordEnds, [.8, 2]);
    expect(s.position, 2.3, reason: 'the transport keeps actual media time');
    expect(s.row.end, 2, reason: 'a manual tap preserves the confirmed line');
    expect(s.stage, TapStage.wordReview);
    s.retry();
    s.wordStarted = true;
    expect(s.mark(2), isTrue);
    expect(s.mark(2.2), isFalse,
        reason: 'the last word still requires positive duration');

    final earlier = TapLyricSession()..text = '你 好 吗';
    earlier.beginLines();
    earlier.mark(.3);
    earlier.mark(2);
    earlier.accept();
    earlier.beginWords();
    earlier.mediaDuration = 8;
    earlier.wordStarted = true;
    earlier.mark(.8);
    expect(earlier.mark(2.2), isFalse,
        reason: 'the tolerance cannot mark a non-final word');
    expect(earlier.row.wordEnds, [.8]);
  });
  test('natural word tolerance ends at the exact line boundary', () {
    final s = TapLyricSession()..text = '你 好';
    s.beginLines();
    s.mark(.3);
    s.mark(2);
    s.accept();
    s.beginWords();
    s.wordStarted = true;
    s.mark(.8);
    expect(s.wordRecordingEnd(8), 2.5);
    expect(s.finishLastWordAtRecordingEnd(2.4, 8), isFalse);
    expect(s.finishLastWordAtRecordingEnd(2.5, 8), isTrue);
    expect(s.row.end, 2);
    expect(s.row.wordEnds, [.8, 2]);
    expect(s.position, 2.5, reason: 'the transport shows the real playhead');
    expect(s.stage, TapStage.wordReview);
    expect(s.reviewRange(8), (start: 0.0, end: 2.5));
    final restored =
        TapLyricSession.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(restored.row.wordEnds, [.8, 2]);
    expect(restored.row.end, 2);
  });
  test(
      'EOF clipped last word extends the containing line and retry restores it',
      () {
    for (final duration in [2.3, 2.5]) {
      final s = TapLyricSession()..text = '你 好';
      s.beginLines();
      s.mark(.3);
      s.mark(2);
      s.accept();
      s.beginWords();
      s.wordStarted = true;
      s.mark(.8);
      expect(s.wordRecordingEnd(duration), duration);
      expect(s.finishLastWordAtRecordingEnd(duration, duration), isTrue);
      expect(s.row.end, duration);
      expect(s.row.wordEnds.last, duration);
      expect(s.row.lineEndBeforeAutoWord, 2);
      final copied =
          TapLyricSession.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(copied.row.end, duration);
      expect((copied.lyric(words: true).lines.single as QrcLine).length,
          Duration(milliseconds: ((duration - .3) * 1000).round()));
      copied.retry();
      expect(copied.row.end, 2);
      expect(copied.row.lineEndBeforeAutoWord, isNull);
      expect(copied.wordRecordingEnd(duration), duration);
      expect(copied.row.wordEnds, isEmpty);
      expect(copied.stage, TapStage.words);
      expect(
          TapLyricSession.fromJson(jsonDecode(jsonEncode(copied.toJson())))
              .row
              .end,
          2);
    }
  });
  test('natural completion infers only the final word and final started line',
      () {
    final words = TapLyricSession()..text = '你 好 吗';
    words.beginLines();
    words.mark(.2);
    words.mark(2);
    words.accept();
    words.beginWords();
    expect(words.finishLastWordAtRecordingEnd(2.5, 8), isFalse);
    words.wordStarted = true;
    expect(words.finishLastWordAtRecordingEnd(2.5, 8), isFalse,
        reason: 'two missing words must not be guessed');
    words.mark(.6);
    words.mark(1.1);
    expect(words.finishLastWordAtRecordingEnd(2.5, 8), isTrue);

    final lines = TapLyricSession()..text = 'one\ntwo';
    lines.beginLines();
    lines.mark(.2);
    expect(lines.finishLastLineAtSongEnd(8), isFalse,
        reason: 'non-final lines still require a stop tap');
    lines.mark(1);
    lines.accept();
    expect(lines.finishLastLineAtSongEnd(8), isFalse,
        reason: 'a line needs an explicit start');
    lines.mark(2);
    expect(lines.finishLastLineAtSongEnd(8), isTrue);
    expect(lines.row.end, 8);
    expect(lines.stage, TapStage.lineReview);
    expect(lines.reviewRange(8), (start: 1.0, end: 8.0));
    expect(
        TapLyricSession.fromJson(jsonDecode(jsonEncode(lines.toJson())))
            .row
            .end,
        8);
    final single = TapLyricSession()..text = 'alone';
    single.beginLines();
    single.mark(.5);
    expect(single.finishLastLineAtSongEnd(8), isTrue);
    expect(single.row.end, 8);
  });
  test('every intermediate stage round-trips while remaining paused', () {
    final s = TapLyricSession()..text = '你好|Hello|ni hao';
    void check() {
      final copy = TapLyricSession.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(copy.toJson(), s.toJson());
    }

    check();
    s.beginLines();
    check();
    s.mark(.2);
    s.position = .6;
    check();
    s.mark(1.5);
    check();
    s.accept();
    check();
    s.beginWords();
    check();
    s.wordStarted = true;
    s.mark(.8);
    s.position = 1;
    s.rate = .25;
    check();
    s.mark(1.4);
    check();
    s.accept();
    check();
  });
  test('invalid persisted timings and unsupported speed cannot be resumed', () {
    final s = TapLyricSession()..text = 'a';
    s.beginLines();
    s.mark(1);
    s.mark(2);
    s.accept();
    final data = s.toJson();
    data['rate'] = .1;
    expect(() => TapLyricSession.fromJson(data), throwsFormatException);
    final bad = s.toJson();
    (bad['rows'] as List).first['end'] = .1;
    expect(() => TapLyricSession.fromJson(bad), throwsFormatException);
  });
  test(
      'progress storage keeps independent songs and recovers previous complete save',
      () async {
    final dir = await Directory.systemTemp.createTemp('tap-progress-');
    addTearDown(() => dir.delete(recursive: true));
    final store = TapProgressStore(dir, 'song-a'),
        other = TapProgressStore(dir, 'song-b');
    final s = TapLyricSession()..text = 'old';
    await store.save(s);
    s.text = 'new';
    await store.save(s);
    expect((await store.load())!.text, 'new');
    expect(await other.load(), isNull);
    await store.file.writeAsString('{broken');
    expect((await store.load())!.text, 'old');
  });
}
