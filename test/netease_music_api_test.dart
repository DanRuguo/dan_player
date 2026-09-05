import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NetEase preset is discoverable, disabled and round-trips all endpoints',
      () {
    final preset = CustomMusicSourceProfile.neteaseApiPreset();
    expect(preset.enabled, isFalse);
    expect(CustomMusicSourceProfile.builtInPresets(), contains(preset));
    expect(CustomMusicSourceProfile.fromJson(preset.toJson()), preset);
    expect(
        preset.capabilities, containsAll(CustomMusicSourceCapability.values));
    expect(preset.endpointFor(CustomMusicSourceCapability.comments)!.path,
        '/comment/music');
  });

  test('search maps old fields, selected details map modern fields and pin ID',
      () async {
    final requests = <Uri>[];
    await _server((request) {
      requests.add(request.uri);
      if (request.uri.path == '/api/search') {
        return {
          'code': 200,
          'result': {
            'songCount': 99,
            'songs': [
              {
                'id': 17706562,
                'name': 'Good Time',
                'artists': [
                  {'name': 'Owl City'},
                  {'name': 'Carly Rae Jepsen'}
                ],
                'album': {'name': 'Good Time'},
                'duration': 205933,
                'url': 'https://ignored.test/audio'
              },
              {'id': 'not-numeric', 'name': 'Invalid'},
            ]
          }
        };
      }
      return {
        'code': 200,
        'songs': [
          {'id': 999, 'name': 'Unrelated'},
          {
            'id': 17706562,
            'name': 'Good Time',
            'ar': [
              {'name': 'Owl City'},
              {'name': 'Carly Rae Jepsen'}
            ],
            'al': {
              'name': 'Good Time',
              'picUrl': 'https://images.test/cover.jpg'
            },
            'dt': 205933
          }
        ]
      };
    }, (transport) async {
      final result = await transport.search(' Good Time ', limit: 40);
      expect(result.tracks, hasLength(1));
      expect(result.tracks.single.onlineId, '17706562');
      expect(result.tracks.single.artist, 'Owl City / Carly Rae Jepsen');
      expect(result.tracks.single.duration, 205);
      expect(result.tracks.single.onlinePlayable, isNull);
      expect(result.tracks.single.onlineDownloadAllowed, isNull);
      expect(result.reachedLimit, isTrue);
      expect(requests, hasLength(1),
          reason: 'Search does not fetch N detail or audio URLs');
      final detail = await transport.metadata(result.tracks.single);
      expect(detail.onlineId, '17706562');
      expect(detail.artworkUrl, 'https://images.test/cover.jpg');
      expect(requests.first.queryParameters, {
        'tokenLabel': 'public',
        'keywords': 'Good Time',
        'type': '1',
        'limit': '25',
        'offset': '0'
      });
      expect(requests.last.queryParameters['ids'], '17706562');
    });
  });

  test('empty search and missing lyrics are honest empty/unavailable results',
      () async {
    await _server(
        (request) => request.uri.path.endsWith('search')
            ? {
                'code': 200,
                'result': {'songCount': 0}
              }
            : {'code': 200, 'nolyric': true}, (transport) async {
      expect((await transport.search('no match')).tracks, isEmpty);
      await expectLater(transport.lyrics(_track()),
          throwsA(_failure(CustomMusicSourceFailureKind.unavailable)));
    });
  });

  test('lyrics and comments expose true hot/latest pagination contracts',
      () async {
    final requests = <Uri>[];
    await _server((request) {
      requests.add(request.uri);
      if (request.uri.path.endsWith('lyric')) {
        return {
          'code': 200,
          'lrc': {'lyric': '[00:00.00]Good Time'},
          'tlyric': {'lyric': '[00:00.00]美好时光'}
        };
      }
      final hot = request.uri.path.endsWith('/hot');
      return {
        'code': 200,
        if (hot) 'hasMore': true else 'more': true,
        'total': 44,
        hot ? 'hotComments' : 'comments': [
          {
            'commentId': 123,
            'user': {'nickname': 'Listener'},
            'content': 'A comment',
            'time': 1760000000000,
            'likedCount': 7
          }
        ]
      };
    }, (transport) async {
      final lyrics = await transport.lyrics(_track());
      expect(lyrics.translation, '[00:00.00]美好时光');
      final normal = await transport.comments(_track(), page: 1, limit: 20);
      expect(normal.comments.single.author, 'Listener');
      expect(normal.supportedSorts,
          [CustomMusicCommentsSort.hot, CustomMusicCommentsSort.latest]);
      expect(normal.hasMore, isTrue);
      expect(requests.last.path, '/api/comment/music');
      expect(requests.last.queryParameters['offset'], '20');
      expect(requests.last.queryParameters.containsKey('sort'), isFalse);
      final hot = await transport.comments(_track(),
          page: 1, limit: 20, sort: CustomMusicCommentsSort.hot);
      expect(hot.hasMore, isTrue);
      expect(requests.last.path, '/api/comment/hot');
      expect(requests.last.queryParameters['type'], '0');
      expect(requests.last.queryParameters['tokenLabel'], 'public');
    });
  });

  test('download permission requires the dedicated download response',
      () async {
    final paths = <String>[];
    await _server((request) {
      paths.add(request.uri.path);
      final row = {
        'id': 17706562,
        'code': 200,
        'url': 'https://audio.test/full.mp3',
        'type': 'mp3',
        'expi': 1200,
        'freeTrialInfo': null
      };
      return {
        'code': 200,
        'data': request.uri.path.contains('download') ? row : [row]
      };
    }, (transport) async {
      expect((await transport.resolve(_track())).downloadAllowed, isFalse);
      expect(
          (await transport.resolve(_track(), forDownload: true))
              .downloadAllowed,
          isTrue);
      expect(paths, ['/api/song/url', '/api/song/download/url']);
    });
  });

  for (final sample in <String, Map>{
    'preview': {
      'id': 17706562,
      'code': 200,
      'url': 'https://audio.test/preview.mp3',
      'freeTrialInfo': {'start': 0, 'end': 30}
    },
    'unavailable': {'id': 17706562, 'code': -105, 'url': null},
    'wrong identity': {
      'id': 999,
      'code': 200,
      'url': 'https://audio.test/full.mp3'
    },
    'unsafe URL': {
      'id': 17706562,
      'code': 200,
      'url': 'https://secret@audio.test/full.mp3'
    },
  }.entries) {
    test('resolution rejects ${sample.key}', () async {
      await _server(
          (request) => {
                'code': 200,
                'data': [sample.value]
              }, (transport) async {
        await expectLater(transport.resolve(_track()),
            throwsA(isA<CustomMusicSourceException>()));
      });
    });
  }

  test(
      'foreign identity and undeclared capabilities are rejected without network',
      () async {
    var requests = 0;
    await _server((request) {
      requests++;
      return {'code': 200};
    }, (transport) async {
      final foreign = Audio.online(
          provider: 'netease',
          id: '17706562',
          title: 'Good Time',
          artist: 'Owl City',
          album: 'Good Time',
          duration: 205);
      await expectLater(transport.lyrics(foreign),
          throwsA(_failure(CustomMusicSourceFailureKind.unavailable)));
      final disabled = CustomMusicSourceTransport(
          transport.profile.copyWith(enabled: false));
      await expectLater(disabled.search('Good Time'),
          throwsA(_failure(CustomMusicSourceFailureKind.unavailable)));
      expect(requests, 0);
    });
  });

  test('API login status is preserved and response bodies stay bounded',
      () async {
    await _server((request) => {'code': 301}, (transport) async {
      await expectLater(transport.search('Good Time'),
          throwsA(_failure(CustomMusicSourceFailureKind.http)));
    });
    await _server((request) => {'code': 200, 'payload': 'x' * (256 * 1024)},
        (transport) async {
      await expectLater(transport.search('Good Time'),
          throwsA(_failure(CustomMusicSourceFailureKind.responseTooLarge)));
    });
  });

  test('pending NetEase requests respond to cancellation and one deadline',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<void>();
    server.listen((request) {
      if (!arrived.isCompleted) arrived.complete();
    });
    try {
      final transport = CustomMusicSourceTransport(_profile(server),
          requestTimeout: const Duration(milliseconds: 150));
      final token = CustomMusicSourceCancellation();
      final request = transport.search('Good Time', cancellation: token);
      final assertion =
          expectLater(request, throwsA(isA<CustomMusicSourceCancelled>()));
      await arrived.future;
      token.cancel();
      await assertion;
      await expectLater(transport.search('Good Time'),
          throwsA(_failure(CustomMusicSourceFailureKind.timeout)));
    } finally {
      await server.close(force: true);
    }
  });
}

Audio _track() => Audio.online(
    provider: 'custom:netease-api',
    id: '17706562',
    title: 'Good Time',
    artist: 'Owl City',
    album: 'Good Time',
    duration: 205);
Matcher _failure(CustomMusicSourceFailureKind kind) =>
    isA<CustomMusicSourceException>().having((e) => e.kind, 'kind', kind);
CustomMusicSourceProfile _profile(HttpServer server) =>
    CustomMusicSourceProfile.neteaseApiPreset().copyWith(
        baseUrl: 'http://127.0.0.1:${server.port}/api/',
        enabled: true,
        endpoints: {
          for (final entry
              in CustomMusicSourceProfile.neteaseApiPreset().endpoints.entries)
            entry.key: '${entry.value}?tokenLabel=public'
        });
Future<void> _server(Map Function(HttpRequest) response,
    Future<void> Function(CustomMusicSourceTransport) run) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(response(request)));
    await request.response.close();
  });
  try {
    await run(CustomMusicSourceTransport(_profile(server)));
  } finally {
    await server.close(force: true);
  }
}
