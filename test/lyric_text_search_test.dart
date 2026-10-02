import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_text_search.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_reading_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search uses original document indices and all loaded reading tracks',
      () {
    final lyric = Lrc([
      LrcLine(Duration.zero, '', isBlank: true),
      LrcLine(const Duration(seconds: 4), 'Rain 雨┃夜雨', isBlank: false)
        ..romanization = 'ame ga furu',
      LrcLine(const Duration(seconds: 8), 'RAIN again', isBlank: false),
    ], LrcSource.local);
    final rows = lyricSearchRows(lyric, project: lyricReadingText);
    expect(rows.map((row) => row.index), [1, 2]);
    expect(filterLyricSearchRows(rows, 'AME 夜雨').single.index, 1);
    expect(rows.first.preview('夜雨'), '夜雨');
    expect(rows.first.preview('ame'), 'ame ga furu');
    expect(rows.first.preview(''), rows.first.text);
    final longPlain = PlainLyric('${'prefix ' * 600}UniqueNeedle after');
    final preview = lyricSearchRows(longPlain, project: lyricReadingText)
        .single
        .preview('uniqueneedle');
    expect(preview, contains('UniqueNeedle'));
    expect(preview.length, lessThan(170));
    expect(filterLyricSearchRows(rows, 'rAiN').map((row) => row.index), [1, 2]);
    expect(rows.first.target.line, same(lyric.lines[1]));
    expect(lyric.lines[1].start, const Duration(seconds: 4));
    final word = QrcWord(Duration.zero, const Duration(seconds: 1), '原文');
    final sync = Qrc([
      QrcLine(Duration.zero, const Duration(seconds: 1), [word], '訳文')
        ..romanization = 'genbun'
    ]);
    final syncedRows = lyricSearchRows(sync, project: lyricReadingText);
    expect(filterLyricSearchRows(syncedRows, '訳文 genbun 原文'), hasLength(1));
    expect((sync.lines.single as QrcLine).words.single, same(word));
  });

  test('plain hits retain CRLF, blank lines and UTF-16 character positions',
      () {
    final lyric = PlainLyric('🎵 opening\r\n\r\n  안녕 hello 🌧\n終わり');
    final rows = lyricSearchRows(lyric, project: lyricReadingText);
    expect(rows.map((row) => row.index), [0, 0, 0]);
    final hit = filterLyricSearchRows(rows, 'hello').single;
    expect(hit.target.textOffset, lyric.text.indexOf('hello'));
    final emoji = filterLyricSearchRows(rows, '🌧').single;
    expect(emoji.target.textOffset, lyric.text.indexOf('🌧'));
    expect(lyric.lines, hasLength(1));
    expect(lyric.lines.single.start, Duration.zero);
    expect(hit.target.belongsTo(lyric), isTrue);
  });

  test('single unbroken plain paragraph reveals the actual query position', () {
    final lyric = PlainLyric('${'prefix ' * 600}UniqueNeedle after');
    final hit = filterLyricSearchRows(
            lyricSearchRows(lyric, project: lyricReadingText), 'uniqueneedle')
        .single;
    expect(hit.target.textOffset, lyric.text.indexOf('UniqueNeedle'));
    expect(hit.target.line, same(lyric.lines.single));
  });

  test('target rejects equal text in another document or a replaced line', () {
    final lyric = PlainLyric('same words');
    final target =
        lyricSearchRows(lyric, project: lyricReadingText).single.target;
    expect(target.belongsTo(PlainLyric('same words')), isFalse);
    lyric.lines[0] = PlainLyricLine('same words');
    expect(target.belongsTo(lyric), isFalse);
  });

  test('empty queries, absent matches and timed filters preserve source order',
      () {
    final lyric = Lrc([
      LrcLine(const Duration(seconds: 9), 'second', isBlank: false),
      LrcLine(const Duration(seconds: 2), 'first', isBlank: false),
    ], LrcSource.local);
    final rows = lyricSearchRows(lyric,
        project: lyricReadingText,
        includeLine: (line) => line.start.inSeconds > 5);
    expect(filterLyricSearchRows(rows, ' \n '), rows);
    expect(filterLyricSearchRows(rows, 'missing'), isEmpty);
    expect(rows.single.index, 0);
    expect(lyric.lines.map((line) => line.start.inSeconds), [9, 2]);
  });
}
