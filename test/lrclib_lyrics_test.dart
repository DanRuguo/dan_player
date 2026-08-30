import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/online/lrclib_lyrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('anonymous search uses documented fields and sends no cookie', () async {
    final client = _Client(_Response.json([
      {
        'id': 38005804,
        'trackName': '結想は花となる',
        'artistName': 'ウォルピスカーター',
        'albumName': 'as:9-nine- ARTEISIA ORIGINAL SOUND TRACK',
        'duration': 195,
        'instrumental': false,
        'plainLyrics': 'line one\nline two',
        'syncedLyrics': null,
      },
    ]));

    final records = await LrclibLyricsTransport(
      httpClientFactory: () => client,
    ).search(
      trackName: '結想は花となる',
      artistName: 'ウォルピスカーター',
    );

    expect(records, hasLength(1));
    expect(records.single.id, 38005804);
    expect(records.single.plainLyrics, contains('line two'));
    expect(client.uri?.path, '/api/search');
    expect(client.uri?.queryParameters, {
      'track_name': '結想は花となる',
      'artist_name': 'ウォルピスカーター',
    });
    expect(client.request.followRedirects, isFalse);
    expect(client.request.headers.values, isNot(contains('cookie')));
    expect(client.closed, isTrue);
  });

  test('instrumental and malformed records are not offered as candidates', () {
    final records = parseLrclibSearchPayload([
      {
        'id': 1,
        'trackName': 'Instrumental',
        'artistName': '',
        'albumName': '',
        'duration': 1,
        'instrumental': true,
        'plainLyrics': null,
        'syncedLyrics': null,
      },
      {'id': null, 'trackName': 'broken'},
      {
        'id': 2,
        'trackName': 'Valid',
        'artistName': 'Singer',
        'albumName': 'Album',
        'duration': 10,
        'instrumental': false,
        'plainLyrics': null,
        'syncedLyrics': '[00:01.00]line',
      },
    ]);

    expect(records.map((record) => record.id), [2]);
  });

  test('429 is surfaced as a bounded-retry transport error', () async {
    final client = _Client(_Response(const [], status: 429));
    await expectLater(
      LrclibLyricsTransport(httpClientFactory: () => client)
          .search(trackName: '卡农'),
      throwsA(isA<LrclibException>()
          .having((error) => error.retryable, 'retryable', isTrue)
          .having((error) => error.statusCode, 'statusCode', 429)),
    );
  });
}

class _Client implements HttpClient {
  _Client(_Response response) : request = _Request(Future.value(response));

  final _Request request;
  Uri? uri;
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
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

  @override
  final _Headers headers = _Headers();

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};

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

  factory _Response.json(Object data) =>
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
