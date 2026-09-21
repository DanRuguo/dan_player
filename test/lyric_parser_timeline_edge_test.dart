import 'dart:convert';

import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final format in const ['qrc', 'krc', 'yrc']) {
    String row(int start, int length, String content, int wordLength) =>
        switch (format) {
          'qrc' => '[$start,$length]$content($start,$wordLength)',
          'krc' => '[$start,$length]<0,$wordLength,0>$content',
          _ => '[$start,$length]($start,$wordLength,0)$content',
        };
    Lyric parse(List<String> rows) =>
        parseOnlineLyricPayload({format: rows.join('\n')})!;

    test('$format sorts source rows stably before binary timeline lookup', () {
      final lyric = parse([
        row(4000, 1000, 'third', 1000),
        row(1000, 1000, 'first', 1000),
        row(1000, 1000, 'second', 1000),
      ]);
      expect(lyric.lines.cast<SyncLyricLine>().map((line) => line.content),
          ['first', 'second', 'third']);
      expect(findCurrentLyricLineIndex(lyric.lines, const Duration(seconds: 2)),
          1);
    });

    test('$format does not create an interlude inside an overlapping voice',
        () {
      final lyric = parse([
        row(0, 20000, 'sustained', 20000),
        row(2000, 1000, 'short', 1000),
        row(12000, 1000, 'next', 1000),
      ]);
      expect(lyric.lines.cast<SyncLyricLine>().where((l) => l.words.isEmpty),
          isEmpty);
    });

    test('$format derives interludes from actual word ends too', () {
      final lyric = parse([
        row(0, 1000, 'long word', 9000),
        row(10000, 1000, 'next', 1000),
        row(20000, 1000, 'after gap', 1000),
      ]);
      final blanks = lyric.lines
          .cast<SyncLyricLine>()
          .where((l) => l.words.isEmpty)
          .toList();
      expect(blanks, hasLength(1));
      expect(blanks.single.start, const Duration(seconds: 11));
      expect(blanks.single.length, const Duration(seconds: 9));
    });
  }

  test('KRC translation stays with its source row after sorting', () {
    final language = base64Encode(utf8.encode(jsonEncode({
      'content': [
        {
          'type': 1,
          'lyricContent': [
            ['later translation'],
            ['earlier translation']
          ]
        }
      ]
    })));
    final lyric = Krc.fromKrcText('[language:$language]\n'
        '[4000,1000]<0,1000,0>later\n[1000,1000]<0,1000,0>earlier');
    expect(lyric.lines.cast<SyncLyricLine>().map((l) => l.translation),
        ['earlier translation', 'later translation']);
  });

  test('LRC expands repeated timestamps while preserving offset and text', () {
    final lyric = Lrc.fromLrcText(
        '[offset:250]\n'
        '[00:01][00:05.50][01:00.125]Repeat [bracket]',
        LrcSource.local)!;
    final rows = lyric.lines.cast<LrcLine>();
    expect(rows.map((l) => l.start.inMilliseconds), [750, 5250, 59875]);
    expect(rows.map((l) => l.content),
        ['Repeat [bracket]', 'Repeat [bracket]', 'Repeat [bracket]']);
    expect(rows.map((l) => l.length.inMilliseconds), [4500, 54625, 0]);
  });

  test('KRC Windows line endings preserve translated metadata and word text',
      () {
    final language = base64Encode(utf8.encode(jsonEncode({
      'content': [
        {
          'type': 1,
          'lyricContent': [
            ['translation']
          ]
        }
      ]
    })));
    final lyric = Krc.fromKrcText(
        '[language:$language]\r\n[1000,1000]<0,1000,0>word\r\n');
    final line = lyric.lines.single as SyncLyricLine;
    expect(line.content, 'word');
    expect(line.translation, 'translation');
  });

  test('LRC body brackets are text, not extra occurrences', () {
    final lines = LrcLine.fromLineAll(
        '[00:01] [00:03.250]Sing [00:05.000] literally', 2000);
    expect(lines.map((line) => line.start.inMilliseconds), [0, 1250]);
    expect(lines.map((line) => line.content),
        ['Sing [00:05.000] literally', 'Sing [00:05.000] literally']);
    expect(LrcLine.fromLine('[00:01][00:03]repeat')!.content, 'repeat');
  });

  test('large reversed LRC and repeated translations retain stable ordering',
      () {
    final source = [
      for (var i = 999; i >= 0; i--) '[${i ~/ 60}:${i % 60}]original-$i',
      for (var i = 999; i >= 0; i--) '[${i ~/ 60}:${i % 60}]translation-$i',
    ].join('\n');
    final lyric = Lrc.fromLrcText(source, LrcSource.web, separator: '┃')!;
    expect(lyric.lines.length, 1000);
    for (var i = 0; i < 1000; i++) {
      final line = lyric.lines[i] as LrcLine;
      expect(line.start.inSeconds, i);
      expect(line.content, 'original-$i┃translation-$i');
      expect(line.length.inSeconds, i == 999 ? 0 : 1);
    }
  });

  test('repeated timestamps also align translated and romanized word lines',
      () {
    final lyric = parseOnlineLyricPayload({
      'yrc': '[1000,1000](1000,1000,0)光\n[4000,1000](4000,1000,0)光',
      'ytlrc': '[00:01][00:04]Light',
      'yromalrc': '[00:01][00:04]hikari',
    })!;
    expect(lyric.lines.map((l) => l.romanization), ['hikari', 'hikari']);
    expect(lyric.lines.cast<SyncLyricLine>().map((l) => l.translation),
        ['Light', 'Light']);
  });

  test('millisecond timestamps align exactly without floating point loss', () {
    final lyric = parseOnlineLyricPayload({
      'yrc': '[1001,1000](1001,1000,0)光',
      'ytlrc': '[00:01.001]Light',
      'yromalrc': '[00:01.001]hikari',
    })!;
    expect(lyric.lines.single.romanization, 'hikari');
    expect((lyric.lines.single as SyncLyricLine).translation, 'Light');
    expect(LrcLine.fromLine('[00:04.015]a')!.start.inMilliseconds, 4015);
  });
}
