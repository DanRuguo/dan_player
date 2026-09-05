import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/online/kugou_music_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _hash = 'abcdef1234567890abcdef1234567890';

void main() {
  test(
      'verbose 25-song search pages fit while oversized responses stay bounded',
      () async {
    await _server((server) async {
      final payload = {
        'status': 1,
        'data': {
          'info': List.generate(
              25,
              (index) => {
                    ..._song(),
                    'hash': (index + 1).toRadixString(16).padLeft(32, '0'),
                    'extended_metadata': 'x' * 5600,
                  }),
        },
      };
      expect(utf8.encode(jsonEncode(payload)).length, greaterThan(128 * 1024));
      var oversized = false;
      server.listen((request) async {
        expect(request.uri.queryParameters['pagesize'], '25');
        await _json(
            request,
            oversized
                ? {
                    'status': 1,
                    'data': {'info': [], 'padding': 'x' * (256 * 1024)}
                  }
                : payload);
      });
      final api = KugouMusicApi(_profile(server));
      final result = await api.search('Good Time Owl City Carly Rae Jepsen');
      expect(result.tracks, hasLength(25));
      oversized = true;
      await expectLater(api.search('Good Time Owl City Carly Rae Jepsen'),
          _failure(CustomMusicSourceFailureKind.responseTooLarge));
    });
  });

  test('search respects the editable profile without resolving media',
      () async {
    await _server((server) async {
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        expect(request.headers.value('x-public'), 'fixture');
        await _json(request, {
          'status': 1,
          'data': {
            'info': [
              _song(),
              {
                ..._song(),
                'hash': '11111111111111111111111111111111',
                'pay_type': 3
              },
              {
                ..._song(),
                'hash': '22222222222222222222222222222222',
                'pay_type_320': 3
              },
              {'hash': 'invalid', 'songname': 'Ignored'},
            ],
          },
        });
      });
      final result =
          await KugouMusicApi(_profile(server)).search(' 卡农 ', limit: 100);
      expect(requests, hasLength(1));
      expect(requests.single.path, '/api/search');
      expect(requests.single.queryParameters['keyword'], '卡农');
      expect(requests.single.queryParameters['pagesize'], '25');
      expect(result.tracks, hasLength(3));
      expect(result.tracks.first.onlineProvider, 'custom:fixture-kugou');
      expect(result.tracks.first.onlineId, '$_hash.12.34');
      expect(result.tracks.first.artworkUrl,
          'https://imge.kugou.com/500/cover.jpg');
      expect(result.tracks.first.duration, 180);
      expect(result.tracks[1].onlinePlayable, isFalse);
      expect(result.tracks[1].onlineDownloadAllowed, isFalse);
      expect(result.tracks[2].onlinePlayable, isTrue,
          reason: 'paid high quality does not forbid public standard quality');
    });
  });

  test('lyrics uses its editable service root and never sends local paths',
      () async {
    await _server((server) async {
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/lyric-service/search') {
          await _json(request, {
            'status': 200,
            'candidates': [
              {'id': '123', 'accesskey': 'public-lyric-access'},
            ],
          });
        } else {
          await _json(request, {
            'status': 200,
            'content': base64Encode(utf8.encode('[00:01.00]Hello'))
          });
        }
      });
      final local = Audio('Song', 'Artist', 'Album', 0, 180, null, null,
          r'C:\private\music\song.flac', 0, 0, null);
      final result = await KugouMusicApi(_profile(server)).lyrics(local);
      expect(result.lyric, '[00:01.00]Hello');
      expect(result.type, 'lrc');
      expect(requests.map((uri) => uri.path),
          ['/lyric-service/search', '/lyric-service/download']);
      expect(requests.first.queryParameters['keyword'], 'Song Artist');
      expect(requests.first.queryParameters['duration'], '180000');
      expect(requests.last.queryParameters['fmt'], 'lrc');
      expect(requests.join(), isNot(contains('private')));
      expect(result.toString(), isNot(contains('public-lyric-access')));
    });
  });

  test('public standard audio can download without a custom permission field',
      () async {
    await _server((server) async {
      late Uri requested;
      server.listen((request) async {
        requested = request.uri;
        expect(request.headers.value(HttpHeaders.cookieHeader), isNull);
        expect(request.headers.value(HttpHeaders.authorizationHeader), isNull);
        await _json(request, {
          'status': 1,
          'errcode': 0,
          'url': ['https://media.example.test/full.mp3?token=private-link'],
          'fileSize': 123456,
          'timeLength': 180,
        });
      });
      final profile = _profile(server);
      final result = await KugouMusicApi(profile)
          .resolve(_audio(profile), forDownload: true);
      expect(requested.path, '/api/download');
      expect(requested.queryParameters['hash'], _hash);
      expect(requested.queryParameters['cmd'], 'playInfo');
      expect(requested.queryParameters['userid'], isNull);
      expect(requested.queryParameters['signature'], isNull);
      expect(result.downloadAllowed, isTrue);
      expect(result.expiresAt!.isAfter(DateTime.now()), isTrue);
      expect(result.toString(), isNot(contains('private-link')));
      expect(result.toString(), isNot(contains('media.example.test')));
    });
  });

  test('protected rows never request playback and previews remain denied',
      () async {
    await _server((server) async {
      var calls = 0;
      server.listen((request) async {
        calls++;
        await _json(request, {
          'status': 1,
          'url': ['https://media.example.test/clip.mp3'],
          'is_free_part': 1
        });
      });
      final profile = _profile(server);
      final api = KugouMusicApi(profile);
      await expectLater(api.resolve(_audio(profile, playable: false)),
          _failure(CustomMusicSourceFailureKind.http));
      expect(calls, 0);
      await expectLater(api.resolve(_audio(profile)),
          _failure(CustomMusicSourceFailureKind.http));
      expect(calls, 1);
    });
  });

  test('bad URLs, redirects, login responses and large bodies are bounded',
      () async {
    await _server((server) async {
      var scenario = 0;
      server.listen((request) async {
        if (scenario == 0) {
          await _json(request, {
            'status': 1,
            'url': ['https://user:secret@media.example.test/a.mp3']
          });
        } else if (scenario == 1) {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/other');
          await request.response.close();
        } else if (scenario == 2) {
          await _json(request,
              {'status': 0, 'code': 401, 'message': 'private server body'});
        } else {
          request.response.write('x' * (33 * 1024));
          await request.response.close();
        }
      });
      final profile = _profile(server);
      final api = KugouMusicApi(profile);
      for (final expected in [
        CustomMusicSourceFailureKind.unavailable,
        CustomMusicSourceFailureKind.redirect,
        CustomMusicSourceFailureKind.http,
        CustomMusicSourceFailureKind.responseTooLarge,
      ]) {
        await expectLater(api.resolve(_audio(profile)), _failure(expected));
        scenario++;
      }
    });
  });

  test('a multi-stage lyrics lookup has one total deadline and cancellation',
      () async {
    await _server((server) async {
      server.listen((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (request.uri.path.endsWith('/search')) {
          await _json(request, {
            'candidates': [
              {'id': '1', 'accesskey': 'access'}
            ]
          });
        } else {
          await _json(request,
              {'content': base64Encode(utf8.encode('[00:00.00]Text'))});
        }
      });
      final profile = _profile(server);
      final api = KugouMusicApi(profile,
          requestTimeout: const Duration(milliseconds: 150));
      await expectLater(api.lyrics(_audio(profile)),
          _failure(CustomMusicSourceFailureKind.timeout));
      final cancellation = CustomMusicSourceCancellation()..cancel();
      await expectLater(api.search('Song', cancellation: cancellation),
          _failure(CustomMusicSourceFailureKind.cancelled));
    });
  });

  test(
      'unconfigured account references and invalid track IDs never open clients',
      () async {
    await _server((server) async {
      var created = 0;
      final profile = _profile(server);
      final authentication = CustomMusicSourceAuthentication.tryCreate(
        kind: CustomMusicSourceAuthenticationKind.bearerHeader,
        credentialRef: 'not-a-token',
      )!;
      final api =
          KugouMusicApi(profile.copyWith(authentication: authentication),
              httpClientFactory: () {
        created++;
        return HttpClient();
      });
      await expectLater(api.search('Song'),
          _failure(CustomMusicSourceFailureKind.credentialsNotConfigured));
      final invalidApi = KugouMusicApi(profile, httpClientFactory: () {
        created++;
        return HttpClient();
      });
      final invalid = Audio.online(
          provider: profile.providerId,
          id: '../private',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          duration: 0);
      await expectLater(invalidApi.resolve(invalid),
          _failure(CustomMusicSourceFailureKind.invalidResponse));
      expect(created, 0);
    });
  });

  test(
      'opt-in anonymous live probe: Canon search, lyric, resolution and tiny range',
      () async {
    final profile = CustomMusicSourceProfile.kugouPreset();
    HttpClient client() => HttpClient()
      ..findProxy = (_) => Platform.environment['KUGOU_LIVE_PROXY'] ?? 'DIRECT';
    final api = KugouMusicApi(profile, httpClientFactory: client);
    final result = await api.search('卡农', limit: 12);
    stdout.writeln('KUGOU LIVE search: ${result.tracks.length} rows');
    expect(result.tracks, isNotEmpty);
    var resolved = 0;
    for (final track in result.tracks
        .where((item) => item.onlinePlayable != false)
        .take(3)) {
      stdout.writeln(
          'KUGOU LIVE candidate: ${track.title} / ${track.artist} / ${track.duration}s');
      try {
        final lyrics = await api.lyrics(track);
        stdout.writeln('KUGOU LIVE lyric: ${lyrics.lyric.length} characters');
      } on CustomMusicSourceException catch (error) {
        stdout.writeln(
            'KUGOU LIVE lyric: ${error.kind.name} / HTTP ${error.statusCode}');
      }
      try {
        final source = await api.resolve(track, forDownload: true);
        final mediaClient = client();
        try {
          final request = await mediaClient
              .getUrl(source.uri)
              .timeout(const Duration(seconds: 6));
          request.followRedirects = false;
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-4095');
          final response =
              await request.close().timeout(const Duration(seconds: 6));
          if (response.statusCode == 200 && response.contentLength > 4096) {
            throw const HttpException('Range request was not honored');
          }
          var bytes = 0;
          await for (final chunk
              in response.timeout(const Duration(seconds: 6))) {
            bytes += chunk.length;
            break;
          }
          stdout.writeln(
              'KUGOU LIVE media: HTTP ${response.statusCode}, ${response.headers.contentType?.mimeType}, first chunk $bytes bytes');
          if (response.statusCode == 200 || response.statusCode == 206) {
            resolved++;
          }
        } finally {
          mediaClient.close(force: true);
        }
        break;
      } on CustomMusicSourceException catch (error) {
        stdout.writeln(
            'KUGOU LIVE resolution: ${error.kind.name} / HTTP ${error.statusCode} / business ${error is KugouMusicApiException ? error.businessCode : null}');
      }
    }
    stdout.writeln('KUGOU LIVE usable anonymous media: $resolved');
    expect(resolved, greaterThan(0));
  }, skip: Platform.environment['KUGOU_LIVE_TEST'] != '1');
}

