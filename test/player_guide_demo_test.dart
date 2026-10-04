import 'dart:io';

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

Widget _host(Widget child,
        {bool reduced = false,
        bool ticker = true,
        MotionPreferences preferences = const MotionPreferences(),
        GlobalKey? boundary,
        double scale = 1,
        bool dark = false}) =>
    MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: applyAppControlTheme(ThemeData(
            platform: TargetPlatform.windows,
            useMaterial3: true,
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: danFontFamilyFallback,
            colorScheme: ColorScheme.fromSeed(
                seedColor: dark ? Colors.deepOrange : Colors.teal,
                brightness: dark ? Brightness.dark : Brightness.light))),
        builder: (context, child) => UiLanguageScope(
            child: MotionPreferencesScope(
                preferences: preferences,
                child: TickerMode(
                    enabled: ticker,
                    child: RepaintBoundary(
                        key: boundary,
                        child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                                disableAnimations: reduced,
                                textScaler: TextScaler.linear(scale)),
                            child: child!))))),
        home: Scaffold(body: child));

Widget _demo(PlayerGuideDemoKind kind, ValueNotifier<bool> hidden) => Padding(
    padding: const EdgeInsets.all(16),
    child: PlayerGuideDemo(kind: kind, isHidden: hidden));

AnimationController _clock(WidgetTester tester, {PlayerGuideDemoKind? kind}) =>
    tester
        .widget<AnimatedBuilder>(find
            .descendant(
                of: kind == null
                    ? find.byType(PlayerGuideDemo)
                    : find.byWidgetPredicate((widget) =>
                        widget is PlayerGuideDemo && widget.kind == kind),
                matching: find.byType(AnimatedBuilder))
            .first)
        .animation as AnimationController;

Finder _header(String id) => find
    .descendant(
        of: find.byKey(ValueKey('guide-section-$id')),
        matching: find.byType(ListTile))
    .first;

