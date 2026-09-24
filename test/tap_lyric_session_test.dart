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
  test(
      'word timing advances only by valid taps, pause and song EOF do not accept',
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
    expect(s.mark(2.1), isFalse);
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
