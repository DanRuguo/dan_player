import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/fake_window_mode_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults keep desktop chrome and artwork lyrics independently', () {
    const value = BackgroundPreferences();
    expect(value.main.source, BackgroundSource.desktop);
    expect(value.nowPlaying.source, BackgroundSource.artwork);
    expect(value.mini.source, BackgroundSource.desktop);
    expect(value.needsNativeGlass, isTrue);
    expect(BackgroundPreferences.fromMap(null), value);
    expect(BackgroundPreferences.fromMap('old-settings'), value);
    expect(AppSettings.version, '26.0.4-snapshot.3');
  });

  for (final scene in BackgroundScene.values) {
    for (final source in BackgroundSource.values) {
      test(
          '${scene.name} ${source.name} round trips without altering other scenes',
          () {
        const original = BackgroundPreferences();
        final changed = original.withScene(
            scene,
            original
                .forScene(scene)
                .copyWith(source: source, opacity: .38, blur: 82));
        expect(
            BackgroundPreferences.fromMap(
                jsonDecode(jsonEncode(changed.toMap()))),
            changed);
        for (final other in BackgroundScene.values.where((v) => v != scene)) {
          expect(changed.forScene(other), original.forScene(other));
        }
        final off = changed.withScene(scene,
            changed.forScene(scene).copyWith(source: BackgroundSource.solid));
        expect(off.forScene(scene).opacity, .38);
        expect(off.forScene(scene).blur, 82);
      });
    }
  }

  test('unknown sources and malformed values safely use defaults', () {
    const fallback = BackgroundPreferences();
    final value = BackgroundPreferences.fromMap(const {
      'main': {'source': 'unsupported', 'opacity': '0', 'blur': double.nan},
      'nowPlaying': {'source': 'artwork', 'opacity': -1, 'blur': 1000},
      'mini': {'source': 'desktop', 'opacity': double.infinity, 'blur': -10},
    });
    expect(value.main, fallback.main);
    expect(value.nowPlaying.opacity, BackgroundAppearance.minOpacity);
    expect(value.nowPlaying.blur, BackgroundAppearance.maxBlur);
    expect(value.mini.opacity, fallback.mini.opacity);
    expect(value.mini.blur, BackgroundAppearance.minBlur);
  });

  test('native policy stays enabled for any desktop scene, not scene switches',
      () {
    var value = const BackgroundPreferences();
    for (final scene in BackgroundScene.values) {
      value = value.withScene(scene,
          value.forScene(scene).copyWith(source: BackgroundSource.artwork));
    }
    expect(value.needsNativeGlass, isFalse);
    for (final scene in BackgroundScene.values) {
      expect(
          value
              .withScene(
                  scene,
                  value
                      .forScene(scene)
                      .copyWith(source: BackgroundSource.desktop))
              .needsNativeGlass,
          isTrue);
    }
  });

  group('isolated settings persistence', () {
    const windowChannel = MethodChannel('window_manager');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Directory parent;
    late Directory root;
    late File file;
    late BackgroundPreferences previous;
    late bool previousDynamicTheme;
    late FakeWindowModeAdapter window;

    setUp(() async {
      expect(
          Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
      parent = await Directory(
              path.join(Directory.current.path, 'build', 'test-data'))
          .create(recursive: true);
      root = await parent.createTemp('background-settings-');
      messenger.setMockMethodCallHandler(pathChannel, (_) async => root.path);
      window = FakeWindowModeAdapter();
      messenger.setMockMethodCallHandler(
          windowChannel, window.handleMethodCall);
      final data = await getAppDataDir();
      expect(path.isWithin(root.path, data.path), isTrue);
      file = File(path.join(data.path, 'settings.json'));
      previous = AppSettings.instance.backgrounds.value;
      previousDynamicTheme = AppSettings.instance.dynamicTheme;
    });

    tearDown(() async {
      AppSettings.instance.backgrounds.value = previous;
      AppSettings.instance.dynamicTheme = previousDynamicTheme;
      messenger.setMockMethodCallHandler(windowChannel, null);
      messenger.setMockMethodCallHandler(pathChannel, null);
      final resolvedParent = await parent.resolveSymbolicLinks();
      final resolvedRoot = await root.resolveSymbolicLinks();
      if (!path.isWithin(resolvedParent, resolvedRoot) ||
          !path.basename(resolvedRoot).startsWith('background-settings-')) {
        throw StateError('Refusing to delete an unverified fixture');
      }
      await Directory(resolvedRoot).delete(recursive: true);
    });

    test('old settings migrate only the missing background preferences',
        () async {
      await file.writeAsString(
          jsonEncode({'Version': '26.0.3', 'DynamicTheme': false}));
      await AppSettings.readFromJson();
      expect(AppSettings.instance.backgrounds.value,
          const BackgroundPreferences());
      expect(AppSettings.instance.dynamicTheme, isFalse);
      await AppSettings.instance.saveSettings();
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved['Version'], AppSettings.version);
      expect(saved['DynamicTheme'], isFalse);
      expect(saved['Backgrounds'], const BackgroundPreferences().toMap());
    });

    test('custom background choices survive a settings reload', () async {
      const custom = BackgroundPreferences(
        main: BackgroundAppearance(
            source: BackgroundSource.solid, opacity: .45, blur: 20),
        nowPlaying: BackgroundAppearance(
            source: BackgroundSource.desktop, opacity: .8, blur: 48),
        mini: BackgroundAppearance(
            source: BackgroundSource.artwork, opacity: .64, blur: 80),
      );
      AppSettings.instance.backgrounds.value = custom;
      await AppSettings.instance.saveSettings();
      AppSettings.instance.backgrounds.value = const BackgroundPreferences();
      await AppSettings.readFromJson();
      expect(AppSettings.instance.backgrounds.value, custom);
    });

    test('a delayed old save cannot overwrite a more recent background choice',
        () async {
      final started = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      var blockFirst = true;
      messenger.setMockMethodCallHandler(windowChannel, (call) async {
        if (call.method == 'getBounds' && blockFirst) {
          blockFirst = false;
          started.complete();
          await release.future;
        }
        return window.handleMethodCall(call);
      });
      AppSettings.instance.backgrounds.value = const BackgroundPreferences();
      final oldSave = AppSettings.instance.saveSettings();
      await started.future;
      final latest = const BackgroundPreferences().withScene(
          BackgroundScene.main,
          const BackgroundAppearance(
              source: BackgroundSource.artwork, opacity: .62));
      AppSettings.instance.backgrounds.value = latest;
      await AppSettings.instance.saveSettings();
      release.complete();
      await oldSave;
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved['Backgrounds'], latest.toMap());
    });
  });
}
