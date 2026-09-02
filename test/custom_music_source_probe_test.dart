import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_probe.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('actual capabilities are checked without playing or saving full media',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final prefix = 'http://127.0.0.1:${server.port}';
    final requests = <String>[];
    final ranges = <String?>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/search':
          expect(request.uri.queryParameters['q'], '卡农 艺术家');
          request.response.write(jsonEncode({
            'tracks': [
              {
                'id': 'sample',
                'title': '卡农',
                'artist': '艺术家',
                'album': '专辑',
                'duration': 120,
                'coverUrl': '$prefix/cover',
              }
            ],
          }));
        case '/lyrics':
          request.response.write(jsonEncode({'lyric': '[00:01.00]测试歌词'}));
        case '/comments':
          request.response.write(jsonEncode({
            'comments': [
              {'id': 'one', 'author': 'User', 'content': 'Comment'},
            ]
          }));
        case '/stream':
        case '/download':
          request.response.write(jsonEncode({
            'url': '$prefix/audio',
            'downloadAllowed': true,
          }));
        case '/cover':
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
        case '/audio':
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.add([...utf8.encode('ID3'), 0, 0, 0, 0, 0]);
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final profile = _profile(prefix, enabled: false);
    final report = await CustomMusicSourceProbeService()
        .run(profile, title: '卡农', artist: '艺术家', album: '专辑');

    expect(report.detectedCapabilities,
        containsAll(CustomMusicSourceCapability.values));
    expect(report.results, hasLength(7));
    expect(profile.enabled, isFalse,
        reason: 'probe never enables saved source');
    expect(report.sampleTitle, '卡农');
    expect(ranges, everyElement('bytes=0-4095'));
    expect(ranges, hasLength(3));
    expect(requests.where((path) => path == '/audio'), hasLength(2));
  });

  test('empty samples do not become permanently unsupported capabilities',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/search') {
        request.response.write('{"tracks":[]}');
      } else {
        request.response.headers.contentType = ContentType.text;
      }
      await request.response.close();
    });
    final report = await CustomMusicSourceProbeService()
        .run(_profile('http://127.0.0.1:${server.port}'), title: '没有此歌曲');
    expect(report.results.map((result) => result.status),
        everyElement(CustomMusicSourceProbeStatus.noSample));
    expect(report.detectedCapabilities, isEmpty);
    expect(requests, containsAll(['/search', '/lyrics']));
    expect(requests, isNot(contains('/download')));
  });

  test('explicit download denial skips resolving and HTML audio is rejected',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final prefix = 'http://127.0.0.1:${server.port}';
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/search') {
        request.response.write(jsonEncode({
          'tracks': [
            {
              'id': 'one',
              'title': '卡农',
              'artist': 'Artist',
              'downloadAllowed': false,
            }
          ]
        }));
      } else if (request.uri.path == '/stream') {
        request.response.write(jsonEncode({'url': '$prefix/audio'}));
      } else if (request.uri.path == '/audio') {
        request.response.headers.contentType = ContentType('audio', 'mpeg');
        request.response.write('<html>sign in first</html>');
      } else {
        request.response.statusCode = 401;
      }
      await request.response.close();
    });
    final report = await CustomMusicSourceProbeService()
        .run(_profile(prefix), title: '卡农');
    final statuses = {
      for (final result in report.results) result.capability: result.status
    };
    expect(statuses[CustomMusicSourceCapability.stream],
        CustomMusicSourceProbeStatus.failed);
    expect(statuses[CustomMusicSourceCapability.download],
        CustomMusicSourceProbeStatus.noSample);
    expect(statuses[CustomMusicSourceCapability.lyrics],
        CustomMusicSourceProbeStatus.needsLogin);
    expect(requests, isNot(contains('/download')));
  });

  test('whole run deadline cancels an unresponsive search and pending work',
      () async {
    final report = await CustomMusicSourceProbeService(
      totalTimeout: const Duration(milliseconds: 40),
      transportFactory: _NeverCompletingTransport.new,
    ).run(_profile('https://example.test'), title: '卡农');
    expect(report.results.map((result) => result.status),
        everyElement(CustomMusicSourceProbeStatus.timeout));
    expect(report.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('external cancellation returns promptly and stops progress callbacks',
      () async {
    final token = CustomMusicSourceCancellation();
    var progressCalls = 0;
    final pending = CustomMusicSourceProbeService(
      transportFactory: _NeverCompletingTransport.new,
    ).run(_profile('https://example.test'),
        title: '卡农', cancellation: token, onResult: (_) => progressCalls++);
    token.cancel();
    final report = await pending;
    expect(report.results.map((result) => result.status),
        everyElement(CustomMusicSourceProbeStatus.cancelled));
    expect(progressCalls, 0);
  });

  test('legacy lyric profile checks only its lyric contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.queryParameters['title'], '卡农');
      expect(request.uri.queryParameters.containsKey('id'), isFalse);
      request.response.headers.contentType = ContentType.text;
      request.response.write('[00:01.00]Legacy lyric');
      await request.response.close();
    });
    final profile = CustomMusicSourceProfile.legacyLyric(
        'http://127.0.0.1:${server.port}/lyrics')!;
    final report =
        await CustomMusicSourceProbeService().run(profile, title: '卡农');
    expect(report.detectedCapabilities, {CustomMusicSourceCapability.lyrics});
    expect(
        report.results.where((result) =>
            result.status == CustomMusicSourceProbeStatus.unsupported),
        hasLength(6));
  });

  test('probe tries another sample and allows initial public HTTP audio CDN',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-4095');
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add([...utf8.encode('ID3'), 0, 0, 0]);
      await request.response.close();
    });
    final profile = _profile('https://api.example.test');
    final transport = _SampleTransport(profile,
        media: Uri.parse('http://127.0.0.1:${server.port}/audio'));
    final report = await CustomMusicSourceProbeService(
      transportFactory: (_) => transport,
    ).run(profile, title: '卡农');
    for (final capability in [
      CustomMusicSourceCapability.stream,
      CustomMusicSourceCapability.download
    ]) {
      expect(
          report.results
              .firstWhere((row) => row.capability == capability)
              .status,
          CustomMusicSourceProbeStatus.success);
    }
    expect(transport.resolvedIds,
        containsAll(['stream-0', 'stream-1', 'download-0', 'download-1']));
    expect(transport.resolvedIds, isNot(contains('stream-2')));
    expect(
        report.results
            .firstWhere(
                (row) => row.capability == CustomMusicSourceCapability.lyrics)
            .status,
        CustomMusicSourceProbeStatus.noSample,
        reason: 'instrumental marker is no lyric sample, not unsupported');
  });

  test('unavailable samples stay noSample and no more than three are tried',
      () async {
    final profile = _profile('https://api.example.test');
    final transport = _SampleTransport(profile);
    final report = await CustomMusicSourceProbeService(
      transportFactory: (_) => transport,
    ).run(profile, title: '卡农');
    expect(transport.resolvedIds, hasLength(6));
    expect(transport.resolvedIds, isNot(contains('stream-3')));
    for (final capability in [
      CustomMusicSourceCapability.stream,
      CustomMusicSourceCapability.download
    ]) {
      expect(
          report.results
              .firstWhere((row) => row.capability == capability)
              .status,
          CustomMusicSourceProbeStatus.noSample);
    }
  });

  test('configured Kugou comments and metadata-only cover are actually probed',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final profile =
        _profile(base).copyWith(protocol: CustomMusicSourceProtocol.kugou);
    final transport = _SampleTransport(profile, cover: '$base/cover');
    final report = await CustomMusicSourceProbeService(
      transportFactory: (_) => transport,
    ).run(profile, title: '卡农');
    expect(transport.metadataCalls, 1);
    expect(transport.commentCalls, 1);
    for (final capability in [
      CustomMusicSourceCapability.metadata,
      CustomMusicSourceCapability.cover,
      CustomMusicSourceCapability.comments
    ]) {
      expect(
          report.results
              .firstWhere((row) => row.capability == capability)
              .status,
          CustomMusicSourceProbeStatus.success);
    }
  });
}

