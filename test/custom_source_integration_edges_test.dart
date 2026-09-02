import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/online/online_artwork_request.dart';
import 'package:flutter_test/flutter_test.dart';

const _hash = 'abcdef1234567890abcdef1234567890';

void main() {
  test('Kugou separate metadata and cover URLs are used without changing ID',
      () async {
    await _server((server, base) async {
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/metadata') {
          await _json(request, {
            'status': 1,
            'data': {
              'hash': _hash,
              'songname': 'Updated title',
              'singername': 'Updated artist',
              'album_id': '99',
              'album_audio_id': '88',
              'duration': 180,
            },
          });
        } else if (request.uri.path == '/cover') {
          await _json(request, {
            'status': 1,
            'data': {'imgurl': '$base/album-art.png'},
          });
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'kugou-edge',
        name: 'Kugou fixture',
        baseUrl: '$base/',
        protocol: CustomMusicSourceProtocol.kugou,
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.cover,
        },
        endpoints: const {
          CustomMusicSourceCapability.metadata: 'metadata?fixture=meta',
          CustomMusicSourceCapability.cover: 'cover?fixture=cover',
        },
      )!;
      final original = _audio(profile, id: '$_hash.12.34');
      final result =
          await CustomMusicSourceTransport(profile).metadata(original);

      expect(requests.map((request) => request.path), ['/metadata', '/cover']);
      expect(requests.map((request) => request.queryParameters['hash']),
          everyElement(_hash));
      expect(requests.map((request) => request.queryParameters['fixture']),
          ['meta', 'cover']);
      expect(result.title, 'Updated title');
      expect(result.artworkUrl, '$base/album-art.png');
      expect(result.onlineId, original.onlineId,
          reason: 'metadata may enrich album identifiers, not rebind the song');
      expect(result.path, original.path);
    });
  });

  test('Dan explicit image endpoint is loaded without an invented metadata GET',
      () async {
    final png = await _smallPng();
    await _server((server, base) async {
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/search') {
          await _json(request, {
            'tracks': [
              {
                'id': 'opaque/id with space',
                'title': 'Sample',
                'artist': 'Artist',
                'album': 'Album',
                'coverUrl': '$base/unused-search-cover.png',
              },
            ],
          });
        } else if (request.uri.path == '/image') {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(png);
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      });
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'dan-cover-edge',
        name: 'Dan fixture',
        baseUrl: '$base/',
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.cover,
        },
        endpoints: const {
          CustomMusicSourceCapability.search: 'search',
          CustomMusicSourceCapability.cover: 'image?size=large&id=old',
        },
      )!;
      final previous = AppSettings.instance.customMusicSources.value;
      addTearDown(
          () => AppSettings.instance.customMusicSources.value = previous);
      AppSettings.instance.customMusicSources.value = [profile];
      final transport = CustomMusicSourceTransport(profile);
      final audio = (await transport.search('Sample')).tracks.single;
      final detailed = await transport.metadata(audio);

      expect(requests.map((request) => request.path), ['/search'],
          reason: 'no metadata endpoint means no extra JSON/root request');
      final artwork = Uri.parse(detailed.artworkUrl!);
      expect(artwork.path, '/image');
      expect(artwork.queryParameters['id'], 'opaque/id with space');
      expect(artwork.queryParameters['size'], 'large');
      final loaded = await OnlineArtworkRequest().loadPng(detailed.artworkUrl!,
          provider: profile.providerId, expectedProfile: profile);
      expect(loaded.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(requests.map((request) => request.path), ['/search', '/image']);
      expect(detailed.path, audio.path);
    });
  });

  test('HTTP 200 outer 401 or 403 cannot authorize a nested media URL',
      () async {
    await _server((server, base) async {
      var responseCode = 401;
      final requests = <Uri>[];
      server.listen((request) async {
        requests.add(request.uri);
        await _json(request, {
          'code': responseCode,
          'data': {
            'url': '$base/must-not-fetch.mp3',
            'downloadAllowed': true,
          },
        });
      });
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'auth-edge',
        name: 'Auth fixture',
        baseUrl: '$base/',
        capabilities: const {
          CustomMusicSourceCapability.stream,
          CustomMusicSourceCapability.download,
        },
        endpoints: const {
          CustomMusicSourceCapability.stream: 'resolve',
          CustomMusicSourceCapability.download: 'resolve',
        },
      )!;
      final transport = CustomMusicSourceTransport(profile);
      for (final code in [401, 403]) {
        responseCode = code;
        for (final forDownload in [false, true]) {
          await expectLater(
            transport.resolve(_audio(profile), forDownload: forDownload),
            throwsA(isA<CustomMusicSourceException>()
                .having((error) => error.kind, 'kind',
                    CustomMusicSourceFailureKind.http)
                .having((error) => error.statusCode, 'denied status',
                    anyOf(401, 403))),
          );
        }
      }
      expect(requests, hasLength(4));
      expect(requests.map((request) => request.path), everyElement('/resolve'));
    });
  });
}

Audio _audio(CustomMusicSourceProfile profile, {String id = 'sample'}) =>
    Audio.online(
        provider: profile.providerId,
        id: id,
        title: 'Sample',
        artist: 'Artist',
        album: 'Album',
        duration: 180);

Future<void> _server(
    Future<void> Function(HttpServer server, String base) body) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  try {
    await body(server, 'http://127.0.0.1:${server.port}');
  } finally {
    await server.close(force: true);
  }
}

Future<void> _json(HttpRequest request, Map<String, Object?> body) async {
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(body));
  await request.response.close();
}

Future<Uint8List> _smallPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff337799), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
