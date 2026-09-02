import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dan-source-v1 transport', () {
    test('search is bounded, preserves identity and reads explicit flags',
        () async {
      await _withServer((server) async {
        late Uri requestUri;
        late String publicHeader;
        server.listen((request) async {
          requestUri = request.uri;
          publicHeader = request.headers.value('x-client') ?? '';
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'tracks': [
              {
                'id': 'opaque/a',
                'title': 'First',
                'artist': 'Artist',
                'album': 'Album',
                'duration': 123,
                'coverUrl': 'https://images.example.test/cover.jpg',
                'streamAvailable': true,
                'downloadAllowed': false,
                // A search response URL is deliberately ignored. Playback is
                // resolved only after the user selects this row.
                'url': 'https://must-not-be-used.example/audio.mp3',
              },
              {
                'id': 'opaque-b',
                'name': 'Second',
                'playable': false,
                'downloadAllowed': true,
              },
              for (var index = 2; index < 30; index++)
                {
                  'id': 'opaque-$index',
                  'title': 'Track $index',
                },
            ],
          }));
          await request.response.close();
        });
        final profile = _danProfile(
          server,
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: 'search'},
          headers: const {'X-Client': 'Dan Player test'},
        );

        final result = await CustomMusicSourceTransport(profile).search(
          '  hello world  ',
          limit: 40,
        );

        expect(requestUri.path, '/search');
        expect(requestUri.queryParameters['q'], 'hello world');
        expect(requestUri.queryParameters['limit'], '25');
        expect(publicHeader, 'Dan Player test');
        expect(result.providerId, 'custom:fixture');
        expect(result.tracks, hasLength(25));
        expect(result.reachedLimit, isTrue);
        expect(result.tracks.first.onlineProvider, 'custom:fixture');
        expect(result.tracks.first.onlineId, 'opaque/a');
        expect(result.tracks.first.onlinePlayable, isTrue);
        expect(result.tracks.first.onlineDownloadAllowed, isFalse);
        expect(result.tracks[1].onlinePlayable, isFalse);
        expect(result.tracks[1].onlineDownloadAllowed, isTrue);
        expect(result.tracks.first.path, isNot(contains('must-not-be-used')));
        expect(result.toString(), isNot(contains('hello world')));
      });
    });

    test('lyrics never sends a local absolute path and comments normalize',
        () async {
      await _withServer((server) async {
        final requests = <Uri>[];
        server.listen((request) async {
          requests.add(request.uri);
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/lyrics') {
            request.response.write(jsonEncode({
              'type': 'lrc',
              'lyric': '[00:00.00]Main',
              'translation': '[00:00.00]Translated',
            }));
          } else {
            request.response.write(jsonEncode({
              'comments': [
                {
                  'id': 'comment-1',
                  'author': {'nickname': 'Alice'},
                  'content': 'Hello',
                  'publishedAt': '2026-09-02T12:00:00Z',
                  'likeCount': 7,
                },
                {'author': 'Bob', 'text': 'World'},
              ],
              'hasMore': true,
              'total': 9,
            }));
          }
          await request.response.close();
        });
        final profile = _danProfile(
          server,
          capabilities: const {
            CustomMusicSourceCapability.lyrics,
            CustomMusicSourceCapability.comments,
          },
          endpoints: const {
            CustomMusicSourceCapability.lyrics: 'lyrics',
            CustomMusicSourceCapability.comments: 'comments',
          },
        );
        final transport = CustomMusicSourceTransport(profile);
        final local = Audio(
          'Title',
          'Artist',
          'Album',
          0,
          180,
          null,
          null,
          r'C:\Users\private-person\Music\secret-song.flac',
          0,
          0,
          null,
        );

        final lyrics = await transport.lyrics(local);
        final online = Audio.online(
          provider: profile.providerId,
          id: 'opaque-comment-id',
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
          duration: 180,
        );
        final comments = await transport.comments(
          online,
          page: 2,
          sort: CustomMusicCommentsSort.latest,
        );

        expect(lyrics.lyric, '[00:00.00]Main');
        expect(lyrics.translation, '[00:00.00]Translated');
        expect(lyrics.type, 'lrc');
        expect(requests.first.queryParameters['fileName'], 'secret-song');
        expect(requests.first.toString(), isNot(contains(r'C:\Users')));
        expect(requests.first.queryParameters, isNot(contains('path')));
        expect(requests.last.queryParameters['id'], 'opaque-comment-id');
        expect(requests.last.queryParameters['page'], '2');
        expect(requests.last.queryParameters['sort'], 'latest');
        expect(comments.comments, hasLength(2));
        expect(comments.comments.first.author, 'Alice');
        expect(comments.comments.first.likeCount, 7);
        expect(
            comments.comments.first.publishedAt, DateTime.utc(2026, 9, 2, 12));
        expect(comments.hasMore, isTrue);
        expect(comments.total, 9);
      });
    });

    test('resolution requires an explicit per-track download grant', () async {
      await _withServer((server) async {
        final purposes = <String>[];
        server.listen((request) async {
          purposes.add(request.uri.queryParameters['purpose'] ?? '');
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'url': 'https://media.example.test/song.mp3?token=super-secret',
            'expiresAt': '2026-09-03T12:00:00Z',
            'downloadAllowed': request.uri.queryParameters['grant'] == 'true',
            'mimeType': 'audio/mpeg',
            'supportsRange': true,
          }));
          await request.response.close();
        });
        final denied = _danProfile(
          server,
          capabilities: const {
            CustomMusicSourceCapability.stream,
            CustomMusicSourceCapability.download,
          },
          endpoints: const {
            CustomMusicSourceCapability.stream: 'resolve',
            CustomMusicSourceCapability.download: 'resolve',
          },
        );
        final audio = Audio.online(
          provider: denied.providerId,
          id: 'track-1',
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
          duration: 1,
        );
        final transport = CustomMusicSourceTransport(denied);

        final stream = await transport.resolve(audio);
        expect(stream.downloadAllowed, isFalse);
        expect(stream.mimeType, 'audio/mpeg');
        expect(stream.supportsRange, isTrue);
        expect(stream.toString(), isNot(contains('media.example.test')));
        expect(stream.toString(), isNot(contains('super-secret')));
        await expectLater(
          transport.resolve(audio, forDownload: true),
          throwsA(isA<CustomMusicSourceException>().having(
            (error) => error.kind,
            'kind',
            CustomMusicSourceFailureKind.unavailable,
          )),
        );
        expect(purposes, ['stream', 'download']);

        final granted = _danProfile(
          server,
          capabilities: const {
            CustomMusicSourceCapability.stream,
            CustomMusicSourceCapability.download,
          },
          endpoints: const {
            CustomMusicSourceCapability.stream: 'resolve',
            CustomMusicSourceCapability.download: 'resolve?grant=true',
          },
        );
        final grantedDownload = await CustomMusicSourceTransport(granted)
            .resolve(audio, forDownload: true);
        expect(grantedDownload.downloadAllowed, isTrue);
        expect(purposes, ['stream', 'download', 'download']);
      });
    });

    test('rejects redirects, oversized bodies, bad schema and unsafe URLs',
        () async {
      await _withServer((server) async {
        server.listen((request) async {
          switch (request.uri.path) {
            case '/redirect':
              request.response.statusCode = HttpStatus.found;
              request.response.headers.set('location', '/search');
            case '/large':
              request.response.contentLength =
                  CustomMusicSourceTransport.searchResponseByteLimit + 1;
              request.response.add(List<int>.filled(
                CustomMusicSourceTransport.searchResponseByteLimit + 1,
                65,
              ));
            case '/bad':
              request.response.write(jsonEncode({'tracks': 'not-a-list'}));
            case '/unsafe':
              request.response.write(jsonEncode({
                'url': 'https://user:password@example.test/song.mp3',
                'downloadAllowed': true,
              }));
          }
          try {
            await request.response.close();
          } on Object {
            // The client intentionally closes an oversized response early.
          }
        });
        Future<CustomMusicSourceException> searchFailure(
            String endpoint) async {
          final profile = _danProfile(
            server,
            capabilities: const {CustomMusicSourceCapability.search},
            endpoints: {CustomMusicSourceCapability.search: endpoint},
          );
          try {
            await CustomMusicSourceTransport(profile).search('query');
          } on CustomMusicSourceException catch (error) {
            return error;
          }
          throw StateError('Expected a custom-source failure');
        }

        expect((await searchFailure('redirect')).kind,
            CustomMusicSourceFailureKind.redirect);
        expect((await searchFailure('large')).kind,
            CustomMusicSourceFailureKind.responseTooLarge);
        expect((await searchFailure('bad')).kind,
            CustomMusicSourceFailureKind.invalidResponse);

        final resolutionProfile = _danProfile(
          server,
          capabilities: const {CustomMusicSourceCapability.stream},
          endpoints: const {CustomMusicSourceCapability.stream: 'unsafe'},
        );
        final audio = Audio.online(
          provider: resolutionProfile.providerId,
          id: 'id',
          title: 'Title',
          artist: 'Artist',
          album: 'Album',
          duration: 1,
        );
        await expectLater(
          CustomMusicSourceTransport(resolutionProfile).resolve(audio),
          throwsA(isA<CustomMusicSourceException>().having(
            (error) => error.kind,
            'kind',
            CustomMusicSourceFailureKind.invalidResponse,
          )),
        );
      });
    });

    test('timeout and cancellation close only their own request', () async {
      await _withServer((server) async {
        final secondReceived = Completer<void>();
        var requestCount = 0;
        server.listen((request) async {
          requestCount++;
          if (requestCount == 2 && !secondReceived.isCompleted) {
            secondReceived.complete();
          }
          await Future<void>.delayed(const Duration(seconds: 1));
          try {
            request.response.write(jsonEncode({'tracks': <Object>[]}));
            await request.response.close();
          } on Object {
            // Expected after timeout/cancellation closes this request client.
          }
        });
        final profile = _danProfile(
          server,
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: 'slow'},
        );
        final timed = CustomMusicSourceTransport(
          profile,
          requestTimeout: const Duration(milliseconds: 40),
        );
        await expectLater(
          timed.search('timeout'),
          throwsA(isA<CustomMusicSourceException>().having(
            (error) => error.kind,
            'kind',
            CustomMusicSourceFailureKind.timeout,
          )),
        );

        final cancellation = CustomMusicSourceCancellation();
        final cancellable = CustomMusicSourceTransport(
          profile,
          requestTimeout: const Duration(seconds: 2),
        ).search('cancel', cancellation: cancellation);
        await secondReceived.future;
        cancellation.cancel();
        await expectLater(
          cancellable,
          throwsA(isA<CustomMusicSourceCancelled>()),
        );
      });
    });

    test('credential references remain inert and redacted', () async {
      final authentication = CustomMusicSourceAuthentication.tryCreate(
        kind: CustomMusicSourceAuthenticationKind.apiKeyHeader,
        credentialRef: 'do-not-use-this-as-a-key',
      )!;
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'credential-source',
        name: 'Credential source',
        baseUrl: 'https://source.example.test/',
        capabilities: const {CustomMusicSourceCapability.search},
        endpoints: const {CustomMusicSourceCapability.search: 'search'},
        authentication: authentication,
      )!;

      CustomMusicSourceException? failure;
      try {
        await CustomMusicSourceTransport(profile).search('query');
      } on CustomMusicSourceException catch (error) {
        failure = error;
      }
      expect(
          failure?.kind, CustomMusicSourceFailureKind.credentialsNotConfigured);
      expect(failure.toString(), contains('凭据存储尚未配置'));
      expect(failure.toString(), isNot(contains('do-not-use-this-as-a-key')));
      expect(profile.toString(), isNot(contains('source.example.test')));
    });
  });

  test('go-music-api preset maps search and constructs its local proxy routes',
      () async {
    await _withServer((server) async {
      final requested = <Uri>[];
      server.listen((request) async {
        requested.add(request.uri);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/search')) {
          request.response.write(jsonEncode({
            'code': 200,
            'data': {
              'songs': [
                {
                  'id': 'hash-or-id',
                  'name': 'Song',
                  'artist': 'Singer',
                  'album': 'Record',
                  'duration': 245,
                  'bitrate': 320,
                  'source': 'kugou',
                  'cover': 'https://cover.example.test/a.jpg',
                  'extra': {'album_id': '123', 'quality': 320},
                  'is_invalid': false,
                  'is_vip': false,
                },
                {
                  'id': 'invalid',
                  'name': 'Invalid',
                  'source': 'qq',
                  'is_invalid': true,
                },
              ],
            },
          }));
        } else {
          expect(request.uri.queryParameters['id'], 'hash-or-id');
          expect(request.uri.queryParameters['source'], 'kugou');
          expect(request.uri.queryParameters['extra'],
              jsonEncode({'album_id': '123', 'quality': '320'}));
          request.response.write(jsonEncode({
            'code': 200,
            'data': {'lyric': '[00:00.00]From go-music-api'},
          }));
        }
        await request.response.close();
      });
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'go-fixture',
        name: 'Self-hosted music API',
        baseUrl: 'http://127.0.0.1:${server.port}/prefix',
        protocol: CustomMusicSourceProtocol.goMusicApi,
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.lyrics,
          CustomMusicSourceCapability.stream,
          CustomMusicSourceCapability.download,
        },
      )!;
      final transport = CustomMusicSourceTransport(profile);

      final result = await transport.search('Song');
      expect(result.tracks, hasLength(1));
      final audio = result.tracks.single;
      expect(audio.onlineProvider, 'custom:go-fixture');
      expect(audio.onlineId, startsWith('gma1.'));
      expect(audio.onlinePlayable, isTrue);
      expect(audio.onlineDownloadAllowed, isTrue);
      expect(requested.single.path, '/prefix/api/v1/music/search');
      expect(requested.single.queryParameters['type'], 'song');

      final stream = await transport.resolve(audio);
      expect(stream.uri.path, '/prefix/api/v1/music/stream');
      expect(stream.uri.queryParameters['id'], 'hash-or-id');
      expect(stream.uri.queryParameters['source'], 'kugou');
      expect(stream.downloadAllowed, isTrue);
      final download = await transport.resolve(audio, forDownload: true);
      expect(download.downloadAllowed, isTrue);
      expect(requested, hasLength(1),
          reason: 'Resolving a go-music-api track returns its proxy URL; it '
              'must not eagerly download the media stream.');

      final lyrics = await transport.lyrics(audio);
      expect(lyrics.lyric, '[00:00.00]From go-music-api');
      expect(requested.last.path, '/prefix/api/v1/music/lyric');
    });
  });
}

CustomMusicSourceProfile _danProfile(
  HttpServer server, {
  required Set<CustomMusicSourceCapability> capabilities,
  required Map<CustomMusicSourceCapability, String> endpoints,
  Map<String, String> headers = const <String, String>{},
}) =>
    CustomMusicSourceProfile.tryCreate(
      id: 'fixture',
      name: 'Fixture',
      baseUrl: 'http://127.0.0.1:${server.port}/',
      capabilities: capabilities,
      endpoints: endpoints,
      publicHeaders: headers,
    )!;

Future<void> _withServer(Future<void> Function(HttpServer server) body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    await body(server);
  } finally {
    await server.close(force: true);
  }
}