CustomMusicSourceProfile _profile(String base, {bool enabled = true}) =>
    CustomMusicSourceProfile.tryCreate(
      id: 'probe-fixture',
      name: 'Fixture',
      baseUrl: base,
      enabled: enabled,
      capabilities: CustomMusicSourceCapability.values,
      endpoints: const {
        CustomMusicSourceCapability.search: 'search',
        CustomMusicSourceCapability.lyrics: 'lyrics',
        CustomMusicSourceCapability.comments: 'comments',
        CustomMusicSourceCapability.stream: 'stream',
        CustomMusicSourceCapability.download: 'download',
      },
    )!;

class _NeverCompletingTransport extends CustomMusicSourceTransport {
  _NeverCompletingTransport(super.profile);

  @override
  Future<CustomMusicSearchResult> search(String rawQuery,
          {int limit = 25, CustomMusicSourceCancellation? cancellation}) =>
      Completer<CustomMusicSearchResult>().future;
}

class _SampleTransport extends CustomMusicSourceTransport {
  _SampleTransport(super.profile, {this.media, this.cover});
  final Uri? media;
  final String? cover;
  final resolvedIds = <String>[];
  int metadataCalls = 0;
  int commentCalls = 0;

  @override
  Future<CustomMusicSearchResult> search(String rawQuery,
          {int limit = 25,
          CustomMusicSourceCancellation? cancellation}) async =>
      CustomMusicSearchResult(
          providerId: profile.providerId,
          tracks: [
            for (var index = 0; index < 4; index++)
              Audio.online(
                  provider: profile.providerId,
                  id: '$index',
                  title: '卡农',
                  artist: 'Artist',
                  album: 'Album',
                  duration: 120)
          ],
          reachedLimit: false);

