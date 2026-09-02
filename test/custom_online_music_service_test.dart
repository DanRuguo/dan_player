import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom source downloads public URLs without extra grant fields',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    final subscription = server.listen((request) async {
      requests.add(request.uri);
      switch (request.uri.path) {
        case '/search':
          request.response.headers.contentType = ContentType.json;
          request.response.write('''
            {"tracks":[{"id":"track-1","title":"Custom result",
            "artist":"Artist","album":"Album","duration":90,
            "streamAvailable":true}]}
          ''');
        case '/stream':
        case '/download':
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"url":"http://127.0.0.1:${server.port}/media.mp3"}',
          );
        case '/stream-2':
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"url":"http://127.0.0.1:${server.port}/media-2.mp3",'
            '"downloadAllowed":true}',
          );
        case '/media.mp3':
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.add(const [1, 2, 3, 4]);
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'test-source',
      name: 'Test source',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {
        CustomMusicSourceCapability.search,
        CustomMusicSourceCapability.stream,
        CustomMusicSourceCapability.download,
      },
      endpoints: const {
        CustomMusicSourceCapability.search: '/search',
        CustomMusicSourceCapability.stream: '/stream',
        CustomMusicSourceCapability.download: '/download',
      },
    )!;
    var profiles = <CustomMusicSourceProfile>[profile];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    final response = await service.search('  custom query  ');
    final track = response.tracks.single;
    expect(track.onlineProvider, profile.providerId);
    expect(track.onlinePlayable, isTrue);
    expect(track.onlineDownloadAllowed, isNull);
    expect(service.canDownload(track), isTrue);
    expect(await service.resolveStreamUrl(track),
        Uri.parse('http://127.0.0.1:${server.port}/media.mp3'));

    final root = await Directory.systemTemp.createTemp('dan-custom-source-');
    addTearDown(() => root.delete(recursive: true));
    final destination = File('${root.path}${Platform.pathSeparator}track.mp3');
    await service.download(track, destination);
    expect(await destination.readAsBytes(), const [1, 2, 3, 4]);
    expect(
        requests
            .where((uri) => uri.path == '/search')
            .single
            .queryParameters['q'],
        'custom query');
    expect(requests.any((uri) => uri.path == '/stream'), isTrue);
    expect(requests.any((uri) => uri.path == '/download'), isTrue);

    final editedProfile = profile.copyWith(endpoints: {
      ...profile.endpoints,
      CustomMusicSourceCapability.stream: '/stream-2',
    });
    profiles = [editedProfile];
    expect(
      await service.resolveStreamUrl(track),
      Uri.parse('http://127.0.0.1:${server.port}/media-2.mp3'),
      reason: 'editing a profile must invalidate its previous stream cache',
    );
    final resolveCount =
        requests.where((uri) => uri.path == '/stream-2').length;
    final explicitlyBlocked = Audio.online(
      provider: track.onlineProvider!,
      id: track.onlineId!,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: track.duration,
      playable: false,
      downloadAllowed: track.onlineDownloadAllowed,
    );
    await expectLater(
      service.resolveStreamUrl(explicitlyBlocked),
      throwsA(isA<OnlineMusicException>().having(
        (error) => error.kind,
        'kind',
        OnlineMusicFailureKind.unavailable,
      )),
    );
    expect(requests.where((uri) => uri.path == '/stream-2'),
        hasLength(resolveCount));

    profiles = [editedProfile.copyWith(enabled: false)];
    await expectLater(
      service.resolveStreamUrl(track),
      throwsA(isA<OnlineMusicException>().having(
        (error) => error.kind,
        'kind',
        OnlineMusicFailureKind.unavailable,
      )),
    );
  });

  test('custom download stays unavailable until credentials can be resolved',
      () {
    final authentication = CustomMusicSourceAuthentication.tryCreate(
      kind: CustomMusicSourceAuthenticationKind.apiKeyHeader,
      credentialRef: 'download-key',
    )!;
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'credential-download',
      name: 'Credential download',
      baseUrl: 'https://example.com',
      capabilities: const {CustomMusicSourceCapability.download},
      endpoints: const {CustomMusicSourceCapability.download: '/download'},
      authentication: authentication,
    )!;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => [profile],
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );
    final track = Audio.online(
      provider: profile.providerId,
      id: 'track-with-credential',
      title: 'Credential track',
      artist: 'Artist',
      album: 'Album',
      duration: 90,
      downloadAllowed: true,
    );

    expect(service.canDownload(track), isFalse);
    expect(service.downloadUnavailableReason(track), '歌源凭据尚未配置');
  });

  test('custom searches use bounded concurrency', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var active = 0;
    var maximumActive = 0;
    var requests = 0;
    final subscription = server.listen((request) async {
      requests++;
      active++;
      if (active > maximumActive) maximumActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"tracks":[]}');
      await request.response.close();
      active--;
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final profiles = <CustomMusicSourceProfile>[
      for (var index = 0; index < 6; index++)
        CustomMusicSourceProfile.tryCreate(
          id: 'source-$index',
          name: 'Source $index',
          baseUrl: 'http://127.0.0.1:${server.port}',
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: '/search'},
        )!,
    ];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    final result = await service.search('bounded');

    expect(result.tracks, isEmpty);
    expect(requests, profiles.length);
    expect(maximumActive, lessThanOrEqualTo(4));
  });

  test('a failing custom service is not automatically retried', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = server.listen((request) async {
      requests++;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'dead-source',
      name: 'Dead source',
      baseUrl: 'http://127.0.0.1:${server.port}',
      capabilities: const {CustomMusicSourceCapability.search},
      endpoints: const {CustomMusicSourceCapability.search: '/search'},
    )!;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => [profile],
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    await expectLater(
        service.search('once'), throwsA(isA<OnlineMusicException>()));
    expect(requests, 1);
  });

  test('custom search sweep has one strict deadline across all profiles',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final subscription = server.listen((request) {
      requests++;
      // Deliberately leave every response pending. Cancelling the sweep must
      // close the transport clients instead of waiting one timeout per source.
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final profiles = <CustomMusicSourceProfile>[
      for (var index = 0; index < 12; index++)
        CustomMusicSourceProfile.tryCreate(
          id: 'stalled-$index',
          name: 'Stalled $index',
          baseUrl: 'http://127.0.0.1:${server.port}',
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: '/search'},
        )!,
    ];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      customSearchSweepTimeout: const Duration(milliseconds: 120),
      customTransportFactory: (profile) => CustomMusicSourceTransport(
        profile,
        requestTimeout: const Duration(seconds: 3),
      ),
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      service.search('deadline'),
      throwsA(isA<OnlineMusicException>()
          .having(
            (error) => error.kind,
            'kind',
            OnlineMusicFailureKind.timeout,
          )
          .having(
            (error) => error.message,
            'message',
            '联网请求超时，请稍后重试',
          )),
    );
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(requests, lessThanOrEqualTo(4));
  });

  test('caller cancellation stops an active custom search immediately',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstRequest = Completer<void>();
    final subscription = server.listen((request) {
      if (!firstRequest.isCompleted) firstRequest.complete();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final profiles = <CustomMusicSourceProfile>[
      for (var index = 0; index < 8; index++)
        CustomMusicSourceProfile.tryCreate(
          id: 'cancelled-$index',
          name: 'Cancelled $index',
          baseUrl: 'http://127.0.0.1:${server.port}',
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: '/search'},
        )!,
    ];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      customTransportFactory: (profile) => CustomMusicSourceTransport(
        profile,
        requestTimeout: const Duration(seconds: 3),
      ),
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );
    final cancellation = OnlineSearchCancellation();
    final pending = service.search('cancel', cancellation: cancellation);
    await firstRequest.future.timeout(const Duration(seconds: 1));

    final stopwatch = Stopwatch()..start();
    cancellation.cancel();
    await expectLater(
      pending,
      throwsA(isA<OnlineMusicException>()
          .having(
            (error) => error.kind,
            'kind',
            OnlineMusicFailureKind.unavailable,
          )
          .having(
            (error) => error.message,
            'message',
            '联网请求已取消',
          )),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('profile edits while resolving stream are rejected before return',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final resolveStarted = Completer<void>();
    final releaseResolve = Completer<void>();
    var mediaRequests = 0;
    final subscription = server.listen((request) async {
      try {
        if (request.uri.path == '/stream') {
          if (!resolveStarted.isCompleted) resolveStarted.complete();
          await releaseResolve.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"url":"http://127.0.0.1:${server.port}/media.mp3",'
            '"downloadAllowed":false}',
          );
        } else if (request.uri.path == '/media.mp3') {
          mediaRequests++;
          request.response.add(const [1, 2, 3]);
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      } catch (_) {
        // The client intentionally closes an invalidated in-flight request.
      }
    });
    addTearDown(() async {
      if (!releaseResolve.isCompleted) releaseResolve.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = _profile(
      id: 'resolve-race',
      port: server.port,
      capabilities: const {
        CustomMusicSourceCapability.stream,
      },
      endpoints: const {
        CustomMusicSourceCapability.stream: '/stream',
      },
    );
    var profiles = <CustomMusicSourceProfile>[profile];
    final service = _customOnlyService(() => profiles);
    final audio = _customAudio(profile, downloadAllowed: false);

    final pending = service.resolveStreamUrl(audio);
    await resolveStarted.future.timeout(const Duration(seconds: 1));
    profiles = [profile.copyWith(name: 'Edited source')];
    releaseResolve.complete();

    await expectLater(
      pending,
      throwsA(isA<OnlineMusicException>().having(
        (error) => error.kind,
        'kind',
        OnlineMusicFailureKind.unavailable,
      )),
    );
    expect(mediaRequests, 0);
  });

  test('search results from an edited profile are discarded', () async {
    final profile = CustomMusicSourceProfile.tryCreate(
      id: 'search-race',
      name: 'Search race',
      baseUrl: 'https://example.com',
      capabilities: const {CustomMusicSourceCapability.search},
      endpoints: const {CustomMusicSourceCapability.search: '/search'},
    )!;
    var profiles = <CustomMusicSourceProfile>[profile];
    final started = Completer<void>();
    final release = Completer<void>();
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      customTransportFactory: (profile) =>
          _ControlledSearchTransport(profile, started, release),
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    final pending = service.search('stale');
    await started.future.timeout(const Duration(seconds: 1));
    profiles = [profile.copyWith(name: 'Edited while searching')];
    release.complete();

    await expectLater(
      pending,
      throwsA(isA<OnlineMusicException>()
          .having(
            (error) => error.kind,
            'kind',
            OnlineMusicFailureKind.unavailable,
          )
          .having(
            (error) => error.message,
            'message',
            '该联网音乐来源当前不可用',
          )),
    );
  });

  test('profile edits during media transfer abort and remove partial download',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mediaStarted = Completer<void>();
    final releaseMedia = Completer<void>();
    final subscription = server.listen((request) async {
      try {
        if (request.uri.path == '/download') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"url":"http://127.0.0.1:${server.port}/media.mp3",'
            '"downloadAllowed":true}',
          );
          await request.response.close();
        } else if (request.uri.path == '/media.mp3') {
          request.response.headers.contentType = ContentType('audio', 'mpeg');
          request.response.contentLength = 4;
          request.response.add(const [1, 2]);
          await request.response.flush();
          if (!mediaStarted.isCompleted) mediaStarted.complete();
          await releaseMedia.future;
          request.response.add(const [3, 4]);
          await request.response.close();
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
      } catch (_) {
        // Expected when the profile monitor closes the media connection.
      }
    });
    addTearDown(() async {
      if (!releaseMedia.isCompleted) releaseMedia.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    final profile = _profile(
      id: 'download-race',
      port: server.port,
      capabilities: const {
        CustomMusicSourceCapability.download,
      },
      endpoints: const {
        CustomMusicSourceCapability.download: '/download',
      },
    );
    var profiles = <CustomMusicSourceProfile>[profile];
    final service = _customOnlyService(() => profiles);
    final audio = _customAudio(profile, downloadAllowed: true);
    final root = await Directory.systemTemp.createTemp('dan-download-race-');
    addTearDown(() => root.delete(recursive: true));
    final destination = File('${root.path}${Platform.pathSeparator}song.mp3');

    final pending = service.download(audio, destination);
    await mediaStarted.future.timeout(const Duration(seconds: 1));
    profiles = [profile.copyWith(enabled: false)];

    await expectLater(
      pending.timeout(const Duration(seconds: 2)),
      throwsA(isA<OnlineMusicException>().having(
        (error) => error.kind,
        'kind',
        OnlineMusicFailureKind.unavailable,
      )),
    );
    expect(await destination.exists(), isFalse);
    expect(
      await root.list().where((entry) => entry.path.endsWith('.part')).toList(),
      isEmpty,
    );
    releaseMedia.complete();
  });

  test('custom transport failures use stable messages without provider names',
      () async {
    final profiles = <CustomMusicSourceProfile>[
      for (final id in const [
        'ok',
        'timeout',
        'network',
        'unavailable',
        'credentials',
        'invalid',
        'large',
        'redirect',
        'denied',
      ])
        CustomMusicSourceProfile.tryCreate(
          id: id,
          name: 'Provider $id',
          baseUrl: 'https://example.com/$id',
          capabilities: const {CustomMusicSourceCapability.search},
          endpoints: const {CustomMusicSourceCapability.search: '/search'},
        )!,
    ];
    final errors = <String, CustomMusicSourceException>{
      'timeout': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.timeout,
        'dynamic timeout detail',
      ),
      'network': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.network,
        'dynamic network detail',
      ),
      'unavailable': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.unavailable,
        'dynamic unavailable detail',
      ),
      'credentials': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.credentialsNotConfigured,
        'secret reference must not escape',
      ),
      'invalid': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.invalidResponse,
        'dynamic schema detail',
      ),
      'large': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.responseTooLarge,
        'dynamic size detail',
      ),
      'redirect': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.redirect,
        'dynamic redirect detail',
      ),
      'denied': const CustomMusicSourceException(
        CustomMusicSourceFailureKind.http,
        'dynamic HTTP detail',
        statusCode: 403,
      ),
    };
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: () => profiles,
      customTransportFactory: (profile) => profile.id == 'ok'
          ? _SuccessfulSearchTransport(profile)
          : _FailingSearchTransport(profile, errors[profile.id]!),
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

    final response = await service.search('messages');

    expect(response.tracks, hasLength(1));
    expect(response.failures['custom:timeout'], '联网请求超时，请稍后重试');
    expect(response.failures['custom:network'], '联网失败，请检查网络连接');
    expect(response.failures['custom:unavailable'], '该联网音乐来源当前不可用');
    expect(response.failures['custom:credentials'], '歌源凭据尚未配置');
    expect(response.failures['custom:invalid'], '音乐服务返回的数据无效或过大');
    expect(response.failures['custom:large'], '音乐服务返回的数据无效或过大');
    expect(response.failures['custom:redirect'], '音乐服务拒绝了请求');
    expect(response.failures['custom:denied'], '音乐服务要求登录或拒绝访问此歌曲');
    for (final entry in response.failures.entries) {
      expect(entry.value, isNot(contains(entry.key)));
      expect(entry.value, isNot(contains('dynamic')));
      expect(entry.value, isNot(contains('secret reference')));
    }
  });
}

