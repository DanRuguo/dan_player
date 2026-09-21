import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/lyric/krc_decoder.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter_test/flutter_test.dart';

const wordText = '[1000,2000]Hello(1000,800) world(1800,1200)';
Lyric words() => parseOnlineLyricPayload({'qrc': wordText})!;
Lyric ordinary() => Lrc.fromLrcText('[00:01.00]Hello world', LrcSource.web)!;
Audio audio() => Audio(
    'Song', 'Artist', 'Album', 0, 180, null, null, 'song.mp3', 0, 0, null);
void main() {
  test('authored romanization stays aligned through cache and offset', () {
    final lyric = parseOnlineLyricPayload({
      'yrc': {'lyric': '[1000,2000](1000,2000,0)光'},
      'ytlrc': {'lyric': '[00:01.00]光芒'},
      'yromalrc': {'lyric': '[00:01.00]hikari'},
    })!;
    final restored =
        LyricSnapshot.fromJson(LyricSnapshot.capture(lyric).toJson())!
            .toLyric(offsetMs: 250);
    expect(restored.lines.single.romanization, 'hikari');
    expect(restored.lines.single.start.inMilliseconds, 1250);
    expect((restored.lines.single as SyncLyricLine).translation, '光芒');
    expect(
        (restored.lines.single as SyncLyricLine)
            .words
            .single
            .start
            .inMilliseconds,
        1250);
  });
  test('an unresponsive QQ word endpoint does not consume the fallback budget',
      () async {
    final pending = Completer<Lyric?>();
    final result = await getOnlineLyric(
        qqSongId: 1,
        qqWordLoader: (_) => pending.future,
        qqPayloadLoader: (_, __) async =>
            {'code': 0, 'lyric': '[00:01.00]available'});
    expect(result, isA<Lrc>());
  });

  test('metadata custom LRC can be upgraded by an exact-match word candidate',
      () async {
    final result = await getMostMatchedLyric(audio(),
        customLyricLoader: (_) async => ordinary(),
        candidateSearch: (_) async => LyricSearchResponse(candidates: [
              SongSearchResult(ResultSource.kugou, 'Song', 'Artist', 'Album', 1,
                  kugouSongHash: 'same')
            ], failures: {}),
        candidateLyricLoader: (_) async => words());
    expect(hasWordTiming(result), isTrue);
  });
  test('punctuation is preserved by all three word formats', () {
    for (final payload in [
      {'qrc': '[1000,2000]Hi (world) [yes](1000,2000)'},
      {'krc': '[1000,2000]<0,2000,0>Hi (world) [yes]'},
      {'yrc': '[1000,2000](1000,2000,0)Hi (world) [yes]'},
    ]) {
      final result = parseOnlineLyricPayload(payload)!;
      expect((result.lines.first as SyncLyricLine).content, 'Hi (world) [yes]');
    }
  });

  test('word response outranks ordinary fields regardless of declaration', () {
    final lyric = parseOnlineLyricPayload(
        {'type': 'lrc', 'lyric': '[00:01.00]ordinary', 'qrc': wordText});
    expect(hasWordTiming(lyric), isTrue);
    expect(
        (lyric!.lines.first as SyncLyricLine).words.last.start.inMilliseconds,
        1800);
  });
  test('damaged word variant falls back to ordinary', () {
    final lyric = parseOnlineLyricPayload({
      'qrc': '[broken]',
      'lrc': {'lyric': '[00:01.00]ordinary'}
    });
    expect(lyric, isA<Lrc>());
  });
  test('YRC keeps absolute word timing and translated timestamps', () {
    final lyric = parseOnlineLyricPayload({
      'yrc': {'lyric': '[1000,2000](1000,800,0)Hello(1800,1200,0) world'},
      'ytlrc': {'lyric': '[00:01.00]你好'}
    })!;
    final line = lyric.lines.first as SyncLyricLine;
    expect(line.words.last.start.inMilliseconds, 1800);
    expect(line.translation, '你好');
    expect(hasWordTiming(lyric), isTrue);
  });
  test('KRC tolerates trailing blank and unmatched translation count', () {
    final language = base64Encode(utf8.encode(jsonEncode({
      'content': [
        {
          'type': 1,
          'lyricContent': [
            ['译文']
          ]
        }
      ]
    })));
    final lyric = Krc.fromKrcText(
        '[language:$language]\n[1000,500]<0,500,0>Hello\n[2000,500]<0,500,0>World\n');
    expect(lyric.lines, hasLength(2));
    expect((lyric.lines.last as SyncLyricLine).translation, isNull);
    expect(hasWordTiming(lyric), isTrue);
  });
  test('compressed KRC decodes and expanded limit is enforced', () {
    String encode(String text) {
      const mask = [
        64,
        71,
        97,
        119,
        94,
        50,
        116,
        71,
        81,
        54,
        49,
        45,
        206,
        210,
        110,
        105
      ];
      final data = zlib.encode(utf8.encode(text));
      return base64Encode([
        107,
        114,
        99,
        49,
        for (var i = 0; i < data.length; i++) data[i] ^ mask[i % 16]
      ]);
    }

    expect(decodeKrcContainer(encode('hello')), 'hello');
    expect(() => decodeKrcContainer(encode('a' * (1024 * 1024 + 1))),
        throwsFormatException);
  });
  test('all matching providers are considered within an equal score', () async {
    final candidates = [
      for (var i = 0; i < 6; i++)
        SongSearchResult(ResultSource.qq, 'Song', 'Artist', 'Album', 1,
            qqSongId: i),
      SongSearchResult(ResultSource.kugou, 'Song', 'Artist', 'Album', 1,
          kugouSongHash: 'hash')
    ];
    final lyric = await getMostMatchedLyric(audio(),
        customLyricLoader: (_) async => null,
        candidateSearch: (_) async =>
            LyricSearchResponse(candidates: candidates, failures: {}),
        candidateLyricLoader: (c) async =>
            c.source == ResultSource.kugou ? words() : ordinary());
    expect(hasWordTiming(lyric), isTrue);
  });
  test('lower match word lyrics never replace higher match ordinary lyrics',
      () async {
    final loaded = <double>[];
    final candidates = [
      SongSearchResult(ResultSource.qq, 'Song', 'Artist', 'Album', 1,
          qqSongId: 1),
      SongSearchResult(ResultSource.kugou, 'Song', 'Artist', 'Album', .8,
          kugouSongHash: 'hash')
    ];
    final lyric = await getMostMatchedLyric(audio(),
        customLyricLoader: (_) async => null,
        candidateSearch: (_) async =>
            LyricSearchResponse(candidates: candidates, failures: {}),
        candidateLyricLoader: (c) async {
          loaded.add(c.score);
          return c.score == 1 ? ordinary() : words();
        });
    expect(hasWordTiming(lyric), isFalse);
    expect(loaded, [1]);
  });
  test('QQ prefers available QRC before ordinary endpoint', () async {
    var ordinaryRequests = 0;
    final result = await getOnlineLyric(
        qqSongId: 1,
        qqWordLoader: (_) async => words(),
        qqPayloadLoader: (_, __) async {
          ordinaryRequests++;
          return {'code': 0, 'lyric': '[00:01.00]ordinary'};
        });
    expect(hasWordTiming(result), isTrue);
    expect(ordinaryRequests, 0);
  });
  test('QQ word failure retains ordinary endpoint fallback', () async {
    final result = await getOnlineLyric(
        qqSongId: 1,
        qqWordLoader: (_) async => throw const FormatException('invalid'),
        qqPayloadLoader: (_, __) async =>
            {'code': 0, 'lyric': '[00:01.00]ordinary'});
    expect(result, isA<Lrc>());
  });
}