  @override
  Future<Audio> metadata(Audio audio,
      {CustomMusicSourceCancellation? cancellation}) async {
    metadataCalls++;
    return Audio.online(
        provider: audio.onlineProvider!,
        id: audio.onlineId!,
        title: audio.title,
        artist: 'Artist',
        album: 'Album',
        duration: 120,
        artworkUrl: cover);
  }

  @override
  Future<CustomMusicLyricsResult> lyrics(Audio audio,
          {CustomMusicSourceCancellation? cancellation}) async =>
      CustomMusicLyricsResult(
          rawBody: '[00:00.00]纯音乐，请欣赏', lyric: '[00:00.00]纯音乐，请欣赏');

  @override
  Future<CustomMusicCommentsResult> comments(Audio audio,
      {int page = 0,
      int limit = 30,
      CustomMusicCommentsSort sort = CustomMusicCommentsSort.hot,
      CustomMusicSourceCancellation? cancellation}) async {
    commentCalls++;
    return CustomMusicCommentsResult(comments: const [
      CustomMusicComment(id: 'one', author: 'User', content: 'Public comment'),
    ], page: 0, hasMore: false);
  }

  @override
  Future<CustomMusicStreamResolution> resolve(Audio audio,
      {bool forDownload = false,
      CustomMusicSourceCancellation? cancellation}) async {
    resolvedIds.add('${forDownload ? 'download' : 'stream'}-${audio.onlineId}');
    if (media == null || audio.onlineId == '0') {
      throw const CustomMusicSourceException(
          CustomMusicSourceFailureKind.unavailable, '样本没有可用音源');
    }
    return CustomMusicStreamResolution(uri: media!, downloadAllowed: true);
  }
}