CustomMusicSourceProfile _profile({
  required String id,
  required int port,
  required Set<CustomMusicSourceCapability> capabilities,
  required Map<CustomMusicSourceCapability, String> endpoints,
}) =>
    CustomMusicSourceProfile.tryCreate(
      id: id,
      name: 'Test $id',
      baseUrl: 'http://127.0.0.1:$port',
      capabilities: capabilities,
      endpoints: endpoints,
    )!;

Audio _customAudio(
  CustomMusicSourceProfile profile, {
  required bool downloadAllowed,
}) =>
    Audio.online(
      provider: profile.providerId,
      id: 'track-1',
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      duration: 60,
      playable: true,
      downloadAllowed: downloadAllowed,
    );

OnlineMusicService _customOnlyService(
  List<CustomMusicSourceProfile> Function() profiles,
) =>
    OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
        qqEnabled: false,
        neteaseEnabled: false,
      ),
      customProfiles: profiles,
      qqSearch: (_, __) async => throw StateError('Built-in source called'),
      neteaseSearch: (_, __) async =>
          throw StateError('Built-in source called'),
    );

class _FailingSearchTransport extends CustomMusicSourceTransport {
  _FailingSearchTransport(super.profile, this.error);

  final CustomMusicSourceException error;

  @override
  Future<CustomMusicSearchResult> search(
    String rawQuery, {
    int limit = CustomMusicSourceTransport.maximumSearchResults,
    CustomMusicSourceCancellation? cancellation,
  }) async =>
      throw error;
}

class _SuccessfulSearchTransport extends CustomMusicSourceTransport {
  _SuccessfulSearchTransport(super.profile);

  @override
  Future<CustomMusicSearchResult> search(
    String rawQuery, {
    int limit = CustomMusicSourceTransport.maximumSearchResults,
    CustomMusicSourceCancellation? cancellation,
  }) async =>
      CustomMusicSearchResult(
        providerId: profile.providerId,
        tracks: [_customAudio(profile, downloadAllowed: false)],
        reachedLimit: false,
      );
}

class _ControlledSearchTransport extends CustomMusicSourceTransport {
  _ControlledSearchTransport(super.profile, this.started, this.release);

  final Completer<void> started;
  final Completer<void> release;

  @override
  Future<CustomMusicSearchResult> search(
    String rawQuery, {
    int limit = CustomMusicSourceTransport.maximumSearchResults,
    CustomMusicSourceCancellation? cancellation,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return CustomMusicSearchResult(
      providerId: profile.providerId,
      tracks: [_customAudio(profile, downloadAllowed: false)],
      reachedLimit: false,
    );
  }
}
