import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/online/qq_public_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QQ search signature stays compatible with the fixed request vector',
      () {
    expect(
      qqSearchSignature('{}'),
      'zzcf8e26805gyafigxmxjehoe02mvsjjgtwzw6f1a05f9',
    );
    expect(
      qqSearchSignature('{"query":"卡农"}'),
      'zzc15073ba0lfpntrgyksnpoa6sqi7lpfmbfi3b7fa8ea',
    );
  });

  test('signed anonymous transport posts the current request without cookies',
      () async {
    final client = _Client(_Response.json({
      'code': 0,
      'req': {
        'code': 0,
        'data': {
          'body': {
            'item_song': [
              {
                'id': 42,
                'mid': 'MID42',
                'name': '結想は花となる',
                'singer': [
                  {'name': 'ウォルピスカーター'},
                ],
                'album': {'name': 'Album', 'mid': 'ALBUM42'},
                'file': {'media_mid': 'MEDIA42'},
                'interval': 123,
              },
            ],
          },
        },
      },
    }));
    final songs = await QqPublicSearchTransport(
      httpClientFactory: () => client,
      now: () => DateTime.fromMicrosecondsSinceEpoch(123456789),
    ).search('結想は花となる', 20);

    expect(songs, hasLength(1));
    expect(songs.single.numericId, 42);
    expect(songs.single.mid, 'MID42');
    expect(songs.single.artists, 'ウォルピスカーター');
    expect(songs.single.albumMid, 'ALBUM42');
    expect(client.method, 'POST');
    expect(client.uri?.host, 'u.y.qq.com');
    expect(client.uri?.path, '/cgi-bin/musics.fcg');
    expect(client.uri?.queryParameters['sign'], isNotEmpty);
    expect(client.request.followRedirects, isFalse);
    expect(client.request.headers.values, isNot(contains('cookie')));
    final body = jsonDecode(client.request.body.toString()) as Map;
    expect(body['req']['method'], 'DoSearchForQQMusicMobile');
    expect(body['req']['param']['query'], '結想は花となる');
    expect(body['req']['param']['searchid'], '123456789');
    expect(client.closed, isTrue);
  });

  test('business code 2001 remains a bounded-retry signal, not a schema error',
      () {
    expect(
      () => parseQqPublicSearchPayload({
        'code': 0,
        'req': {'code': 2001, 'data': const {}},
      }),
      throwsA(isA<QqPublicSearchException>()
          .having((error) => error.retryable, 'retryable', isTrue)
          .having((error) => error.serviceCode, 'serviceCode', 2001)),
    );
  });

  test('parser skips malformed rows and accepts nested current song records',
      () {
    final songs = parseQqPublicSearchPayload({
      'code': 0,
      'req_1': {
        'code': 0,
        'data': {
          'body': {
            'song': {
              'list': [
                null,
                {'name': 'missing mid'},
                {
                  'track_info': {
                    'id': '7',
                    'mid': 'MID7',
                    'title': 'Song',
                    'singers': [
                      {'name': 'Singer'},
                    ],
                    'album': {'title': 'Album'},
                  },
                },
              ],
            },
          },
        },
      },
    });

    expect(songs, hasLength(1));
    expect(songs.single.numericId, 7);
    expect(songs.single.title, 'Song');
    expect(songs.single.artists, 'Singer');
  });
}

class _Client implements HttpClient {
  _Client(_Response response) : request = _Request(Future.value(response));

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
      _stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
