import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/build_index_state_view.dart';
import 'package:dan_player/component/feature_onboarding.dart';
import 'package:dan_player/component/onboarding_guide_prompt.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/page/welcoming_page.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/l10n/catalog_onboarding_guide_prompt.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

Widget _host(Widget page,
        {GlobalKey? boundary,
        GlobalKey<NavigatorState>? navigator,
        double scale = 1}) =>
    UiLanguageScope(
        child: MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: applyAppControlTheme(ThemeData(
                platform: TargetPlatform.windows,
                useMaterial3: true,
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: danFontFamilyFallback,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: scale == 1 ? Colors.teal : Colors.deepOrange,
                    brightness:
                        scale == 1 ? Brightness.light : Brightness.dark))),
            builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        disableAnimations: true,
                        textScaler: TextScaler.linear(scale)),
                    child: child!)),
            home: page));

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final originalCompleted = AppSettings.instance.onboardingCompleted;
  final originalLanguage = uiLanguage.value;
  late Directory fixture;
  late File settings;
  Completer<String>? delayedPath;
  final qa = path.normalize(path.join(Directory.current.parent.path, 'tool',
      'qa-local', 'resource-guide-edit-2606-oct4', 'onboarding'));

  setUpAll(loadPlaylistFeatureFonts);
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    fixture = await Directory(path.join(qa, 'data'))
        .create(recursive: true)
        .then((parent) => parent.createTemp('guide-first-use-'));
    delayedPath = null;
    messenger.setMockMethodCallHandler(
        pathChannel, (_) async => delayedPath?.future ?? fixture.path);
    final data = await getAppDataDir();
    settings = File(path.join(data.path, 'settings.json'));
    AppSettings.instance.onboardingCompleted = false;
    uiLanguage.value = UiLanguage.zh;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(pathChannel, null);
    AppSettings.instance.onboardingCompleted = originalCompleted;
    uiLanguage.value = originalLanguage;
  });

  // getAppDataDir resolves mocked paths and performs real directory I/O on
  // every FLUTTER_TEST request. Wait in the real loop, never advance fake time
  // while assuming that those operations have completed.
  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    final watch = Stopwatch()..start();
    while (!ready() && watch.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(ready(), isTrue, reason: 'Expected isolated I/O/UI completion');
  }

  Future<void> prompt(WidgetTester tester) async {
    await waitFor(
        tester, () => find.byType(OnboardingGuidePrompt).evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    expect(settings.existsSync(), isTrue);
    expect(
        jsonDecode(settings.readAsStringSync())['OnboardingCompleted'], isTrue);
    expect(PlayService.isInitialized, isFalse);
    expect(find.byType(BuildIndexStateView), findsNothing);
    expect(find.byType(OnboardingGuidePrompt), findsOneWidget);
  }

  Future<void> skip(WidgetTester tester) async {
    await tester.tap(find.text(ui('跳过引导')));
    await prompt(tester);
  }

  for (final complete in [true, false]) {
    testWidgets(
        'first ${complete ? 'completion' : 'skip'} offers guide once and keeps import usable',
        (tester) async {
      sizePlaylistFeature(tester);
      await tester.pumpWidget(_host(const WelcomingPage()));
      if (complete) {
        for (var step = 0; step < 3; step++) {
          await tester.tap(find.byKey(const ValueKey('onboarding-next')));
          await tester.pump();
        }
        await prompt(tester);
      } else {
        await skip(tester);
      }
      await tester.tap(find.byKey(const ValueKey('onboarding-guide-later')));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingGuidePrompt), findsNothing);
      expect(find.byType(FolderSelectorView), findsOneWidget);
      expect(find.text(ui('添加文件夹')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_host(const WelcomingPage()));
      await tester.pumpAndSettle();
      expect(find.byType(FeatureOnboarding), findsNothing);
      expect(find.byType(OnboardingGuidePrompt), findsNothing);
      expect(find.byType(FolderSelectorView), findsOneWidget);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('open guide returns to import without playback or scanning',
      (tester) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(_host(const WelcomingPage()));
    await skip(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-guide-open')));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingGuidePrompt), findsNothing);
    expect(find.byType(PlayerFeatureGuideDialog), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
    expect(find.byType(BuildIndexStateView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('close-player-feature-guide')));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
    expect(find.text(ui('添加文件夹')), findsOneWidget);
    expect(AppSettings.instance.onboardingCompleted, isTrue);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('already completed welcome never offers the first-use guide',
      (tester) async {
    sizePlaylistFeature(tester);
    AppSettings.instance.onboardingCompleted = true;
    await tester.pumpWidget(_host(const WelcomingPage()));
    await tester.pumpAndSettle();
    expect(find.byType(FeatureOnboarding), findsNothing);
    expect(find.byType(OnboardingGuidePrompt), findsNothing);
    expect(find.byType(FolderSelectorView), findsOneWidget);
    expect(settings.existsSync(), isFalse);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful restore uses its own completion without guide',
      (tester) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(_host(const WelcomingPage()));
    await tester.tap(find.byKey(const ValueKey('onboarding-restore')));
    await tester.pumpAndSettle();
    final restore =
        tester.widget<CacheBackupSettings>(find.byType(CacheBackupSettings));
    expect(restore.restoreOnly, isTrue);
    // Exercise the prepared-restore callback from the real restore dialog;
    // archive restoration itself remains covered by the existing backup suite.
    AppSettings.instance.onboardingCompleted = true;
    restore.onRestorePrepared!();
    await waitFor(tester, settings.existsSync);
    await tester.tap(find.text(ui('关闭')));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingGuidePrompt), findsNothing);
    expect(find.byType(FolderSelectorView), findsOneWidget);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'optional restore callback retains standalone completion contract',
      (tester) async {
    sizePlaylistFeature(tester);
    var completed = 0;
    await tester.pumpWidget(_host(
        Scaffold(body: FeatureOnboarding(onComplete: () => completed++))));
    await tester.tap(find.byKey(const ValueKey('onboarding-restore')));
    await tester.pumpAndSettle();
    tester
        .widget<CacheBackupSettings>(find.byType(CacheBackupSettings))
        .onRestorePrepared!();
    expect(completed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('duplicate completion callbacks cannot enqueue a second prompt',
      (tester) async {
    sizePlaylistFeature(tester);
    await tester.pumpWidget(_host(const WelcomingPage()));
    final complete = tester
        .widget<FeatureOnboarding>(find.byType(FeatureOnboarding))
        .onComplete;
    complete();
    complete();
    await prompt(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-guide-later')));
    await tester.pumpAndSettle();
    complete();
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingGuidePrompt), findsNothing);
    expect(find.byType(FolderSelectorView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dispose in [true, false]) {
    testWidgets(
        'late save cannot open guide after welcome ${dispose ? 'disposal' : 'is covered by another route'}',
        (tester) async {
      sizePlaylistFeature(tester);
      final navigator = GlobalKey<NavigatorState>();
      await tester
          .pumpWidget(_host(const WelcomingPage(), navigator: navigator));
      delayedPath = Completer<String>();
      final complete = tester
          .widget<FeatureOnboarding>(find.byType(FeatureOnboarding))
          .onComplete;
      complete();
      if (dispose) {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        navigator.currentState!.push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another route'))));
        await tester.pumpAndSettle();
      }
      delayedPath!.complete(fixture.path);
      await waitFor(tester, settings.existsSync);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingGuidePrompt), findsNothing);
      if (!dispose) {
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingGuidePrompt), findsNothing);
        expect(find.byType(FolderSelectorView), findsOneWidget);
      }
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  test('first-use guide catalog translates every message in four languages',
      () {
    for (final entry in catalogOnboardingGuidePrompt.entries) {
      expect(entry.value, hasLength(3));
      for (final language in UiLanguage.values) {
        final translated = translateUi(entry.key, language);
        expect(translated, isNotEmpty);
        if (language != UiLanguage.zh) expect(translated, isNot(entry.key));
      }
    }
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          'guide prompt ${language.code} ${narrow ? 'narrow-large' : 'wide'} real fonts',
          (tester) async {
        sizePlaylistFeature(tester,
            width: narrow ? 360 : 1080, height: narrow ? 900 : 760);
        uiLanguage.value = language;
        final boundary = GlobalKey();
        await tester.pumpWidget(_host(const WelcomingPage(),
            boundary: boundary, scale: narrow ? 2 : 1));
        await skip(tester);
        final dialog = tester.getRect(find.byType(AlertDialog));
        expect(dialog.left, greaterThanOrEqualTo(0));
        expect(dialog.right, lessThanOrEqualTo(narrow ? 360 : 1080));
        for (final action in ['later', 'open']) {
          final button = find.byKey(ValueKey('onboarding-guide-$action'));
          await tester.ensureVisible(button);
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(dialog.left));
          expect(rect.right, lessThanOrEqualTo(dialog.right));
          expect(rect.bottom, lessThanOrEqualTo(900));
        }
        expect(tester.takeException(), isNull);
        await capturePlaylistFeature(tester, boundary,
            'onboarding-guide-${language.code}-${narrow ? 'narrow-large' : 'wide'}');
        await tester.tap(find.byKey(const ValueKey('onboarding-guide-later')));
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingGuidePrompt), findsNothing);
        expect(PlayService.isInitialized, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
