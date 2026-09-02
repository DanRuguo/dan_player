import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _track(String provider, String id) => Audio.online(
    provider: provider,
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    duration: 60,
    created: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'defaults start both sources concurrently and merge in original provider order',
      () async {
    final qq = Completer<List<Audio>>();
    final netease = Completer<List<Audio>>();
    final started = <String>[];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(),
      qqSearch: (query, limit) {
        started.add('qq:$query:$limit');
        return qq.future;
      },
      neteaseSearch: (query, limit) {
        started.add('netease:$query:$limit');
        return netease.future;
      },
    );
    final pending = service.search('  song  ');
    expect(started, ['qq:song:30', 'netease:song:30']);
    final first = _track('qq', '1');
    final second = _track('netease', '2');
    netease.complete([second]);
    qq.complete([first]);
    final response = await pending;
    expect(response.tracks, [first, second]);
    expect(response.failures, isEmpty);
    expect(response.hasPartialFailure, isFalse);
  });

  for (final source in OnlineMusicSource.values) {
    test('only ${source.id} is called when the other source is disabled',
        () async {
      final calls = <String>[];
      final preferences =
          const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false)
              .withEnabled(source, true);
      final service = OnlineMusicService.forTesting(
        sourcePreferences: () => preferences,
        qqSearch: (_, __) async {
          calls.add('qq');
          return [_track('qq', '1')];
        },
        neteaseSearch: (_, __) async {
          calls.add('netease');
          return [_track('netease', '2')];
        },
      );
      final response = await service.search('song');
      expect(calls, [source.id]);
      expect(response.tracks.single.onlineProvider, source.id);
      expect(response.failures, isEmpty);
    });
  }

  test(
      'production entry with all sources off raises the actionable error before any HTTP client',
      () async {
    final old = AppSettings.instance.onlineSources.value;
    addTearDown(() => AppSettings.instance.onlineSources.value = old);
    final oldCustom = AppSettings.instance.customMusicSources.value;
    addTearDown(
        () => AppSettings.instance.customMusicSources.value = oldCustom);
    AppSettings.instance.customMusicSources.value = [];
    AppSettings.instance.onlineSources.value =
        const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false);
    var clients = 0;
    await HttpOverrides.runZoned(() async {
      await expectLater(
          OnlineMusicService.instance.search('song'),
          throwsA(isA<OnlineMusicException>()
              .having((error) => error.kind, 'kind',
                  OnlineMusicFailureKind.unavailable)
              .having((error) => error.message, 'message',
                  onlineSourcesDisabledMessage)));
    }, createHttpClient: (_) {
      clients++;
      throw StateError('Unexpected HTTP client');
    });
    expect(clients, 0);
    expect(PlayService.isInitialized, isFalse);
  });

  test(
      'empty query preserves the existing empty response without any source calls',
      () async {
    var calls = 0;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(
          qqEnabled: false, neteaseEnabled: false),
      qqSearch: (_, __) async {
        calls++;
        return [];
      },
      neteaseSearch: (_, __) async {
        calls++;
        return [];
      },
    );
    final response = await service.search('  ');
    expect(response.tracks, isEmpty);
    expect(response.failures, isEmpty);
    expect(calls, 0);
  });

  test('limits are still clamped and query is trimmed for each enabled source',
      () async {
    final inputs = <(String, int)>[];
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () =>
          const OnlineSourcePreferences(neteaseEnabled: false),
      qqSearch: (query, limit) async {
        inputs.add((query, limit));
        return [];
      },
      neteaseSearch: (_, __) async => throw StateError('Disabled hook called'),
    );
    for (final limit in [-10, 0, 1, 30, 50, 100]) {
      await service.search('  query ', limit: limit);
    }
    expect(inputs, [
      ('query', 1),
      ('query', 1),
      ('query', 1),
      ('query', 30),
      ('query', 50),
      ('query', 50)
    ]);
  });

  test(
      'changing settings while a search is in flight affects only subsequent searches',
      () async {
    var preferences = const OnlineSourcePreferences();
    final qq = Completer<List<Audio>>();
    final netease = Completer<List<Audio>>();
    var qqCalls = 0;
    var neteaseCalls = 0;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => preferences,
      qqSearch: (_, __) {
        qqCalls++;
        return qq.future;
      },
      neteaseSearch: (_, __) {
        neteaseCalls++;
        return netease.future;
      },
    );
    final pending = service.search('first');
    expect(qqCalls, 1);
    expect(neteaseCalls, 1);
    preferences =
        const OnlineSourcePreferences(qqEnabled: false, neteaseEnabled: false);
    final first = _track('qq', 'first');
    final second = _track('netease', 'second');
    qq.complete([first]);
    netease.complete([second]);
    expect((await pending).tracks, [first, second]);
    await expectLater(
        service.search('next'), throwsA(isA<OnlineMusicException>()));
    expect(qqCalls, 1);
    expect(neteaseCalls, 1);
    preferences = const OnlineSourcePreferences(qqEnabled: false);
    expect((await service.search('third')).tracks, [second]);
    expect(qqCalls, 1);
    expect(neteaseCalls, 2);
  });

  test(
      'partial failure API remains intact and disabled providers add no failures',
      () async {
    final track = _track('netease', 'ok');
    var preferences = const OnlineSourcePreferences();
    var qqCalls = 0;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => preferences,
      qqSearch: (_, __) async {
        qqCalls++;
        throw const SocketException('offline');
      },
      neteaseSearch: (_, __) async => [track],
    );
    final partial = await service.search('first');
    expect(partial.tracks, [track]);
    expect(partial.failures.keys, ['qq']);
    expect(partial.hasPartialFailure, isTrue);
    preferences = const OnlineSourcePreferences(qqEnabled: false);
    final success = await service.search('next');
    expect(success.failures, isEmpty);
    expect(success.hasPartialFailure, isFalse);
    expect(qqCalls, 2,
        reason: 'one bounded retry is used for a transient socket failure');
  });

  test(
      'one enabled failed provider is a full error, not an empty successful response',
      () async {
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () =>
          const OnlineSourcePreferences(neteaseEnabled: false),
      qqSearch: (_, __) async => throw const SocketException('offline'),
      neteaseSearch: (_, __) async => throw StateError('Must not be called'),
    );
    await expectLater(
        service.search('song'),
        throwsA(isA<OnlineMusicException>().having(
            (error) => error.kind, 'kind', OnlineMusicFailureKind.network)));
  });

  test('known transient provider failure is retried once and then succeeds',
      () async {
    var calls = 0;
    final track = _track('qq', 'recovered');
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () =>
          const OnlineSourcePreferences(neteaseEnabled: false),
      qqSearch: (_, __) async {
        calls++;
        if (calls == 1) {
          throw const OnlineMusicException(
            OnlineMusicFailureKind.api,
            'QQ音乐请求遇到临时服务状态（代码 2001）',
            retryable: true,
            serviceCode: 2001,
          );
        }
        return [track];
      },
      neteaseSearch: (_, __) async => throw StateError('Must not be called'),
    );
    final response = await service.search('卡农');
    expect(calls, 2);
    expect(response.tracks, [track]);
    expect(response.failures, isEmpty);
  });

  test('permanent API/schema failure is never retried', () async {
    var calls = 0;
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () =>
          const OnlineSourcePreferences(neteaseEnabled: false),
      qqSearch: (_, __) async {
        calls++;
        throw const OnlineMusicException(
          OnlineMusicFailureKind.api,
          '返回格式异常',
        );
      },
      neteaseSearch: (_, __) async => throw StateError('Must not be called'),
    );
    await expectLater(
      service.search('卡农'),
      throwsA(isA<OnlineMusicException>()
          .having((error) => error.kind, 'kind', OnlineMusicFailureKind.api)),
    );
    expect(calls, 1);
  });

  test('deduplication still uses provider descriptor identities', () async {
    final qq = _track('qq', 'same-id');
    final netease = _track('netease', 'same-id');
    final service = OnlineMusicService.forTesting(
      sourcePreferences: () => const OnlineSourcePreferences(),
      qqSearch: (_, __) async => [qq, qq],
      neteaseSearch: (_, __) async => [netease],
    );
    final result = await service.search('same');
    expect(result.tracks, [qq, netease]);
    expect(qq.path, isNot(netease.path));
  });

  test('known sources allow download attempts independently of search switches',
      () {
    for (final source in OnlineMusicSource.values) {
      final track = _track(source.id, '1');
      expect(source.supportsDownload, isTrue);
      expect(OnlineMusicService.instance.canDownload(track), isTrue);
      expect(
          OnlineMusicService.instance.downloadUnavailableReason(track), isNull);
    }
  });
}
