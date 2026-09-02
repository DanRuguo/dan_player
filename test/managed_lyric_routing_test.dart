import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final settings = AppSettings.instance;
  final audio = Audio('Canon', 'Artist', 'Album', 0, 180, null, null,
      r'C:\Music\Canon.mp3', 0, 0, null);

  setUp(() {
    final sources = settings.onlineSources.value;
    final profiles = settings.customMusicSources.value;
    final lrclib = settings.lrclibEnabled.value;
    addTearDown(() {
      settings.onlineSources.value = sources;
      settings.customMusicSources.value = profiles;
      settings.lrclibEnabled.value = lrclib;
    });
    settings.onlineSources.value =
        const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false);
    settings.customMusicSources.value = [];
    settings.lrclibEnabled.value = false;
  });

  test('deleted and disabled Kugou have no hidden lyric network fallback',
      () async {
    await HttpOverrides.runZoned(() async {
      expect((await searchLyricCandidates(audio)).sourcesDisabled, isTrue);
      expect(await getOnlineLyric(kugouSongHash: 'old-saved-hash'), isNull);
      settings.customMusicSources.value = [
        CustomMusicSourceProfile.kugouPreset().copyWith(enabled: false),
      ];
      expect((await searchLyricCandidates(audio)).sourcesDisabled, isTrue);
      expect(await getOnlineLyric(kugouSongHash: 'old-saved-hash'), isNull);
    }, createHttpClient: (_) => throw StateError('Unexpected hidden request'));
  });

  test('Kugou candidate lookup honors edited profile and rejects stale choice',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(request.uri.path == '/edited-search'
          ? {
              'tracks': [
                {
                  'id': 'chosen-id',
                  'title': 'Canon',
                  'artist': 'Artist',
                  'album': 'Album'
                }
              ]
            }
          : {'lyric': '[00:01.00]Chosen lyric', 'type': 'lrc'}));
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'kugou',
      name: 'My renamed API',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.lyrics
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/edited-search',
        CustomMusicSourceCapability.lyrics: '/edited-lyrics'
      },
    )!;
    settings.customMusicSources.value = [profile];
    final result = await searchLyricCandidates(audio, maxAttempts: 1);
    final candidate = result.candidates.single;
    expect(candidate.sourceLabel, 'My renamed API');
    expect(candidate.kugouSongHash, 'chosen-id');
    expect(await getLyricForCandidate(candidate), isNotNull);
    expect(paths, ['/edited-search', '/edited-lyrics']);
    settings.customMusicSources.value = [profile.copyWith(name: 'Changed')];
    expect(await getLyricForCandidate(candidate), isNull);
    expect(paths, hasLength(2));
    expect(await getOnlineLyric(kugouSongHash: 'chosen-id'), isNotNull);
    expect(paths.last, '/edited-lyrics');
  });

  test('LRCLIB switch gates new candidate lookup independently', () async {
    var calls = 0;
    settings.lrclibEnabled.value = true;
    final enabled = await searchLyricCandidates(audio, maxAttempts: 1,
        lrclibSearch: (_, __) async {
      calls++;
      return [];
    });
    expect(enabled.sourcesDisabled, isFalse);
    expect(calls, greaterThan(0));
    settings.lrclibEnabled.value = false;
    final previousCalls = calls;
    final disabled = await searchLyricCandidates(audio, maxAttempts: 1,
        lrclibSearch: (_, __) async {
      calls++;
      return [];
    });
    expect(disabled.sourcesDisabled, isTrue);
    expect(calls, previousCalls);
  });
}
