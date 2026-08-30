import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/component/online_metadata_lookup_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_artwork_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('metadata query omits unknown tags and falls back to the filename', () {
    final audio = Audio('UNKNOWN', 'UNKNOWN', 'UNKNOWN', 0, 120, null, null,
        r'D:\music\歌曲.flac', 0, 0, null);
    expect(onlineMetadataQuery(audio), '歌曲');
    expect(onlineMetadataQuery(audio, title: 'New title', artist: 'Singer'),
        'New title Singer');
    expect(onlineMetadataQuery(audio, title: '   ', artist: '未知艺术家'), '歌曲');
  });

  test('metadata query removes only trailing OP and short-version noise', () {
    final audio = Audio(
      '結想は花となる -OP- short ver.',
      'ウォルピスカーター',
      'Album',
      0,
      120,
      null,
      null,
      r'D:\music\sample.mp3',
      0,
      0,
      null,
    );
    expect(
      onlineMetadataQuery(audio),
      '結想は花となる ウォルピスカーター',
    );
  });

  test('invalid artwork URLs never open a network client', () async {
    var opened = false;
    final request = OnlineArtworkRequest(httpClientFactory: () {
      opened = true;
      return _Client((_) => _Response(const []));
    });
    for (final address in [
      'file:///D:/picture.png',
      'data:image/png;base64,AAAA',
      'https://user:password@example.com/image',
      'not a url',
    ]) {
      await expectLater(request.loadPng(address), throwsFormatException);
    }
    expect(opened, isFalse);
  });

  test('pre-cancelled artwork request does not open a client', () async {
    var opened = false;
    final request = OnlineArtworkRequest(httpClientFactory: () {
      opened = true;
      return _Client((_) => _Response(const []));
    })
      ..cancel();
    await expectLater(request.loadPng('https://example.com/cover'),
        throwsA(isA<HttpException>()));
    expect(opened, isFalse);
  });

  test('artwork is upgraded to HTTPS, decoded and returned as a PNG', () async {
    final fixture = await _smallPng();
    final client = _Client((_) => _Response(fixture));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);

    final png = await request.loadPng('http://example.com/cover');

    expect(client.requested.single.scheme, 'https');
    expect(client.closed, isTrue);
    expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 2);
    expect(image.height, 2);
    image.dispose();
    codec.dispose();
  });

  test('an HTTPS downgrade is rejected before following the redirect',
      () async {
    final client = _Client((_) =>
        _Response(const [], status: 302, location: 'http://example.com/plain'));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);

    await expectLater(request.loadPng('https://example.com/cover'),
        throwsA(isA<HttpException>()));

    expect(client.requested, [Uri.parse('https://example.com/cover')]);
    expect(client.closed, isTrue);
  });

  test('redirect loops are bounded', () async {
    final client =
        _Client((_) => _Response(const [], status: 302, location: '/loop'));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);

    await expectLater(request.loadPng('https://example.com/cover'),
        throwsA(isA<HttpException>()));

    expect(client.requested, hasLength(6));
    expect(client.closed, isTrue);
  });

  test('oversized and empty responses are rejected without an image result',
      () async {
    for (final response in [
      _Response(const [], length: 10 * 1024 * 1024 + 1),
      _Response(const []),
    ]) {
      final client = _Client((_) => response);
      final request = OnlineArtworkRequest(httpClientFactory: () => client);
      await expectLater(
          request.loadPng('https://example.com/cover'), throwsFormatException);
      expect(client.closed, isTrue);
    }
  });

  test('non-image server data is never passed to the metadata editor',
      () async {
    final client = _Client((_) => _Response([1, 2, 3]));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);
    await expectLater(
        request.loadPng('https://example.com/cover'), throwsA(anything));
    expect(client.closed, isTrue);
  });

  test('cancellation at response completion does not produce artwork',
      () async {
    final fixture = await _smallPng();
    late OnlineArtworkRequest request;
    final client =
        _Client((_) => _Response(fixture, onListen: () => request.cancel()));
    request = OnlineArtworkRequest(httpClientFactory: () => client);
    await expectLater(request.loadPng('https://example.com/cover'),
        throwsA(isA<HttpException>()));
    expect(client.closed, isTrue);
  });
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

class _Client implements HttpClient {
  _Client(this.response);
  final _Response Function(Uri) response;
  final requested = <Uri>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    return _Request(response(url));
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final HttpHeaders headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers([this.location]);
  final String? location;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes,
      {int? length, int status = 200, String? location, this.onListen})
      : contentLength = length ?? bytes.length,
        statusCode = status,
        headers = _Headers(location);
  final List<int> bytes;
  final void Function()? onListen;
  @override
  final int contentLength;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    onListen?.call();
    return Stream.value(bytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
