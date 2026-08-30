import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio({
  String title = 'Song A',
  String artist = 'Artist A',
  String album = 'Album A',
  String path = r'C:\Music\Song A.mp3',
}) =>
    Audio(
      title,
      artist,
      album,
      0,
      180,
      null,
      null,
      path,
      0,
      0,
      null,
    );

Map<String, Object?> _qqPayload(List<Object?> songs, {Object code = 0}) => {
      'code': code,
      'req': {
        'code': 0,
        'data': {
          'body': {'item_song': songs},
        },
      },
    };

Map<String, Object?> _neteasePayload(
  List<Object?> songs, {
  Object code = 200,
}) =>
    {
      'code': code,
      'result': {'songs': songs},
    };

Map<String, Object?> _qqSong(
  int id,
  String title, {
  String artist = 'Artist A',
  String album = 'Album A',
  String? mid,
}) =>
    {
      'id': id,
      if (mid != null) 'mid': mid,
      'name': title,
      'singer': [
        {'name': artist},
      ],
      'album': {'title': album},
    };

class _TestLyric extends Lyric {
  _TestLyric(super.lines);
}

Lyric _lyric(String text) => _TestLyric([
      LrcLine(Duration.zero, text, isBlank: false),
    ]);

void main() {
  test('normalization handles full-width text and common separators', () {
    expect(normalizeSongMatchText(' Ｓｏｎｇ－Ａ、Ｂ＆Ｃ '), 'songabc');

    final audio = _audio(title: 'Song-A', artist: 'Alice / Bob');
    final matching = computeSongMatchScore(
      audio,
      'song a',
      'Alice、Bob',
      'Album A',
    );
    final wrongTitle = computeSongMatchScore(
      audio,
      'Completely Different',
      'Alice、Bob',
      'Album A',
    );
    expect(matching, greaterThan(0.99));
    expect(matching, greaterThan(wrongTitle));
  });

  test('OP and short-version suffixes do not pollute query or relevance', () {
    final audio = _audio(
      title: '結想は花となる -OP- short ver.',
      artist: 'ウォルピスカーター',
      album: '結想は花となる',
    );

    expect(
      canonicalSongTitleForMatch(audio.title),
      '結想は花となる',
    );
    expect(
      songMatchSearchQuery(audio),
      '結想は花となる ウォルピスカーター',
    );
    final exact = computeSongMatchScore(
      audio,
      '結想は花となる',
      'ウォルピスカーター',
      '結想は花となる',
    );
    final unrelatedVersion = computeSongMatchScore(
      audio,
      'MURAMASA (Short ver.)',
      'V.A.',
      'PC Game Songs',
    );
    expect(exact, greaterThan(0.99));
    expect(exact, greaterThan(unrelatedVersion));
  });

  test('QQ parser skips bad rows and accepts ID plus MID', () {
    final results = parseQqLyricSearchPayload(
      _qqPayload([
        null,
        {'name': 'missing identity'},
        _qqSong(42, 'Song A', mid: 'MID42'),
      ]),
      _audio(),
      1,
    );

    expect(results, hasLength(1));
    expect(results.single.qqSongId, 42);
    expect(results.single.qqSongMid, 'MID42');
    expect(results.single.artists, 'Artist A');
  });

  test('Netease parser accepts old and new artist/album field shapes', () {
    final results = parseNeteaseLyricSearchPayload(
      _neteasePayload([
        {
          'id': '100',
          'name': 'Song A',
          'artists': [
            {'name': 'Artist A'},
          ],
          'album': {'name': 'Album A'},
        },
        {
          'id': 101,
          'name': 'Song B',
          'ar': [
            {'name': 'Artist B'},
          ],
          'al': {'name': 'Album B'},
        },
        {'id': 'not-a-number', 'name': 'bad'},
      ], code: '200'),
      _audio(),
      20,
    );

    expect(results, hasLength(2));
    expect(results.first.neteaseSongId, '100');
    expect(results.last.artists, 'Artist B');
    expect(results.last.album, 'Album B');
  });

  test('enabled providers start concurrently and failures stay isolated',
      () async {
    final qqResult = Completer<Object?>();
    final neteaseResult = Completer<Object?>();
    var qqStarted = false;
    var neteaseStarted = false;

    final search = searchLyricCandidates(
      _audio(),
      sources: const {ResultSource.qq, ResultSource.netease},
      maxAttempts: 1,
      qqSearch: (_, __) {
        qqStarted = true;
        return qqResult.future;
      },
      neteaseSearch: (_, __) {
        neteaseStarted = true;
        return neteaseResult.future;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(qqStarted, isTrue);
    expect(neteaseStarted, isTrue);
    qqResult.complete(_qqPayload([_qqSong(42, 'Song A')]));
    neteaseResult.completeError(const SocketException('offline'));

    final response = await search;
    expect(response.candidates, hasLength(1));
    expect(response.candidates.single.source, ResultSource.qq);
    expect(response.failures, contains(ResultSource.netease));
    expect(response.hasPartialFailure, isTrue);
  });

  test('QQ business code 2001 is retried only within the configured bound',
      () async {
    var calls = 0;
    final response = await searchLyricCandidates(
      _audio(),
      sources: const {ResultSource.qq},
      maxAttempts: 2,
      retryDelay: Duration.zero,
      qqSearch: (_, __) async {
        calls++;
        return calls == 1
            ? _qqPayload(const [], code: 2001)
            : _qqPayload([_qqSong(42, 'Song A')]);
      },
    );

    expect(calls, 2);
    expect(response.candidates, hasLength(1));
    expect(response.failures, isEmpty);
  });

  test('malformed provider data is not repeatedly requested', () async {
    var calls = 0;
    final response = await searchLyricCandidates(
      _audio(),
      sources: const {ResultSource.qq},
      maxAttempts: 3,
      retryDelay: Duration.zero,
      qqSearch: (_, __) async {
        calls++;
        return const {'code': 0};
      },
    );

    expect(calls, 1);
    expect(response.candidates, isEmpty);
    expect(response.failures, contains(ResultSource.qq));
  });

  test('aggregation happens before de-duplication and score sorting', () async {
    final songs = <Object?>[
      for (var index = 0; index < 7; index++)
        _qqSong(index + 1, 'Unrelated $index'),
      _qqSong(99, 'Song A'),
      _qqSong(99, 'Song A live', artist: 'Someone Else'),
    ];
    final response = await searchLyricCandidates(
      _audio(),
      sources: const {ResultSource.qq},
      perSourceLimit: 20,
      maxAttempts: 1,
      qqSearch: (_, __) async => _qqPayload(songs),
    );

    expect(response.candidates.first.qqSongId, 99);
    expect(
      response.candidates.where((candidate) => candidate.qqSongId == 99),
      hasLength(1),
    );
    expect(response.candidates, hasLength(8));
  });

  test(
      'cross-provider candidates rank the exact base title above version noise',
      () async {
    final audio = _audio(
      title: '結想は花となる -OP- short ver.',
      artist: 'ウォルピスカーター',
      album: '結想は花となる',
    );
    final seenQueries = <String>[];
    final response = await searchLyricCandidates(
      audio,
      sources: const {ResultSource.qq, ResultSource.netease},
      maxAttempts: 1,
      qqSearch: (query, _) async {
        seenQueries.add(query);
        return _qqPayload([
          _qqSong(
            9,
            'MURAMASA (Short ver.)',
            artist: 'V.A.',
            album: 'PC Game Songs',
          ),
        ]);
      },
      neteaseSearch: (query, _) async {
        seenQueries.add(query);
        return _neteasePayload([
          {
            'id': 3427740763,
            'name': '結想は花となる',
            'artists': [
              {'name': 'ウォルピスカーター'},
            ],
            'album': {'name': '結想は花となる'},
          },
        ]);
      },
    );

    expect(seenQueries, everyElement('結想は花となる ウォルピスカーター'));
    expect(response.candidates.first.source, ResultSource.netease);
    expect(response.candidates.first.neteaseSongId, '3427740763');
    expect(response.candidates.first.score,
        greaterThan(response.candidates.last.score));
  });

  test('title-only fallback survives local composer versus platform singer',
      () async {
    final audio = _audio(
      title: '結想は花となる -OP- short ver.',
      artist: '堀江晶太',
      album: 'as:9-nine- ARTEISIA',
    );
    final queries = <String>[];
    final response = await searchLyricCandidates(
      audio,
      sources: const {ResultSource.netease},
      maxAttempts: 2,
      neteaseSearch: (query, _) async {
        queries.add(query);
        if (query.contains('堀江晶太')) return _neteasePayload(const []);
        return _neteasePayload([
          {
            'id': 3427740763,
            'name': '結想は花となる',
            'artists': [
              {'name': 'ウォルピスカーター'},
            ],
            'album': {'name': '結想は花となる'},
          },
        ]);
      },
    );

    expect(queries, [
      '結想は花となる 堀江晶太',
      '結想は花となる',
    ]);
    expect(response.candidates, hasLength(1));
    expect(response.candidates.single.neteaseSongId, '3427740763');
    expect(response.candidates.single.score, greaterThan(0.7),
        reason:
            'an exact title remains usable when singer and composer differ');
  });

  test('anonymous Netease lyric payload is parsed with translation', () async {
    String? requestedId;
    final lyric = await getNeteaseLyric(
      '186016',
      payloadLoader: (songId) async {
        requestedId = songId;
        return {
          'code': 200,
          'lrc': {
            'version': 1,
            'lyric': '[00:01.00]結想は花となる',
          },
          'tlyric': {
            'version': 1,
            'lyric': '[00:01.00]思念化作花朵',
          },
          'romalrc': {'version': 0, 'lyric': null},
        };
      },
    );

    expect(requestedId, '186016');
    expect(lyric, isNotNull);
    expect(lyric!.lines, hasLength(1));
    final line = lyric.lines.single as LrcLine;
    expect(line.content, contains('結想は花となる'));
    expect(line.content, contains('思念化作花朵'));
  });

  test('Netease instrumental and missing lyric payloads stay unavailable', () {
    expect(parseNeteaseLyricPayload({'code': 200, 'nolyric': true}), isNull);
    expect(
      parseNeteaseLyricPayload({
        'code': 200,
        'lrc': {'version': 0, 'lyric': null},
      }),
      isNull,
    );
    expect(parseNeteaseLyricPayload(const []), isNull);
    expect(
      parseNeteaseLyricPayload({
        'code': 200,
        'uncollected': true,
        'lrc': {'version': 0, 'lyric': ''},
      }),
      isNull,
      reason: 'the public 結想は花となる record currently reports this shape',
    );
  });

  test('current anonymous QQ lyric payload decodes entities and translation',
      () async {
    int? requestedId;
    String? requestedMid;
    final lyric = await getQqPublicLyric(
      songId: 42,
      songMid: 'MID42',
      payloadLoader: (songId, songMid) async {
        requestedId = songId;
        requestedMid = songMid;
        return {
          'retcode': 0,
          'lyric': '[00&#58;01.00]Original&#10;',
          'trans': '[00&#58;01.00]译文&#10;',
        };
      },
    );

    expect(requestedId, 42);
    expect(requestedMid, 'MID42');
    expect(lyric, isNotNull);
    expect((lyric!.lines.single as LrcLine).content, contains('Original'));
    expect((lyric.lines.single as LrcLine).content, contains('译文'));
    expect(parseQqPublicLyricPayload({'retcode': 1}), isNull);
  });

  test('LRCLIB title-only fallback handles composer tagged as artist',
      () async {
    final audio = _audio(
      title: '結想は花となる -OP- short ver.',
      artist: '堀江晶太',
      album: 'as:9-nine- ARTEISIA',
    );
    final queries = <String>[];
    final response = await searchLyricCandidates(
      audio,
      sources: const {ResultSource.lrclib},
      maxAttempts: 1,
      lrclibSearch: (query, _) async {
        queries.add(query);
        if (query.contains('堀江晶太')) return const [];
        return [
          {
            'id': 38005804,
            'trackName': '結想は花となる',
            'artistName': 'ウォルピスカーター',
            'albumName': 'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK',
            'duration': 195,
            'instrumental': false,
            'plainLyrics': 'line one\nline two',
            'syncedLyrics': null,
          },
        ];
      },
    );

    expect(queries, ['結想は花となる 堀江晶太', '結想は花となる']);
    expect(response.candidates.single.source, ResultSource.lrclib);
    expect(response.candidates.single.lrclibId, 38005804);
    expect(response.candidates.single.score, greaterThan(0.7));
  });

  test('LRCLIB plain text remains untimed instead of gaining fake timestamps',
      () {
    final lyric = parseLrclibLyricPayload({
      'id': 38005804,
      'trackName': '結想は花となる',
      'artistName': 'ウォルピスカーター',
      'albumName': 'Album',
      'duration': 195,
      'instrumental': false,
      'plainLyrics': 'first line\nsecond line',
      'syncedLyrics': null,
    });

    expect(lyric, isA<PlainLyric>());
    expect(lyric!.lines, hasLength(1));
    expect(
      (lyric.lines.single as PlainLyricLine).content,
      'first line\nsecond line',
    );
  });

  test('LRCLIB prefers real synced LRC when the record provides it', () {
    final lyric = parseLrclibLyricPayload({
      'id': 1,
      'trackName': 'Song A',
      'artistName': 'Artist A',
      'albumName': 'Album A',
      'duration': 180,
      'instrumental': false,
      'plainLyrics': 'plain line',
      'syncedLyrics': '[00:01.00]synced line',
    });

    expect(lyric, isA<Lrc>());
    expect((lyric!.lines.single as LrcLine).content, 'synced line');
  });

  test('automatic matching falls through uncollected Netease to LRCLIB',
      () async {
    final candidates = [
      SongSearchResult(
        ResultSource.netease,
        '結想は花となる',
        'ウォルピスカーター',
        'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK',
        0.8,
        neteaseSongId: '3427740763',
      ),
      SongSearchResult(
        ResultSource.lrclib,
        '結想は花となる',
        'ウォルピスカーター',
        'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK',
        0.8,
        lrclibId: 38005804,
      ),
    ];
    final loaded = <ResultSource>[];
    final lyric = await getMostMatchedLyric(
      _audio(title: '結想は花となる -OP- short ver.', artist: '堀江晶太'),
      customLyricLoader: (_) async => null,
      candidateSearch: (_) async => LyricSearchResponse(
        candidates: candidates,
        failures: const {},
      ),
      candidateLyricLoader: (candidate) async {
        loaded.add(candidate.source);
        if (candidate.source == ResultSource.netease) {
          return parseNeteaseLyricPayload({
            'code': 200,
            'uncollected': true,
            'lrc': {'lyric': ''},
          });
        }
        return parseLrclibLyricPayload({
          'id': 38005804,
          'trackName': '結想は花となる',
          'artistName': 'ウォルピスカーター',
          'albumName': 'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK',
          'duration': 195,
          'instrumental': false,
          'plainLyrics': 'available fallback',
          'syncedLyrics': null,
        });
      },
    );

    expect(loaded, [ResultSource.netease, ResultSource.lrclib]);
    expect(lyric, isA<PlainLyric>());
  });

  test('default provider selection follows the shared source preferences',
      () async {
    final previous = AppSettings.instance.onlineSources.value;
    AppSettings.instance.onlineSources.value = const OnlineSourcePreferences(
      qqEnabled: false,
      neteaseEnabled: true,
    );
    var qqCalls = 0;
    var kugouCalls = 0;
    var neteaseCalls = 0;
    try {
      final response = await searchLyricCandidates(
        _audio(),
        maxAttempts: 1,
        qqSearch: (_, __) async {
          qqCalls++;
          return _qqPayload(const []);
        },
        kugouSearch: (_, __) async {
          kugouCalls++;
          return {
            'error_code': 0,
            'data': {'info': <Object?>[]},
          };
        },
        neteaseSearch: (_, __) async {
          neteaseCalls++;
          return _neteasePayload([
            {
              'id': 7,
              'name': 'Song A',
              'artists': [
                {'name': 'Artist A'},
              ],
              'album': {'name': 'Album A'},
            },
          ]);
        },
        lrclibSearch: (_, __) async => const [],
      );

      expect(qqCalls, 0);
      expect(kugouCalls, 2,
          reason: 'an empty contextual result falls back to title-only once');
      expect(neteaseCalls, 1);
      expect(response.candidates.single.source, ResultSource.netease);
    } finally {
      AppSettings.instance.onlineSources.value = previous;
    }
  });

  test('Kugou lyric fallback remains when both online-song sources are off',
      () async {
    final previous = AppSettings.instance.onlineSources.value;
    AppSettings.instance.onlineSources.value = const OnlineSourcePreferences(
      qqEnabled: false,
      neteaseEnabled: false,
    );
    var kugouCalls = 0;
    try {
      final response = await searchLyricCandidates(
        _audio(),
        maxAttempts: 1,
        qqSearch: (_, __) async => throw StateError('QQ must stay disabled'),
        neteaseSearch: (_, __) async =>
            throw StateError('Netease must stay disabled'),
        kugouSearch: (_, __) async {
          kugouCalls++;
          return {
            'error_code': 0,
            'data': {
              'info': [
                {
                  'songname': 'Song A',
                  'singername': 'Artist A',
                  'album_name': 'Album A',
                  'hash': 'HASH-A',
                },
              ],
            },
          };
        },
        lrclibSearch: (_, __) async => const [],
      );

      expect(kugouCalls, 1);
      expect(response.sourcesDisabled, isFalse);
      expect(response.candidates.single.source, ResultSource.kugou);
    } finally {
      AppSettings.instance.onlineSources.value = previous;
    }
  });

  test('automatic matching continues after missing and failed candidates',
      () async {
    final candidates = [
      SongSearchResult(ResultSource.qq, 'one', '', '', 1, qqSongId: 1),
      SongSearchResult(ResultSource.qq, 'two', '', '', 0.9, qqSongId: 2),
      SongSearchResult(ResultSource.qq, 'three', '', '', 0.8, qqSongId: 3),
    ];
    final loaded = <int?>[];
    final result = await getMostMatchedLyric(
      _audio(),
      customLyricLoader: (_) async => throw StateError('custom unavailable'),
      candidateSearch: (_) async => LyricSearchResponse(
        candidates: candidates,
        failures: const {},
      ),
      candidateLyricLoader: (candidate) async {
        loaded.add(candidate.qqSongId);
        if (candidate.qqSongId == 1) return null;
        if (candidate.qqSongId == 2) throw StateError('provider unavailable');
        return _lyric('third candidate');
      },
    );

    expect(result, isNotNull);
    expect((result!.lines.single as LrcLine).content, 'third candidate');
    expect(loaded, [1, 2, 3]);
  });

  test('an explicitly empty provider set reports disabled sources', () async {
    final response = await searchLyricCandidates(
      _audio(),
      sources: const {},
    );
    expect(response.sourcesDisabled, isTrue);
    expect(response.candidates, isEmpty);
    expect(response.failures, isEmpty);
  });
}