Future<void> _toggle(WidgetTester tester, String id) async {
  await tester.ensureVisible(_header(id));
  await tester.pumpAndSettle();
  await tester.tap(_header(id));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final output = Platform.environment['DAN_PLAYLIST_FEATURE_RENDER_DIR'];
    if (output == null) return;
    final allowed = path.normalize(path.join(Directory.current.parent.path,
        'tool', 'qa-local', 'preflight-final-2606-oct4', 'manual'));
    expect(
        path.isWithin(allowed, path.normalize(path.absolute(output))), isTrue);
  });

  test('common workflows and demo UI have complete translations', () {
    for (final file in [
      'lib/component/player_feature_guide.dart',
      'lib/component/player_guide_demo.dart'
    ]) {
      final source = File(file).readAsStringSync();
      final keys = RegExp(r"'((?:\\.|[^'\\])*)'")
          .allMatches(source)
          .map((match) => match.group(1)!.replaceAll(r'\n', '\n'))
          .where((text) => RegExp(r'[\u4e00-\u9fff]').hasMatch(text))
          .toSet();
      for (final key in keys) {
        for (final language in UiLanguage.values) {
          final translated = translateUi(key, language);
          expect(translated.trim(), isNotEmpty);
          if (language != UiLanguage.zh) {
            expect(translated, isNot(key), reason: '${language.name}: $key');
          }
        }
      }
    }
    for (final language in UiLanguage.values) {
      expect(translateUi('演示歌词：{0}', language, ['Sample']), contains('Sample'));
    }
  });

  testWidgets('progress accepts taps, dragging and keyboard without playback',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 600);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(PlayerGuideDemoKind.progress, hidden)));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('guide-demo-progress-slider'));
    final before = tester.widget<Slider>(slider).value;
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * .8, rect.center.dy));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, greaterThan(before));
    await tester.drag(slider, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final dragged = tester.widget<Slider>(slider).value;
    expect(dragged, lessThan(.8));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, greaterThan(dragged));
    await tester.tap(find.byKey(const ValueKey('guide-demo-seek-forward')));
    await tester.pump(const Duration(milliseconds: 30));
    expect(_clock(tester).isAnimating, isTrue);
    await tester.pumpAndSettle();
    expect(_clock(tester).isAnimating, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'word emphasis and rising lines finish and keep one semantic line',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 600);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host(_demo(PlayerGuideDemoKind.lyrics, hidden)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(_clock(tester).isAnimating, isTrue);
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('guide-demo-lyric-line-0')));
      final colors = (text.textSpan! as TextSpan)
          .children!
          .cast<TextSpan>()
          .map((word) => word.style!.color)
          .toSet();
      expect(colors.length, greaterThan(1));
      await tester.pumpAndSettle();
      expect(_clock(tester).isAnimating, isFalse);
      await tester.tap(find.byKey(const ValueKey('guide-demo-next-line')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_clock(tester).isAnimating, isTrue);
      final current = ui('下一句|轻轻|向上浮起').split('|').join(' ');
      expect(find.bySemanticsLabel(ui('演示歌词：{0}', [current])), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-demo-lyric-line-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('guide-demo-lyric-line-1')),
          findsOneWidget);
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('guide-demo-lyric-line-0')), findsNothing);
      expect(_clock(tester).isAnimating, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'native hidden, motion gates and lifecycle settle without resuming',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 600);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    for (final gate in [
      'hidden',
      'category',
      'media',
      'ticker',
      'native',
      'pause'
    ]) {
      final hidden = ValueNotifier(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      final child = _demo(PlayerGuideDemoKind.lyrics, hidden);
      await tester.pumpWidget(_host(child));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_clock(tester).isAnimating, isTrue, reason: gate);
      switch (gate) {
        case 'hidden':
          hidden.value = true;
        case 'category':
          await tester.pumpWidget(_host(child,
              preferences:
                  const MotionPreferences(disabled: {MotionKind.lyrics})));
        case 'media':
          await tester.pumpWidget(_host(child, reduced: true));
        case 'ticker':
          await tester.pumpWidget(_host(child, ticker: false));
        case 'native':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'pause':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      expect(_clock(tester).isAnimating, isFalse, reason: gate);
      expect(_clock(tester).value, 1, reason: gate);
      hidden.value = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pumpWidget(_host(child));
      await tester.pumpAndSettle();
      expect(_clock(tester).isAnimating, isFalse, reason: gate);
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      hidden.dispose();
    }
  });

  testWidgets('scrolling outside the viewport and disposal stop a demo clock',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 420);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_host(SingleChildScrollView(
        controller: scroll,
        child: Column(children: [
          _demo(PlayerGuideDemoKind.lyrics, hidden),
          const SizedBox(height: 1400),
        ]))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_clock(tester).isAnimating, isTrue);
    scroll.jumpTo(700);
    await tester.pump();
    expect(_clock(tester).isAnimating, isFalse);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_clock(tester).isAnimating, isFalse);
    await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    hidden.value = true;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('common page links and closing a guide topic keep demos local',
      (tester) async {
    sizePlaylistFeature(tester, width: 1080, height: 900);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    uiLanguage.value = UiLanguage.zh;
    final destinations = <String>[];
    final boundary = GlobalKey();
    await tester.pumpWidget(_host(
        PlayerFeatureGuideDialog(
            onNavigate: destinations.add, demoIsHidden: hidden),
        boundary: boundary));
    for (final link in [
      ('guide-basic-music-page', '/audios'),
      ('guide-basic-category-page', '/categories'),
    ]) {
      final target = find.byKey(ValueKey(link.$1));
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      expect(destinations.last, link.$2);
    }
    await _toggle(tester, 'getting-started');
    await _toggle(tester, 'playlists');
    await _toggle(tester, 'queue');
    final demo = find.byKey(const ValueKey('guide-demo-progress'));
    await tester.ensureVisible(demo);
    await tester.pumpAndSettle();
    await capturePlaylistFeature(
        tester, boundary, 'manual-common-playback-wide');
    await _toggle(tester, 'queue');
    await _toggle(tester, 'lyrics');
    await tester
        .ensureVisible(find.byKey(const ValueKey('guide-demo-highlight')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
    await tester.pump(const Duration(milliseconds: 20));
    expect(_clock(tester).isAnimating, isTrue);
    await tester.ensureVisible(_header('lyrics'));
    await tester.pump();
    await tester.tap(_header('lyrics'));
    await tester.pump();
    expect(_clock(tester).isAnimating, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerGuideDemo), findsNothing);
    await _toggle(tester, 'search');
    final search = find.byKey(const ValueKey('guide-basic-search-page'));
    await tester.ensureVisible(search);
    await tester.pumpAndSettle();
    await tester.tap(search);
    expect(destinations.last, '/search');
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('everyday library instructions render in a wide and narrow guide',
      (tester) async {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    final boundary = GlobalKey();
    sizePlaylistFeature(tester, width: 1080, height: 900);
    uiLanguage.value = UiLanguage.zh;
    await tester.pumpWidget(_host(
        PlayerFeatureGuideDialog(demoIsHidden: hidden),
        boundary: boundary));
    final music = find.text(ui('音乐页：浏览、排序与点歌'));
    await tester.ensureVisible(music);
    await tester.pumpAndSettle();
    await capturePlaylistFeature(
        tester, boundary, 'manual-common-library-wide');
    expect(find.text(ui('分类页：从专辑与艺术家开始')), findsOneWidget);
    sizePlaylistFeature(tester, width: 360, height: 1200);
    uiLanguage.value = UiLanguage.en;
    await tester.pumpWidget(_host(
        PlayerFeatureGuideDialog(demoIsHidden: hidden),
        boundary: boundary,
        scale: 1.5,
        dark: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(ui('分类页：从专辑与艺术家开始')));
    await tester.pumpAndSettle();
    final link = find.byKey(const ValueKey('guide-basic-category-page'));
    final rect = tester.getRect(link);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    await capturePlaylistFeature(
        tester, boundary, 'manual-common-library-en-narrow');
    expect(tester.takeException(), isNull);
    expect(PlayService.isInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in UiLanguage.values) {
    testWidgets('interactive guide ${language.name} narrow enlarged rendering',
        (tester) async {
      sizePlaylistFeature(tester, width: 360, height: 1200);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(
          SingleChildScrollView(
              child: Column(children: [
            _demo(PlayerGuideDemoKind.progress, hidden),
            _demo(PlayerGuideDemoKind.lyrics, hidden),
          ])),
          boundary: boundary,
          scale: 1.5,
          dark: true));
      await tester.pumpAndSettle();
      for (final button in [
        'guide-demo-seek-back',
        'guide-demo-seek-forward',
        'guide-demo-highlight',
        'guide-demo-next-line'
      ]) {
        final target = find.byKey(ValueKey(button));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expect(target.hitTestable(), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('guide-demo-highlight')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(_clock(tester, kind: PlayerGuideDemoKind.lyrics).value,
          inExclusiveRange(0, 1));
      await capturePlaylistFeature(
          tester, boundary, 'manual-demo-${language.name}-words-narrow');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('guide-demo-next-line')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(_clock(tester, kind: PlayerGuideDemoKind.lyrics).value,
          inExclusiveRange(0, 1));
      await capturePlaylistFeature(
          tester, boundary, 'manual-demo-${language.name}-rising-narrow');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(PlayService.isInitialized, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
