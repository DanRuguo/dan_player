import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("custom lyric API uses metadata query and parses LRC JSON", () async {
    final requests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          "type": "lrc",
          "lyric": "[00:01.00]Hello\n[00:02.00]World",
          "translation": "[00:01.00]你好",
        }),
      );
      request.response.close();
    });

    final previousApi = AppSettings.instance.lyricApiUrl;
    AppSettings.instance.lyricApiUrl =
        "http://127.0.0.1:${server.port}/lyric?token=abc";

    try {
      final audio = Audio(
        "Tagged Title",
        "Artist Name",
        "Album Name",
        0,
        123,
        null,
        null,
        r"C:\Music\File Name.mp3",
        0,
        0,
        null,
      );

      final lyric = await getMostMatchedLyric(audio);

      expect(lyric, isA<Lrc>());
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters["token"], "abc");
      expect(requests.single.queryParameters["title"], "Tagged Title");
      expect(requests.single.queryParameters["artist"], "Artist Name");
      expect(requests.single.queryParameters["album"], "Album Name");
      expect(requests.single.queryParameters["duration"], "123");
      expect(requests.single.queryParameters["fileName"], "File Name");
      expect(requests.single.queryParameters["displayTitle"], "File Name");

      final lines = (lyric as Lrc).lines.cast<LrcLine>();
      expect(lines, hasLength(2));
      expect(lines.first.content, "Hello┃你好");
      expect(lines.last.content, "World");
    } finally {
      AppSettings.instance.lyricApiUrl = previousApi;
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test("custom lyric API connectivity reports recognized lyrics", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          "type": "lrc",
          "lyric": "[00:01.00]Probe",
        }),
      );
      request.response.close();
    });

    try {
      final result = await testLyricApiConnectivity(
        "http://127.0.0.1:${server.port}/lyric",
      );

      expect(result.isReachable, isTrue);
      expect(result.lyricRecognized, isTrue);
      expect(result.statusCode, 200);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test("custom lyric API connectivity reports HTTP failure", () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late final StreamSubscription subscription;

    subscription = server.listen((request) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write("error");
      request.response.close();
    });

    try {
      final result = await testLyricApiConnectivity(
        "http://127.0.0.1:${server.port}/lyric",
      );

      expect(result.isReachable, isFalse);
      expect(result.lyricRecognized, isFalse);
      expect(result.statusCode, HttpStatus.internalServerError);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('multiple custom lyric sources fall through in saved order', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri.path);
      if (request.uri.path == '/first') {
        request.response.statusCode = HttpStatus.internalServerError;
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'type': 'lrc',
          'lyric': '[00:01.00]Second source',
        }));
      }
      await request.response.close();
    });
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    CustomMusicSourceProfile source(String id, String path) =>
        CustomMusicSourceProfile.tryCreate(
          id: id,
          name: id,
          baseUrl: 'http://127.0.0.1:${server.port}',
          capabilities: const {CustomMusicSourceCapability.lyrics},
          endpoints: {CustomMusicSourceCapability.lyrics: path},
        )!;
    AppSettings.instance.customMusicSources.value = [
      source('first', '/first'),
      source('second', '/second'),
    ];
    final audio = Audio(
      'Tagged Title',
      'Artist',
      'Album',
      0,
      120,
      null,
      null,
      r'C:\Music\track.mp3',
      0,
      0,
      null,
    );

    final lyric = await getMostMatchedLyric(audio);

    expect(((lyric as Lrc).lines.single as LrcLine).content, 'Second source');
    expect(requests, ['/first', '/second']);
  });

  test('an edited profile cannot publish a stale in-flight lyric', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      if (!requested.isCompleted) requested.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'type': 'lrc',
        'lyric': '[00:01.00]Stale lyric',
      }));
      await request.response.close();
    });
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'lyric-race',
      name: 'Lyric race',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {CustomMusicSourceCapability.lyrics},
      endpoints: const {CustomMusicSourceCapability.lyrics: '/lyrics'},
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final audio = Audio(
      'Tagged Title',
      'Artist',
      'Album',
      0,
      120,
      null,
      null,
      r'C:\Music\track.mp3',
      0,
      0,
      null,
    );

    final pending = getMostMatchedLyric(
      audio,
      candidateSearch: (_) async =>
          LyricSearchResponse(candidates: const [], failures: const {}),
    );
    await requested.future;
    AppSettings.instance.customMusicSources.value = [
      profile.copyWith(enabled: false),
    ];
    release.complete();

    expect(await pending, isNull);
  });

  test('custom lyric choices keep metadata sources and scope go identities',
      () {
    CustomMusicSourceProfile profile(
      String id,
      CustomMusicSourceProtocol protocol,
    ) =>
        CustomMusicSourceProfile.tryCreate(
          id: id,
          name: id,
          baseUrl: 'https://example.com',
          protocol: protocol,
          capabilities: const {CustomMusicSourceCapability.lyrics},
          endpoints: const {CustomMusicSourceCapability.lyrics: '/lyrics'},
        )!;
    final dan = profile('dan-lyrics', CustomMusicSourceProtocol.danSourceV1);
    final go = profile('go-lyrics', CustomMusicSourceProtocol.goMusicApi);
    final legacy = CustomMusicSourceProfile.legacyLyric(
      'https://example.com/legacy-lyrics',
    )!;
    final disabled = profile('disabled', CustomMusicSourceProtocol.danSourceV1)
        .copyWith(enabled: false);
    final local = Audio(
      'Tagged Title',
      'Artist',
      'Album',
      0,
      120,
      null,
      null,
      r'C:\Music\track.mp3',
      0,
      0,
      null,
    );

    expect(
      customLyricSourceChoicesFor(
        local,
        profiles: [dan, go, legacy, disabled],
      ).map((choice) => choice.profile.id),
      ['dan-lyrics', CustomMusicSourceProfile.legacyLyricProfileId],
    );

    final descriptor = base64Url
        .encode(utf8.encode(jsonEncode({
          'id': 'opaque-song',
          'source': 'netease',
          'name': 'Tagged Title',
        })))
        .replaceAll('=', '');
    final owned = Audio.online(
      provider: go.providerId,
      id: 'gma1.$descriptor',
      title: 'Tagged Title',
      artist: 'Artist',
      album: 'Album',
      duration: 120,
    );
    expect(
      customLyricSourceChoicesFor(owned, profiles: [go])
          .map((choice) => choice.profile.id),
      ['go-lyrics'],
    );
    expect(
      customLyricSourceChoicesFor(
        Audio.online(
          provider: go.providerId,
          id: 'broken',
          title: 'Tagged Title',
          artist: 'Artist',
          album: 'Album',
          duration: 120,
        ),
        profiles: [go],
      ),
      isEmpty,
    );
  });

  test(
      'explicit custom lyric choice discards an equal rebuilt profile response',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    final release = Completer<void>();
    final subscription = server.listen((request) async {
      if (!requested.isCompleted) requested.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'type': 'lrc',
        'lyric': '[00:01.00]Late explicit lyric',
      }));
      await request.response.close();
    });
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'explicit-race',
      name: 'Explicit race',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {CustomMusicSourceCapability.lyrics},
      endpoints: const {CustomMusicSourceCapability.lyrics: '/lyrics'},
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final audio = Audio(
      'Tagged Title',
      'Artist',
      'Album',
      0,
      120,
      null,
      null,
      r'C:\Music\track.mp3',
      0,
      0,
      null,
    );

    final pending = getLyricForCustomSourceChoice(
      audio,
      CustomLyricSourceChoice(profile),
    );
    await requested.future;
    final replacement = profile.copyWith();
    expect(replacement, profile);
    expect(identical(replacement, profile), isFalse);
    AppSettings.instance.customMusicSources.value = [replacement];
    release.complete();

    expect(await pending, isNull);
  });
}
