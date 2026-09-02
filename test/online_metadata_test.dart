import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/online_metadata_lookup_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
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

  test('enabled custom source may load cover over its own HTTP host', () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'local-cover',
      name: 'Local cover source',
      baseUrl: 'http://127.0.0.1:8123',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.cover,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/search',
        CustomMusicSourceCapability.cover: '/cover',
      },
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final fixture = await _smallPng();
    final client = _Client((_) => _Response(fixture));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);

    await request.loadPng(
      'http://127.0.0.1:8123/cover?id=1',
      provider: profile.providerId,
      expectedProfile: profile,
    );

    expect(client.requested.single.scheme, 'http');
  });

  test('stale expected custom profile is rejected before opening a client',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'stale-cover',
      name: 'Stale cover source',
      baseUrl: 'http://127.0.0.1:8126',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.cover,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/search',
        CustomMusicSourceCapability.cover: '/cover',
      },
    )!;
    final equivalentReplacement = profile.copyWith();
    expect(equivalentReplacement, equals(profile));
    expect(identical(equivalentReplacement, profile), isFalse);
    AppSettings.instance.customMusicSources.value = [equivalentReplacement];
    var opened = false;
    final request = OnlineArtworkRequest(httpClientFactory: () {
      opened = true;
      return _Client((_) => _Response(const []));
    });

    await expectLater(
      request.loadPng(
        'http://127.0.0.1:8126/cover',
        provider: profile.providerId,
        expectedProfile: profile,
      ),
      throwsFormatException,
    );
    expect(opened, isFalse);
  });

  test('custom cover rejects disabled, edited and unrelated HTTP sources',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'strict-cover',
      name: 'Strict cover source',
      baseUrl: 'http://127.0.0.1:8124',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.cover,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/search',
        CustomMusicSourceCapability.cover: '/cover',
      },
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    var opened = false;
    var request = OnlineArtworkRequest(httpClientFactory: () {
      opened = true;
      return _Client((_) => _Response(const []));
    });
    await expectLater(
      request.loadPng(
        'http://192.168.1.5:8124/old-cover',
        provider: profile.providerId,
      ),
      throwsFormatException,
    );
    expect(opened, isFalse,
        reason: 'custom HTTP is restricted to the configured host and port');

    AppSettings.instance.customMusicSources.value = [
      profile.copyWith(enabled: false),
    ];
    request = OnlineArtworkRequest(httpClientFactory: () {
      opened = true;
      return _Client((_) => _Response(const []));
    });
    await expectLater(
      request.loadPng(
        'https://127.0.0.1:8124/cover',
        provider: profile.providerId,
      ),
      throwsFormatException,
    );

    final authentication = CustomMusicSourceAuthentication.tryCreate(
      kind: CustomMusicSourceAuthenticationKind.bearerHeader,
      credentialRef: 'cover-token',
    )!;
    for (final unavailableProfile in [
      profile.copyWith(
        capabilities: const {CustomMusicSourceCapability.search},
      ),
      profile.copyWith(authentication: authentication),
    ]) {
      AppSettings.instance.customMusicSources.value = [unavailableProfile];
      var invalidProfileOpened = false;
      request = OnlineArtworkRequest(httpClientFactory: () {
        invalidProfileOpened = true;
        return _Client((_) => _Response(const []));
      });
      await expectLater(
        request.loadPng(
          'https://127.0.0.1:8124/cover',
          provider: profile.providerId,
        ),
        throwsFormatException,
      );
      expect(invalidProfileOpened, isFalse);
    }

    AppSettings.instance.customMusicSources.value = [profile];
    final fixture = await _smallPng();
    late _Client editingClient;
    editingClient = _Client((_) => _Response(
          fixture,
          onListen: () {
            AppSettings.instance.customMusicSources.value = [
              profile.copyWith(name: 'Edited source'),
            ];
          },
        ));
    request = OnlineArtworkRequest(httpClientFactory: () => editingClient);
    await expectLater(
      request.loadPng(
        'http://127.0.0.1:8124/cover',
        provider: profile.providerId,
      ),
      throwsA(isA<HttpException>()),
    );
    expect(editingClient.requested, hasLength(1));

    AppSettings.instance.customMusicSources.value = [profile];
    final bodyDelivered = Completer<void>();
    final finishBody = Completer<void>();
    final completedBodyClient = _Client((_) => _DeferredDoneResponse(
          fixture,
          delivered: bodyDelivered,
          finish: finishBody,
        ));
    request =
        OnlineArtworkRequest(httpClientFactory: () => completedBodyClient);
    final pendingDecode = request.loadPng(
      'http://127.0.0.1:8124/cover',
      provider: profile.providerId,
    );
    await bodyDelivered.future;
    AppSettings.instance.customMusicSources.value = [
      profile.copyWith(name: 'Edited before decode'),
    ];
    finishBody.complete();
    await expectLater(
      pendingDecode,
      throwsA(isA<HttpException>()),
    );
  });

  test('custom cover public headers never leak across an origin redirect',
      () async {
    final previous = AppSettings.instance.customMusicSources.value;
    addTearDown(() => AppSettings.instance.customMusicSources.value = previous);
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'header-cover',
      name: 'Header cover source',
      baseUrl: 'http://127.0.0.1:8125',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.cover,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/search',
        CustomMusicSourceCapability.cover: '/cover',
      },
      publicHeaders: const {'X-Public-Tenant': 'tenant-a'},
    )!;
    AppSettings.instance.customMusicSources.value = [profile];
    final fixture = await _smallPng();
    final client = _Client((uri) => uri.host == '127.0.0.1'
        ? _Response(
            const [],
            status: 302,
            location: 'https://cdn.example.test/cover.png',
          )
        : _Response(fixture));
    final request = OnlineArtworkRequest(httpClientFactory: () => client);

    await request.loadPng(
      'http://127.0.0.1:8125/cover?id=1',
      provider: profile.providerId,
    );

    expect(client.requested, hasLength(2));
    expect(client.requestHeaders[0]['x-public-tenant'], 'tenant-a');
    expect(client.requestHeaders[1], isNot(contains('x-public-tenant')));
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

  test('artwork deadline covers the whole multi-stage request', () async {
    final fixture = await _smallPng();
    var bodyStarted = false;
    final client = _Client(
      (_) => _Response(
        fixture,
        delay: const Duration(milliseconds: 90),
        onListen: () => bodyStarted = true,
      ),
      closeDelay: const Duration(milliseconds: 90),
    );
    final request = OnlineArtworkRequest(
      httpClientFactory: () => client,
      totalTimeout: const Duration(milliseconds: 150),
    );

    await expectLater(
      request.loadPng('https://example.com/cover'),
      throwsA(isA<TimeoutException>()),
    );

    expect(bodyStarted, isTrue,
        reason: 'each phase is shorter than the deadline on its own');
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
  _Client(this.response, {this.closeDelay = Duration.zero});
  final _Response Function(Uri) response;
  final Duration closeDelay;
  final requested = <Uri>[];
  final requestHeaders = <Map<String, String>>[];
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    final headers = _Headers();
    requestHeaders.add(headers.values);
    return _Request(response(url), headers, closeDelay);
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response, this.headers, this.closeDelay);
  final _Response response;
  final Duration closeDelay;
  @override
  final HttpHeaders headers;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async {
    if (closeDelay > Duration.zero) await Future<void>.delayed(closeDelay);
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers([this.location]);
  final String? location;
  final Map<String, String> values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.bytes,
      {int? length,
      int status = 200,
      String? location,
      this.delay = Duration.zero,
      this.onListen})
      : contentLength = length ?? bytes.length,
        statusCode = status,
        headers = _Headers(location);
  final List<int> bytes;
  final Duration delay;
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
    final stream = delay > Duration.zero
        ? Stream<List<int>>.fromFuture(
            Future<List<int>>.delayed(delay, () => bytes),
          )
        : Stream<List<int>>.value(bytes);
    return stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredDoneResponse extends _Response {
  _DeferredDoneResponse(
    super.bytes, {
    required this.delivered,
    required this.finish,
  });

  final Completer<void> delivered;
  final Completer<void> finish;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final body = bytes;
    return (() async* {
      yield body;
      if (!delivered.isCompleted) delivered.complete();
      await finish.future;
    })()
        .listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
