import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/fake_window_mode_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('missing/invalid containers retain both built-in default sources', () {
    for (final value in [null, 'qq', 0, false, <String, Object>{}]) {
      expect(OnlineSourcePreferences.fromJson(value),
          const OnlineSourcePreferences());
    }
    expect(const OnlineSourcePreferences().enabledSources,
        [OnlineMusicSource.qq, OnlineMusicSource.netease]);
  });

  test(
      'explicit empty array disables all sources rather than restoring defaults',
      () {
    final preferences = OnlineSourcePreferences.fromJson(const []);
    expect(preferences.isEmpty, isTrue);
    expect(preferences.toJson(), isEmpty);
    expect(
        OnlineSourcePreferences.fromJson(
            jsonDecode(jsonEncode(preferences.toJson()))),
        preferences);
  });

  for (final qq in [true, false]) {
    for (final netease in [true, false]) {
      test('qq=$qq netease=$netease round trips and switches independently',
          () {
        final preferences =
            OnlineSourcePreferences(qqEnabled: qq, neteaseEnabled: netease);
        expect(
            OnlineSourcePreferences.fromJson(
                jsonDecode(jsonEncode(preferences.toJson()))),
            preferences);
        final changed = preferences.withEnabled(OnlineMusicSource.qq, !qq);
        expect(changed.qqEnabled, !qq);
        expect(changed.neteaseEnabled, netease);
        expect(preferences.qqEnabled, qq);
        expect(
            preferences
                .withEnabled(OnlineMusicSource.netease, !netease)
                .qqEnabled,
            qq);
      });
    }
  }

  test(
      'unknown IDs are not executed or silently converted into enabled providers',
      () {
    expect(
        OnlineSourcePreferences.fromJson(const ['plugin', 'qq', null, 7, 'qq'])
            .toJson(),
        ['qq']);
    expect(OnlineSourcePreferences.fromJson(const ['plugin']).isEmpty, isTrue);
    expect(OnlineMusicSource.fromId('plugin'), isNull);
    expect(OnlineMusicSource.fromId('qq'), OnlineMusicSource.qq);
    expect(OnlineMusicSource.values, hasLength(2));
  });

  group('isolated OnlineSources settings persistence', () {
    const windowChannel = MethodChannel('window_manager');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory parent;
    late Directory root;
    late File file;
    late OnlineSourcePreferences previous;
    late BackgroundPreferences previousBackgrounds;
    late bool previousDynamic;

    setUp(() async {
      expect(
          Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
      parent = await Directory(
              path.join(Directory.current.path, 'build', 'test-data'))
          .create(recursive: true);
      root = await parent.createTemp('source-settings-');
      messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
      final window = FakeWindowModeAdapter();
      messenger.setMockMethodCallHandler(
          windowChannel, window.handleMethodCall);
      final data = await getAppDataDir();
      expect(path.isWithin(root.path, data.path), isTrue);
      file = File(path.join(data.path, 'settings.json'));
      previous = AppSettings.instance.onlineSources.value;
      previousBackgrounds = AppSettings.instance.backgrounds.value;
      previousDynamic = AppSettings.instance.dynamicTheme;
    });

    tearDown(() async {
      AppSettings.instance.onlineSources.value = previous;
      AppSettings.instance.backgrounds.value = previousBackgrounds;
      AppSettings.instance.dynamicTheme = previousDynamic;
      messenger.setMockMethodCallHandler(windowChannel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      final resolvedParent = await parent.resolveSymbolicLinks();
      final resolvedRoot = await root.resolveSymbolicLinks();
      if (!path.isWithin(resolvedParent, resolvedRoot) ||
          !path.basename(resolvedRoot).startsWith('source-settings-')) {
        throw StateError('Refusing to remove an unverified settings fixture');
      }
      await Directory(resolvedRoot).delete(recursive: true);
    });

    test(
        'missing key resets a legacy snapshot to defaults without changing backgrounds',
        () async {
      final background = const BackgroundPreferences().withScene(
          BackgroundScene.main,
          const BackgroundAppearance(
              source: BackgroundSource.solid, opacity: .6));
      await file.writeAsString(jsonEncode({
        'Version': '26.0.3',
        'DynamicTheme': false,
        'Backgrounds': background.toMap()
      }));
      AppSettings.instance.onlineSources.value = const OnlineSourcePreferences(
          qqEnabled: false, neteaseEnabled: false);
      await AppSettings.readFromJson();
      expect(AppSettings.instance.onlineSources.value,
          const OnlineSourcePreferences());
      expect(AppSettings.instance.backgrounds.value, background);
      expect(AppSettings.instance.dynamicTheme, isFalse);
    });

    for (final sources in [
      <String>[],
      ['qq'],
      ['netease'],
      ['qq', 'netease']
    ]) {
      test('OnlineSources $sources survives save/reload using exact stable key',
          () async {
        final value = OnlineSourcePreferences.fromJson(sources);
        AppSettings.instance.onlineSources.value = value;
        final background = AppSettings.instance.backgrounds.value;
        await AppSettings.instance.saveSettings();
        final saved = jsonDecode(await file.readAsString()) as Map;
        expect(saved['OnlineSources'], sources);
        expect(saved['Version'], '26.0.3');
        expect(saved['Backgrounds'], background.toMap());
        AppSettings.instance.onlineSources.value =
            const OnlineSourcePreferences();
        await AppSettings.readFromJson();
        expect(AppSettings.instance.onlineSources.value, value);
      });
    }
  });
}
