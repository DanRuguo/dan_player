import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected NetEase metadata gets cover only for the exact requested ID',
      () async {
    final client = _Client(_Response.json({
      'code': 200,
      'songs': [
        {
          'id': 12,
          'name': 'Wrong song',
          'album': {'picUrl': 'https://img/wrong'}
        },
        {
          'id': 11,
          'name': 'Song',
          'artists': [
            {'name': 'Artist'}
          ],
          'album': {'name': 'Album', 'picUrl': 'https://img/cover'},
          'duration': 180000
        },
      ]
    }));
    final service = OnlineMusicService.forNeteaseTransportTesting(
        httpClientFactory: () => client);
    final original = Audio.online(
        provider: 'netease',
        id: '11',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: 180,
        downloadAllowed: false);
    final result = await service.refreshMetadata(original);
    expect(result.onlineId, '11');
    expect(result.onlineDownloadAllowed, isFalse);
    expect(result.artworkUrl, 'https://img/cover');
    expect(client.method, 'GET');
    expect(client.uri!.queryParameters['ids'], '[11]');
    expect(client.request.headers.values.keys, isNot(contains('cookie')));
    expect(client.request.followRedirects, isFalse);
    expect(client.closed, isTrue);
  });

  test('cancelled selected metadata never opens an HTTP client', () async {
    final service = OnlineMusicService.forNeteaseTransportTesting(
        httpClientFactory: () => throw StateError('Unexpected client'));
    final token = CustomMusicSourceCancellation()..cancel();
    await expectLater(
        service.refreshMetadata(
            Audio.online(
                provider: 'netease',
                id: '11',
                title: 'Song',
                artist: 'Artist',
                album: 'Album',
                duration: 180),
            cancellation: token),
        throwsA(isA<CustomMusicSourceCancelled>()));
  });

  test(
      'owned Netease transport preserves HTTP request and parses mixed schemas',
      () async {
    final client = _Client(_Response.json({
      'code': '200',
      'result': {
        'songs': [
          {
            'id': 11,
            'name': '第一首',
            'ar': [
              {'name': '歌手甲'}
            ],
            'al': {'name': '专辑甲', 'picUrl': 'https://img/1'},
            'dt': 125000,
          },
          'bad-row',
          {
            'id': '12',
            'name': '第二首',
            'artists': [
              {'name': '歌手乙'}
            ],
            'album': {'name': '专辑乙'},
            'duration': 61000,
          },
          {'name': 'missing id'},
        ],
      },
    }));
    final response = await OnlineMusicService.forNeteaseTransportTesting(
      httpClientFactory: () => client,
    ).search('卡农');

    expect(response.tracks.map((track) => track.onlineId), ['11', '12']);
    expect(response.tracks.first.artist, '歌手甲');
    expect(response.tracks.first.album, '专辑甲');
    expect(response.tracks.first.duration, 125);
    expect(client.method, 'POST');
    expect(client.uri, Uri.https('music.163.com', '/weapi/search/get'));
    expect(client.request.followRedirects, isFalse);
    expect(client.request.headers.values.keys, isNot(contains('cookie')));
    final form = Uri.splitQueryString(client.request.body.toString());
    expect(form.keys.toSet(), {'params', 'encSecKey'});
    expect(client.request.body.toString(), isNot(contains('卡农')),
        reason: 'diagnostics and request bodies must not expose the raw query');
    expect(client.closed, isTrue);
  });

  test('malformed JSON is an API failure and is not retried', () async {
    var opened = 0;
    final service = OnlineMusicService.forNeteaseTransportTesting(
      httpClientFactory: () {
        opened++;
        return _Client(_Response(utf8.encode('<html>bad gateway</html>')));
      },
    );
    await expectLater(
      service.search('卡农'),
      throwsA(isA<OnlineMusicException>()
          .having((error) => error.kind, 'kind', OnlineMusicFailureKind.api)
          .having((error) => error.message, 'message', contains('无法解析'))),
    );
    expect(opened, 1);
  });

  test('HTTP transient response retries once while permanent response does not',
      () async {
    final clients = <_Client>[
      _Client(_Response(const [], status: 500)),
      _Client(_Response.json({
        'code': 200,
        'result': {'songs': []},
      })),
    ];
    var index = 0;
    final recovered = await OnlineMusicService.forNeteaseTransportTesting(
      httpClientFactory: () => clients[index++],
    ).search('卡农');
    expect(recovered.tracks, isEmpty);
    expect(index, 2);
    expect(clients.every((client) => client.closed), isTrue);

    var permanentCalls = 0;
    final denied = OnlineMusicService.forNeteaseTransportTesting(
      httpClientFactory: () {
        permanentCalls++;
        return _Client(_Response(const [], status: 403));
      },
    );
    await expectLater(
        denied.search('卡农'), throwsA(isA<OnlineMusicException>()));
    expect(permanentCalls, 1);
  });

  test('non-object and missing songs remain explicit schema failures',
      () async {
    for (final payload in <Object>[
      const [],
      {'code': 200},
      {
        'code': 200,
        'result': {'songs': null}
      },
    ]) {
      final service = OnlineMusicService.forNeteaseTransportTesting(
        httpClientFactory: () => _Client(_Response(
          utf8.encode(jsonEncode(payload)),
        )),
      );
      await expectLater(
        service.search('卡农'),
        throwsA(isA<OnlineMusicException>()
            .having((error) => error.kind, 'kind', OnlineMusicFailureKind.api)),
      );
    }
  });
}

class _Client implements HttpClient {
  _Client(_Response value) : request = _Request(Future.value(value));
  final _Request request;
  Uri? uri;
  String? method;
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    uri = url;
    method = 'POST';
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    method = 'GET';
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  final body = StringBuffer();

  @override
  final _Headers headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};

  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name.toLowerCase()] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(List<int> bytes, {int status = 200})
      : contentLength = bytes.length,
        statusCode = status,
        _stream = Stream.value(bytes);

  factory _Response.json(Map<String, dynamic> data) =>
      _Response(utf8.encode(jsonEncode(data)));

  final Stream<List<int>> _stream;

  @override
  final int contentLength;

  @override
  final int statusCode;

  @override
  final HttpHeaders headers = _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
