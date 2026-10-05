import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a revoked candidate group cannot return its earlier ordinary fallback',
      () async {
    final audio = Audio('Song', 'Artist', 'Album', 0, 120, null, null,
        'fixture/song.mp3', 0, 0, null);
    final fallback = Lrc.fromLrcText('[00:01]Old selection', LrcSource.local)!;
    final pending = Completer<Lyric?>();
    final secondStarted = Completer<void>();
    var current = true;
    final result = getMostMatchedLyric(audio,
        candidateSearch: (_) async => LyricSearchResponse(candidates: [
              SongSearchResult(ResultSource.qq, 'Song', 'Artist', 'Album', .9,
                  qqSongId: 1),
              SongSearchResult(
                  ResultSource.netease, 'Song', 'Artist', 'Album', .9,
                  neteaseSongId: '2'),
            ], failures: const {}),
        candidateLyricLoader: (candidate) {
          if (candidate.qqSongId == 1) return Future.value(fallback);
          secondStarted.complete();
          return pending.future;
        },
        stillCurrent: () => current);
    await secondStarted.future;
    current = false;
    pending.completeError(
        StateError('The old provider failed after a new choice'));
    expect(await result, isNull);
  });

  for (final failure in [false, true]) {
    test(
        'retired QQ word lookup starts no ordinary fallback (failure=$failure)',
        () async {
      final pending = Completer<Lyric?>();
      var current = true;
      var ordinaryRequests = 0;
      final result = getOnlineLyric(
          qqSongId: 1,
          qqWordLoader: (_) => pending.future,
          qqPayloadLoader: (_, __) async {
            ordinaryRequests++;
            return const {
              'code': 0,
              'lyric': '[00:01]Unwanted fallback',
            };
          },
          stillCurrent: () => current);
      current = false;
      if (failure) {
        pending.completeError(StateError('Old word endpoint failed'));
      } else {
        pending.complete(null);
      }
      expect(await result, isNull);
      expect(ordinaryRequests, 0);
    });
  }

  for (final revoke in ['owner', 'profile']) {
    test('retired Kugou metadata starts no lyric request (revoke=$revoke)',
        () async {
      const hash = 'abcdef1234567890abcdef1234567890';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final metadataStarted = Completer<void>();
      final releaseMetadata = Completer<void>();
      var lyricRequests = 0;
      final subscription = server.listen((request) async {
        if (request.uri.path == '/info') {
          metadataStarted.complete();
          await releaseMetadata.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'status': 1,
            'data': {
              'hash': hash,
              'songname': 'Song',
              'singername': 'Artist',
              'duration': 120,
            }
          }));
        } else {
          lyricRequests++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'candidates': []}));
        }
        await request.response.close();
      });
      final previous = AppSettings.instance.customMusicSources.value;
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'kugou',
        name: 'Local Kugou ownership fixture',
        baseUrl: 'http://127.0.0.1:${server.port}/',
        protocol: CustomMusicSourceProtocol.kugou,
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.lyrics,
        },
        endpoints: const {
          CustomMusicSourceCapability.search: 'search',
          CustomMusicSourceCapability.metadata: 'info',
          CustomMusicSourceCapability.lyrics: 'lyrics/',
        },
      )!;
      AppSettings.instance.customMusicSources.value = [profile];
      addTearDown(() async {
        AppSettings.instance.customMusicSources.value = previous;
        if (!releaseMetadata.isCompleted) releaseMetadata.complete();
        await subscription.cancel();
        await server.close(force: true);
      });
      var current = true;
      final result =
          getOnlineLyric(kugouSongHash: hash, stillCurrent: () => current);
      await metadataStarted.future;
      if (revoke == 'owner') {
        current = false;
      } else {
        AppSettings.instance.customMusicSources.value = [];
      }
      releaseMetadata.complete();
      expect(await result, isNull);
      expect(lyricRequests, 0,
          reason: 'An obsolete metadata response grants no new request.');
    });
  }

  for (final stage in ['search', 'krc']) {
    test('retired Kugou $stage response starts no further download', () async {
      await _withDelayedKugouLyrics(stage, (fixture) async {
        final result = getOnlineLyric(
            kugouSongHash: _kugouHash, stillCurrent: () => fixture.current);
        await fixture.started.future;
        fixture.current = false;
        fixture.release.complete();
        expect(await result, isNull);
        expect(fixture.downloads, stage == 'search' ? isEmpty : ['krc']);
      });
    });
  }

  test('retired custom candidate starts no download after lyric search',
      () async {
    await _withDelayedKugouLyrics('search', (fixture) async {
      final candidate = SongSearchResult(
          ResultSource.kugou, 'Song', 'Artist', 'Album', .9,
          customProfile: fixture.profile, customAudio: fixture.audio);
      final result =
          getLyricForCandidate(candidate, stillCurrent: () => fixture.current);
      await fixture.started.future;
      fixture.current = false;
      fixture.release.complete();
      expect(await result, isNull);
      expect(fixture.downloads, isEmpty);
    });
  });

  test('removed custom choice starts no LRC fallback after a late KRC failure',
      () async {
    await _withDelayedKugouLyrics('krc', (fixture) async {
      final result = getLyricForCustomSourceChoice(
          fixture.audio, CustomLyricSourceChoice(fixture.profile));
      await fixture.started.future;
      AppSettings.instance.customMusicSources.value = [];
      fixture.release.complete();
      expect(await result, isNull);
      expect(fixture.downloads, ['krc']);
    });
  });

  for (final stage in ['search', 'krc']) {
    test('retired custom choice $stage response starts no further download',
        () async {
      await _withDelayedKugouLyrics(stage, (fixture) async {
        final result = getLyricForCustomSourceChoice(
            fixture.audio, CustomLyricSourceChoice(fixture.profile),
            stillCurrent: () => fixture.current);
        await fixture.started.future;
        fixture.current = false;
        fixture.release.complete();
        expect(await result, isNull);
        expect(fixture.downloads, stage == 'search' ? isEmpty : ['krc']);
      });
    });
  }

  test('ownership check cancels its transport listeners and race exactly once',
      () async {
    var current = true;
    var cancellations = 0;
    final token = CustomMusicSourceCancellation(stillCurrent: () => current);
    token.onCancel(() => cancellations++);
    final pending = Completer<void>();
    final cancelled = expectLater(
        token.race(pending.future), throwsA(isA<CustomMusicSourceCancelled>()));
    current = false;
    expect(token.isCancelled, isFalse,
        reason: 'Ownership is observed at I/O checks without a polling timer.');
    expect(token.check, throwsA(isA<CustomMusicSourceCancelled>()));
    expect(token.isCancelled, isTrue);
    await cancelled;
    token.cancel();
    expect(token.check, throwsA(isA<CustomMusicSourceCancelled>()));
    expect(cancellations, 1);
    pending.complete();
  });

  test('an explicit custom choice cancel still cancels a current owner',
      () async {
    await _withDelayedKugouLyrics('search', (fixture) async {
      final cancellation = LyricSearchCancellation();
      final result = getLyricForCustomSourceChoice(
          fixture.audio, CustomLyricSourceChoice(fixture.profile),
          cancellation: cancellation, stillCurrent: () => fixture.current);
      await fixture.started.future;
      final cancelled =
          expectLater(result, throwsA(isA<CustomMusicSourceCancelled>()));
      cancellation.cancel();
      await cancelled;
      fixture.release.complete();
      expect(fixture.current, isTrue);
      expect(fixture.downloads, isEmpty);
    });
  });
}

