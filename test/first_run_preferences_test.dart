import 'dart:convert';
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/feature_onboarding.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/data/app_data_location.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixture;
  late File settings;
  late File marker;
  final originalLanguage = uiLanguage.value;
  final originalCompleted = AppSettings.instance.onboardingCompleted;
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    fixture = await parent.createTemp('first-run-');
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    final directory = await getAppDataDir();
    settings = File(path.join(directory.path, 'settings.json'));
    marker = File(path.join(directory.path, appDataReadyMarkerName));
    AppSettings.instance.onboardingCompleted = false;
  });
  tearDown(() async {
    binding.platformDispatcher.clearLocaleTestValue();
    uiLanguage.value = originalLanguage;
    AppSettings.instance.onboardingCompleted = originalCompleted;
    messenger.setMockMethodCallHandler(channel, null);
    final resolved = await fixture.resolveSymbolicLinks();
    expect(
        path.isWithin(
            path.join(Directory.current.path, 'build', 'test-data'), resolved),
        isTrue);
    expect(path.basename(resolved), startsWith('first-run-'));
    await Directory(resolved).delete(recursive: true);
  });
  test(
      'fresh profile selects system language, unsupported languages use English',
      () async {
    for (final item in [
      (const Locale('zh', 'TW'), UiLanguage.zh),
      (const Locale('en', 'GB'), UiLanguage.en),
      (const Locale('ja'), UiLanguage.ja),
      (const Locale('ko'), UiLanguage.ko),
      (const Locale('de'), UiLanguage.en)
    ]) {
      binding.platformDispatcher.localeTestValue = item.$1;
      await AppSettings.readFromJson();
      expect(uiLanguage.value, item.$2);
      expect(AppSettings.instance.onboardingCompleted, isFalse);
    }
  });
  test('saved language and legacy Chinese override system selection', () async {
    binding.platformDispatcher.localeTestValue = const Locale('ja');
    for (final language in [null, ...UiLanguage.values]) {
      await settings.writeAsString(jsonEncode({
        'Version': '26.0.5',
        if (language != null) 'UiLanguage': language.code
      }));
      await AppSettings.readFromJson();
      expect(uiLanguage.value, language ?? UiLanguage.zh);
    }
  });
  testWidgets(
      'guide persists language and only successful restoration completes it',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var completed = 0;
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            home: Scaffold(
                body: FeatureOnboarding(onComplete: () => completed++)))));
    await tester.pumpAndSettle();
    final selector = tester.widget<AppSegmentedControl<UiLanguage>>(
        find.byKey(const ValueKey('onboarding-language')));
    selector.onChanged!(UiLanguage.ko);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      // Explicitly flush the same preference without touching window geometry.
      await AppSettings.instance
          .saveSettings(captureWindowSize: false, throwOnError: true);
      expect(jsonDecode(await settings.readAsString())['UiLanguage'], 'ko');
    });
    expect(find.text(ui('欢迎使用 Dan Player')), findsOneWidget);
    expect(completed, 0);
    await tester.tap(find.byKey(const ValueKey('onboarding-restore')));
    await tester.pumpAndSettle();
    expect(completed, 0);
    tester
        .widget<CacheBackupSettings>(find.byType(CacheBackupSettings))
        .onRestorePrepared!();
    expect(completed, 1);
    await tester.tap(find.text(ui('关闭')));
    await tester.pumpAndSettle();
    expect(completed, 1);
  });
  test('only an activated restore marker skips an incomplete restored tour',
      () async {
    await settings.writeAsString(
        jsonEncode({'Version': '26.0.5', 'OnboardingCompleted': false}));
    for (final content in [
      '{}',
      'broken JSON',
      jsonEncode(
          {'format': 'dan-player-cache-backup', 'restoredAt': 'bad date'}),
      jsonEncode({
        'format': 'dan-player-cache-backup',
        'restoredAt': '2026-09-13T00:00:00Z'
      })
    ]) {
      await marker.writeAsString(content);
      await AppSettings.readFromJson();
      expect(AppSettings.instance.onboardingCompleted,
          content.contains('2026-09-13'));
    }
  });
}
