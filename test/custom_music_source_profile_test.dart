import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('custom music source profile', () {
    test('round trips capabilities, endpoints and non-secret authentication',
        () {
      final authentication = CustomMusicSourceAuthentication.tryCreate(
        kind: CustomMusicSourceAuthenticationKind.apiKeyHeader,
        credentialRef: 'source-kugou-key',
      );
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'self-hosted-kugou',
        name: '家庭歌源',
        baseUrl: 'https://music.example.test/api/',
        enabled: false,
        capabilities: CustomMusicSourceCapability.values,
        endpoints: const {
          CustomMusicSourceCapability.search: 'v1/search',
          CustomMusicSourceCapability.lyrics: '/v1/lyrics',
          CustomMusicSourceCapability.stream:
              'https://stream.example.test/resolve',
        },
        publicHeaders: const {
          'Accept-Language': 'zh-CN',
          'X-Client': 'Dan Player',
          'Authorization': 'must-not-be-saved',
          'X-Auth-Token': 'must-not-be-saved-either',
        },
        authentication: authentication,
      );

      expect(profile, isNotNull);
      expect(profile!.publicHeaders, {
        'Accept-Language': 'zh-CN',
        'X-Client': 'Dan Player',
      });
      expect(profile.endpointFor(CustomMusicSourceCapability.search),
          Uri.parse('https://music.example.test/api/v1/search'));
      expect(profile.endpointFor(CustomMusicSourceCapability.lyrics),
          Uri.parse('https://music.example.test/v1/lyrics'));
      expect(profile.providerId, 'custom:self-hosted-kugou');
      expect(
        CustomMusicSourceProfile.profileIdFromProvider(profile.providerId),
        profile.id,
      );
      expect(CustomMusicSourceProfile.profileIdFromProvider('qq'), isNull);
      expect(CustomMusicSourceProfile.profileIdFromProvider('custom:../bad'),
          isNull);

      final encoded = jsonEncode(profile.toJson());
      expect(profile.toJson()['protocol'], 'dan-source-v1');
      expect(encoded, isNot(contains('must-not-be-saved')));
      expect(encoded, isNot(contains(r'C:\Users\')));
      expect(CustomMusicSourceProfile.fromJson(jsonDecode(encoded)), profile);
      expect(profile.toString(), isNot(contains(profile.baseUrl)));
      expect(profile.toString(), isNot(contains('source-kugou-key')));
      expect(authentication.toString(), contains('redacted'));
      expect(authentication.toString(), isNot(contains('source-kugou-key')));

      final oldProfileJson = Map<String, Object>.of(profile.toJson())
        ..remove('protocol');
      expect(CustomMusicSourceProfile.fromJson(oldProfileJson)?.protocol,
          CustomMusicSourceProtocol.danSourceV1);
      final goMusicApi = profile.copyWith(
        protocol: CustomMusicSourceProtocol.goMusicApi,
      );
      expect(goMusicApi.toJson()['protocol'], 'go-music-api-v1');
      expect(
          CustomMusicSourceProfile.fromJson(goMusicApi.toJson()), goMusicApi);
    });

    test('rejects filesystem URLs and unsafe endpoint traversal', () {
      expect(
        CustomMusicSourceProfile.tryCreate(
          id: 'local-file',
          name: 'Local',
          baseUrl: r'C:\Users\person\source',
          capabilities: const {CustomMusicSourceCapability.search},
        ),
        isNull,
      );
      final profile = CustomMusicSourceProfile.tryCreate(
        id: 'safe-source',
        name: 'Safe',
        baseUrl: 'http://127.0.0.1:3000/',
        capabilities: const {CustomMusicSourceCapability.search},
        endpoints: const {
          CustomMusicSourceCapability.search: '../private',
        },
      );
      expect(profile, isNotNull);
      expect(profile!.endpoints, isEmpty);
    });

    test('search owns metadata and cover while legacy stays lyric-only', () {
      expect(
        CustomMusicSourceProfile.tryCreate(
          id: 'orphan-cover',
          name: 'Orphan cover',
          baseUrl: 'https://source.example/',
          capabilities: const {CustomMusicSourceCapability.cover},
        ),
        isNull,
      );
      expect(
        CustomMusicSourceProfile.tryCreate(
          id: CustomMusicSourceProfile.legacyLyricProfileId,
          name: 'Unsafe legacy',
          baseUrl: 'https://source.example/',
          protocol: CustomMusicSourceProtocol.legacyLyrics,
          capabilities: const {
            CustomMusicSourceCapability.lyrics,
            CustomMusicSourceCapability.stream,
          },
          endpoints: const {
            CustomMusicSourceCapability.lyrics: '/lyrics',
            CustomMusicSourceCapability.stream: '/stream',
          },
        ),
        isNull,
      );
    });

    test('valid modern settings stay authoritative over legacy fields', () {
      final valid = CustomMusicSourceProfile.tryCreate(
        id: 'one',
        name: 'One',
        baseUrl: 'https://one.example/',
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.cover,
        },
        endpoints: const {CustomMusicSourceCapability.search: '/search'},
      )!;
      final duplicate = valid.copyWith(name: 'Duplicate');
      final decoded = CustomMusicSourceProfileCodec.decodeSettings(
        {
          'version': 1,
          'unknownFutureField': true,
          'profiles': [
            {
              ...valid.toJson(),
              'unknown': {'ignored': true}
            },
            {'id': 'broken', 'name': 'Broken'},
            duplicate.toJson(),
            'not a profile',
          ],
        },
        legacyLyricApiUrl: 'https://legacy.example/lyric',
      );
      expect(decoded.map((profile) => profile.id), [
        'one',
        CustomMusicSourceProfile.kugouProfileId,
      ]);
      expect(decoded.first, valid);
      expect(decoded.where((profile) => profile.isLegacyLyricProfile), isEmpty);

      final fallback = [valid];
      expect(
        CustomMusicSourceProfileCodec.decodeSettings(
          {'version': 999, 'profiles': []},
          fallback: fallback,
        ),
        fallback,
      );
      expect(
        CustomMusicSourceProfileCodec.decodeSettings(
          {'version': 1, 'profiles': []},
          fallback: fallback,
        ),
        isEmpty,
      );
    });

    test('modern and old lyric-only backups preserve every usable profile', () {
      final first = CustomMusicSourceProfile.tryCreate(
        id: 'lyrics-a',
        name: 'Lyrics A',
        baseUrl: 'https://a.example/',
        capabilities: const {CustomMusicSourceCapability.lyrics},
        endpoints: const {CustomMusicSourceCapability.lyrics: '/lyrics'},
      )!;
      final modern = CustomMusicSourceProfileCodec.encodeBackup(
        [first],
        createdAt: DateTime.utc(2026, 9, 2),
      );
      expect(CustomMusicSourceProfileCodec.decodeBackup(modern), [first]);

      final oldBackup = {
        'version': 1,
        'currentLyricApiUrl': 'https://current.example/lyrics',
        'apis': [
          {
            'type': 'lyric',
            'name': 'Current duplicate',
            'url': 'https://current.example/lyrics',
          },
          {
            'type': 'lyric',
            'name': 'Second lyrics',
            'url': 'https://second.example/lyrics',
          },
          {'type': 'cover', 'url': 'https://ignored.example/cover'},
          {'type': 'lyric', 'url': r'C:\private\lyrics'},
        ],
      };
      final imported = CustomMusicSourceProfileCodec.decodeBackup(oldBackup);
      expect(imported, hasLength(2));
      expect(imported.first.id, CustomMusicSourceProfile.legacyLyricProfileId);
      expect(imported.last.name, 'Second lyrics');
      expect(
        CustomMusicSourceProfileCodec.decodeBackup(oldBackup).last.id,
        imported.last.id,
        reason: 'A migrated backup entry needs a stable deterministic ID.',
      );
    });

    test('LRC API keeps its stable ID when protocol and capabilities change',
        () {
      final source = CustomMusicSourceProfile.lrcApiPreset().copyWith(
        name: 'My source',
        protocol: CustomMusicSourceProtocol.danSourceV1,
        capabilities: const {CustomMusicSourceCapability.search},
        endpoints: const {CustomMusicSourceCapability.search: '/search'},
      );
      expect(source.id, CustomMusicSourceProfile.legacyLyricProfileId);
      expect(source.protocol, CustomMusicSourceProtocol.danSourceV1);
      final decoded = CustomMusicSourceProfileCodec.decodeSettings(
        CustomMusicSourceProfileCodec.encodeSettings([source]),
        legacyLyricApiUrl: 'https://stale.example/lyrics',
      );
      expect(decoded, [source]);
    });

    test(
        'default preset migration runs once and never revives explicit deletions',
        () {
      final defaults = CustomMusicSourceProfile.builtInPresets();
      expect(defaults.map((profile) => profile.id), [
        CustomMusicSourceProfile.legacyLyricProfileId,
        CustomMusicSourceProfile.kugouProfileId,
        'netease-api',
      ]);
      expect(defaults.take(2).every((profile) => profile.enabled), isTrue);
      expect(defaults.last.enabled, isFalse);
      final old =
          CustomMusicSourceProfile.legacyLyric('https://mine.example/lyrics')!
              .copyWith(name: 'My lyrics', enabled: false);
      final migrated = CustomMusicSourceProfileCodec.decodeSettings({
        'version': 1,
        'profiles': [old.toJson()],
      });
      expect(migrated.first, old);
      expect(migrated.last, CustomMusicSourceProfile.kugouPreset());
      final deletedKugou = CustomMusicSourceProfileCodec.encodeSettings([old]);
      expect(CustomMusicSourceProfileCodec.decodeSettings(deletedKugou), [old]);
      final deletedLrc = CustomMusicSourceProfileCodec.encodeSettings(
          [CustomMusicSourceProfile.kugouPreset()]);
      expect(
        CustomMusicSourceProfileCodec.decodeSettings(deletedLrc,
            legacyLyricApiUrl: 'https://stale.example/lyrics'),
        [CustomMusicSourceProfile.kugouPreset()],
      );
      expect(
          CustomMusicSourceProfileCodec.decodeSettings(
            {'version': 1, 'profiles': []},
            legacyLyricApiUrl: 'https://stale.example/lyrics',
          ),
          isEmpty);
    });
  });

  group('custom music source settings persistence', () {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory parent;
    late Directory root;
    late File settingsFile;
    late List<CustomMusicSourceProfile> previousProfiles;

    setUp(() async {
      expect(
          Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
      parent = await Directory(
        path.join(Directory.current.path, 'build', 'test-data'),
      ).create(recursive: true);
      root = await parent.createTemp('custom-source-settings-');
      messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
      settingsFile =
          File(path.join((await getAppDataDir()).path, 'settings.json'));
      previousProfiles = AppSettings.instance.customMusicSources.value;
      AppSettings.instance.customMusicSources.value = const [];
    });

    tearDown(() async {
      AppSettings.instance.customMusicSources.value = previousProfiles;
      messenger.setMockMethodCallHandler(pathChannel, null);
      final resolvedParent = await parent.resolveSymbolicLinks();
      final resolvedRoot = await root.resolveSymbolicLinks();
      if (!path.isWithin(resolvedParent, resolvedRoot) ||
          !path.basename(resolvedRoot).startsWith('custom-source-settings-')) {
        throw StateError('Refusing to remove an unverified settings fixture');
      }
      await Directory(resolvedRoot).delete(recursive: true);
    });

    test('multiple profiles save and reload while legacy URL remains readable',
        () async {
      final general = CustomMusicSourceProfile.tryCreate(
        id: 'general-source',
        name: 'General source',
        baseUrl: 'https://source.example/v1/',
        capabilities: const {
          CustomMusicSourceCapability.search,
          CustomMusicSourceCapability.metadata,
          CustomMusicSourceCapability.cover,
          CustomMusicSourceCapability.comments,
          CustomMusicSourceCapability.stream,
          CustomMusicSourceCapability.download,
        },
        endpoints: const {CustomMusicSourceCapability.search: 'search'},
      )!;
      AppSettings.instance.customMusicSources.value = [general];
      AppSettings.instance.lyricApiUrl = 'https://lyrics.example/api';

      await AppSettings.instance.saveSettings(
        throwOnError: true,
        captureWindowSize: false,
      );
      final saved = jsonDecode(await settingsFile.readAsString()) as Map;
      expect(saved['CustomMusicSources'], isA<Map>());
      expect((saved['CustomMusicSources'] as Map)['profiles'], hasLength(2));
      expect(saved['LyricApiUrl'], 'https://lyrics.example/api');

      AppSettings.instance.customMusicSources.value = const [];
      await AppSettings.readFromJson();
      expect(AppSettings.instance.customMusicSources.value, [
        general,
        CustomMusicSourceProfile.legacyLyric('https://lyrics.example/api')!,
      ]);
      expect(AppSettings.instance.lyricApiUrl, 'https://lyrics.example/api');
    });

    test('old single URL migrates without replacing an unrelated fallback',
        () async {
      final fallback = CustomMusicSourceProfile.tryCreate(
        id: 'existing',
        name: 'Existing',
        baseUrl: 'https://existing.example/',
        capabilities: const {CustomMusicSourceCapability.search},
      )!;
      AppSettings.instance.customMusicSources.value = [fallback];
      await settingsFile.writeAsString(jsonEncode({
        'Version': '26.0.3',
        'LyricApiUrl': 'https://old.example/lyrics',
        'CustomMusicSources': {'version': 999, 'profiles': []},
      }));

      await AppSettings.readFromJson();
      expect(AppSettings.instance.customMusicSources.value, [
        fallback,
        CustomMusicSourceProfile.legacyLyric('https://old.example/lyrics')!,
      ]);

      AppSettings.instance.lyricApiUrl = 'not a URL';
      expect(AppSettings.instance.customMusicSources.value.first, fallback);
      expect(AppSettings.instance.lyricApiUrl, 'https://old.example/lyrics');
      AppSettings.instance.lyricApiUrl = null;
      expect(AppSettings.instance.customMusicSources.value, [fallback]);
    });
  });
}