const _kugouHash = 'abcdef1234567890abcdef1234567890';

class _DelayedKugouLyrics {
  _DelayedKugouLyrics(this.profile)
      : audio = Audio.online(
          provider: profile.providerId,
          id: _kugouHash,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 120,
        );

  final CustomMusicSourceProfile profile;
  final Audio audio;
  final started = Completer<void>();
  final release = Completer<void>();
  final downloads = <String>[];
  bool current = true;
}

Future<void> _withDelayedKugouLyrics(String delayedStage,
    Future<void> Function(_DelayedKugouLyrics fixture) run) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final previous = AppSettings.instance.customMusicSources.value;
  final profile = CustomMusicSourceProfile.tryCreate(
    id: 'kugou',
    name: 'Local Kugou stage ownership fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/',
    protocol: CustomMusicSourceProtocol.kugou,
    capabilities: const {
      CustomMusicSourceCapability.search,
      CustomMusicSourceCapability.metadata,
      CustomMusicSourceCapability.lyrics,
    },
    endpoints: const {
      CustomMusicSourceCapability.search: 'search',
      CustomMusicSourceCapability.metadata: 'info',
      CustomMusicSourceCapability.lyrics: 'lyrics/',
    },
  )!;
  final fixture = _DelayedKugouLyrics(profile);
  final subscription = server.listen((request) async {
    final stage = switch (request.uri.path) {
      '/lyrics/search' => 'search',
      '/lyrics/download' => request.uri.queryParameters['fmt'],
      _ => 'metadata',
    };
    if (request.uri.path == '/lyrics/download') {
      fixture.downloads.add(stage!);
    }
    if (stage == delayedStage) {
      fixture.started.complete();
      await fixture.release.future;
    }
    final body = switch (stage) {
      'metadata' => {
          'status': 1,
          'data': {
            'hash': _kugouHash,
            'songname': 'Song',
            'singername': 'Artist',
            'duration': 120,
          },
        },
      'search' => {
          'status': 200,
          'candidates': [
            {
              'id': 'owned-lyric',
              'accesskey': 'local-access',
              'song': 'Song',
              'singer': 'Artist',
              'duration': 120000,
            },
          ],
        },
      'krc' => {'status': 200, 'content': 'invalid KRC response'},
      _ => {
          'status': 200,
          'content': base64Encode(utf8.encode('[00:01]Obsolete fallback')),
        },
    };
    // Revocation can close this client's socket while the deliberately late
    // server response is being released. That is the expected transport path.
    try {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
      await request.response.close();
    } on HttpException {
      // The request was cancelled by its former owner.
    } on SocketException {
      // The request was cancelled by its former owner.
    }
  });
  AppSettings.instance.customMusicSources.value = [profile];
  try {
    await run(fixture);
  } finally {
    AppSettings.instance.customMusicSources.value = previous;
    if (!fixture.release.isCompleted) fixture.release.complete();
    await subscription.cancel();
    await server.close(force: true);
  }
}
