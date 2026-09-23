import 'dart:io';
import 'dart:convert';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/lyric/online_lyric_parser.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Audio audio() => Audio(
    'Song', 'Artist', 'Album', 0, 180, null, null, 'song.mp3', 0, 0, null);
Lyric plain() => Lrc.fromLrcText('[00:01.00]plain', LrcSource.web)!;
Lyric words() =>
    parseOnlineLyricPayload({'qrc': '[1000,2000]word(1000,2000)'})!;
SongSearchResult candidate(ResultSource source, double score, int id) =>
    SongSearchResult(source, 'Song', 'Artist', 'Album', score, qqSongId: id);
Future<Lyric?> match(List<SongSearchResult> candidates,
        Future<Lyric?> Function(SongSearchResult) load,
        {bool Function()? active}) =>
    getMostMatchedLyric(audio(),
        candidateSearch: (_) async =>
            LyricSearchResponse(candidates: candidates, failures: {}),
        candidateLyricLoader: load,
        stillCurrent: active);

void main() {
  test(
      'equal displayed percentages cannot let hidden decimals bypass word priority',
      () async {
    final result = await match([
      candidate(ResultSource.qq, .951, 1),
      candidate(ResultSource.netease, .947, 2)
    ], (c) async => c.qqSongId == 1 ? plain() : words());
    expect(hasWordTiming(result), isTrue);
    final ordered = [
      candidate(ResultSource.netease, .951, 2),
      candidate(ResultSource.qq, .947, 1)
    ]..sort(compareLyricCandidates);
    expect(ordered.first.source, ResultSource.qq);
  });
  test(
      'multiple searchable custom sources retain identity and follow saved priority',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(request.uri.path.endsWith('search')
          ? {
              'tracks': [
                {
                  'id': 'same-id',
                  'title': 'Song',
                  'artist': 'Artist',
                  'album': 'Album',
                  'duration': 180
                }
              ]
            }
          : {'lyric': '[00:01.00]${request.uri.path}'}));
      await request.response.close();
    });
    final settings = AppSettings.instance;
    final profiles = settings.customMusicSources.value;
    final builtins = settings.onlineSources.value;
    final lrclib = settings.lrclibEnabled.value;
    addTearDown(() async {
      settings.customMusicSources.value = profiles;
      settings.onlineSources.value = builtins;
      settings.lrclibEnabled.value = lrclib;
      await subscription.cancel();
      await server.close(force: true);
    });
    CustomMusicSourceProfile profile(String id) =>
        CustomMusicSourceProfile.tryCreate(
            id: id,
            name: id,
            baseUrl: 'http://127.0.0.1:${server.port}',
            capabilities: {
              CustomMusicSourceCapability.search,
              CustomMusicSourceCapability.lyrics
            },
            endpoints: {
              CustomMusicSourceCapability.search: '/$id/search',
              CustomMusicSourceCapability.lyrics: '/$id/lyrics'
            })!;
    settings.customMusicSources.value = [profile('second'), profile('first')];
    settings.onlineSources.value =
        const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false);
    settings.lrclibEnabled.value = false;
    final response = await searchLyricCandidates(audio());
    expect(response.candidates.map((c) => c.customProfile!.id),
        ['second', 'first']);
    expect(response.candidates.map((c) => c.identity).toSet(), hasLength(2));
    final result = await getMostMatchedLyric(audio(),
        candidateSearch: (_) async => response);
    expect((result!.lines.single as UnsyncLyricLine).content, '/second/lyrics');
  });
  test(
      'manual hides sub-60 matches but retains explicitly unscored results; automatic rejects them',
      () async {
    final unknown = SongSearchResult(
        ResultSource.kugou, 'Unverified', '', '', 1,
        scoreVerified: false);
    final boundary = candidate(ResultSource.qq, .6, 2);
    final low = candidate(ResultSource.netease, .59, 3);
    expect(visibleManualLyricCandidates([unknown, low, boundary]),
        [boundary, unknown]);
    final loaded = <SongSearchResult>[];
    await match([unknown, low, boundary], (c) async {
      loaded.add(c);
      return null;
    });
    expect(loaded, [boundary]);
  });
  test('a higher plain match wins before lower word lyrics are requested',
      () async {
    final loaded = <int?>[];
    final result = await match([
      candidate(ResultSource.netease, .9, 2),
      candidate(ResultSource.qq, .95, 1)
    ], (c) async {
      loaded.add(c.qqSongId);
      return c.qqSongId == 1 ? plain() : words();
    });
    expect(hasWordTiming(result), isFalse);
    expect(loaded, [1]);
  });
  test('same scores prefer word timing then QQ Netease LRCLIB order', () async {
    final loaded = <ResultSource>[];
    final result = await match([
      candidate(ResultSource.lrclib, .9, 3),
      candidate(ResultSource.netease, .9, 2),
      candidate(ResultSource.qq, .9, 1)
    ], (c) async {
      loaded.add(c.source);
      return c.source == ResultSource.netease ? words() : plain();
    });
    expect(hasWordTiming(result), isTrue);
    expect(loaded, [ResultSource.qq, ResultSource.netease]);
  });
  test(
      'failed candidates fall through to 60 percent inclusive and stop below it',
      () async {
    final loaded = <int?>[];
    await match([
      candidate(ResultSource.qq, .95, 1),
      candidate(ResultSource.qq, .6, 2),
      candidate(ResultSource.qq, .599, 3)
    ], (c) async {
      loaded.add(c.qqSongId);
      if (c.qqSongId == 1) throw const FormatException();
      return null;
    });
    expect(loaded, [1, 2]);
  });
  test('cancellation blocks remaining candidates', () async {
    var active = true;
    final loaded = <int?>[];
    await match([
      candidate(ResultSource.qq, 1, 1),
      candidate(ResultSource.netease, .9, 2)
    ], (c) async {
      loaded.add(c.qqSongId);
      active = false;
      return null;
    }, active: () => active);
    expect(loaded, [1]);
  });
  test('custom priority follows settings and cannot displace a tied built-in',
      () {
    final a =
        CustomMusicSourceProfile.legacyLyric('https://one.example/lyrics')!;
    final b = CustomMusicSourceProfile.tryCreate(
        id: 'two',
        name: 'Two',
        baseUrl: 'https://two.example',
        capabilities: {CustomMusicSourceCapability.lyrics})!;
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    SongSearchResult custom(CustomMusicSourceProfile profile) =>
        SongSearchResult(ResultSource.kugou, 'Song', 'Artist', 'Album', .9,
            customProfile: profile, customAudio: audio());
    final first = custom(a),
        second = custom(b),
        builtin = candidate(ResultSource.lrclib, .9, 3);
    AppSettings.instance.customMusicSources.value = [b, a];
    final ordered = [first, builtin, second]..sort(compareLyricCandidates);
    expect(ordered, [builtin, second, first]);
  });
  test(
      'explicit instrumental markers remain distinct from empty/uncollected responses',
      () async {
    await expectLater(
        getNeteaseLyric('123',
            payloadLoader: (_) async => {'code': 200, 'nolyric': true}),
        throwsA(isA<InstrumentalLyric>()));
    expect(
        await getNeteaseLyric('123',
            payloadLoader: (_) async => {'code': 200, 'uncollected': true}),
        isNull);
    await expectLater(
        getLrclibLyric(1, payloadLoader: (_) async => {'instrumental': true}),
        throwsA(isA<InstrumentalLyric>()));
    await expectLater(
        getQqPublicLyric(
            songId: 1,
            throwOnFailure: true,
            payloadLoader: (_, __) async => {'code': 0, 'nolyric': true}),
        throwsA(isA<InstrumentalLyric>()));
  });
  test(
      'confirmed instrumental does not fall through to a lower unrelated match',
      () async {
    final loaded = <int?>[];
    await expectLater(
        match([
          candidate(ResultSource.qq, .95, 1),
          candidate(ResultSource.qq, .6, 2)
        ], (c) async {
          loaded.add(c.qqSongId);
          throw const InstrumentalLyric();
        }),
        throwsA(isA<InstrumentalLyric>()));
    expect(loaded, [1]);
  });
}