Map<String, Object> _song() => {
      'hash': _hash,
      'album_id': '12',
      'album_audio_id': 34,
      'songname': 'Canon',
      'singername': 'Artist',
      'album_name': 'Album',
      'duration': 180,
      'pay_type': 0,
      'price': 0,
      'privilege': 0,
      'trans_param': {'union_cover': 'http://imge.kugou.com/{size}/cover.jpg'},
    };

CustomMusicSourceProfile _profile(HttpServer server) =>
    CustomMusicSourceProfile.tryCreate(
      id: 'fixture-kugou',
      name: 'KuGou fixture',
      baseUrl: 'http://${server.address.host}:${server.port}/',
      protocol: CustomMusicSourceProtocol.kugou,
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.metadata,
        CustomMusicSourceCapability.cover,
        CustomMusicSourceCapability.lyrics,
        CustomMusicSourceCapability.stream,
        CustomMusicSourceCapability.download,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: 'api/search',
        CustomMusicSourceCapability.metadata: 'api/info',
        CustomMusicSourceCapability.cover: 'api/info',
        CustomMusicSourceCapability.lyrics: 'lyric-service/',
        CustomMusicSourceCapability.stream: 'api/stream',
        CustomMusicSourceCapability.download: 'api/download',
      },
      publicHeaders: const {'X-Public': 'fixture'},
    )!;

Audio _audio(CustomMusicSourceProfile profile, {bool? playable}) =>
    Audio.online(
      provider: profile.providerId,
      id: '$_hash.12.34',
      title: 'Canon',
      artist: 'Artist',
      album: 'Album',
      duration: 180,
      playable: playable,
    );

Matcher _failure(CustomMusicSourceFailureKind kind) => throwsA(
      isA<CustomMusicSourceException>()
          .having((error) => error.kind, 'kind', kind),
    );

Future<void> _json(HttpRequest request, Object body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<void> _server(Future<void> Function(HttpServer) operation) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    await operation(server);
  } finally {
    await server.close(force: true);
  }
}
