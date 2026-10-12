import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/player_guide_demo.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/playlist_feature_fixture.dart';

const _modeKey = ValueKey('guide-demo-transition-mode');
const _startKey = ValueKey('guide-demo-transition-start');
const _transitionUiKeys = [
  '试一试：歌曲过渡',
  '仅本卡片演示，不播放声音、不联网，也不修改曲库或设置。',
  '歌曲过渡',
  '常规切换',
  '连续输出',
  '交叉淡入淡出',
  '当前歌曲',
  '下一首歌曲',
  '音量交接示意；实际效果取决于歌曲与输出设备。',
  '演示歌曲过渡',
  '示意音量',
];

String _label(PlaybackTransitionMode mode) => ui(switch (mode) {
      PlaybackTransitionMode.standard => '常规切换',
      PlaybackTransitionMode.gapless => '连续输出',
      PlaybackTransitionMode.crossfade => '交叉淡入淡出',
    });

Widget _demo(ValueNotifier<bool> hidden) => Padding(
      padding: const EdgeInsets.all(16),
      child: PlayerGuideDemo(
          key: const ValueKey('transition-demo'),
          kind: PlayerGuideDemoKind.transitions,
          isHidden: hidden),
    );

Widget _host(Widget child,
    {bool reduced = false,
    bool ticker = true,
    double scale = 1,
    GlobalKey? boundary,
    MotionPreferences preferences = const MotionPreferences()}) {
  final policy = AppFontPolicy.defaults(language: uiLanguage.value);
  return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppControlTheme(ThemeData(
          platform: TargetPlatform.windows,
          useMaterial3: true,
          fontFamily: policy.uiFamily,
          fontFamilyFallback: policy.fallback)),
      builder: (context, child) => UiLanguageScope(
          child: AppFontScope(
              policy: policy,
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
                              child: child!)))))),
      home: Scaffold(body: SingleChildScrollView(child: child)));
}

AnimationController _clock(WidgetTester tester) => tester
    .widget<AnimatedBuilder>(find
        .ancestor(
            of: find.byKey(const ValueKey('guide-demo-transition-current')),
            matching: find.byType(AnimatedBuilder))
        .first)
    .animation as AnimationController;

({double current, double next}) _gains(WidgetTester tester) => (
      current: tester
          .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('guide-demo-transition-current')))
          .value!,
      next: tester
          .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('guide-demo-transition-next')))
          .value!,
    );

void _expectRenderedLabels(WidgetTester tester) {
  final demo = find.byType(PlayerGuideDemo);
  for (final key in [
    '试一试：歌曲过渡',
    '仅本卡片演示，不播放声音、不联网，也不修改曲库或设置。',
    '当前歌曲',
    '下一首歌曲',
    '音量交接示意；实际效果取决于歌曲与输出设备。',
    '演示歌曲过渡',
  ]) {
    final text = find.descendant(of: demo, matching: find.text(ui(key)));
    expect(text, findsOneWidget, reason: '${uiLanguage.value.code}: $key');
    expect(tester.getSize(text).isEmpty, isFalse);
  }
  final control = tester.widget<AppSegmentedControl<PlaybackTransitionMode>>(
      find.byKey(_modeKey));
  expect(control.semanticLabel, ui('歌曲过渡'));
  for (final (id, title) in [
    ('current', '当前歌曲'),
    ('next', '下一首歌曲'),
  ]) {
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byKey(ValueKey('guide-demo-transition-$id')))
            .semanticsLabel,
        '${ui(title)} · ${ui('示意音量')}');
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final output = Platform.environment['DAN_GUIDE_TRANSITION_RENDER_DIR'];
  if (output == null || output.isEmpty) return;
  final workspace = Platform.environment['DAN_PLAYER_WORKSPACE'] ??
      Directory.current.parent.path;
  final allowed = path
      .normalize(path.join(workspace, 'tool', 'qa-local', 'global-opt-oct12'));
  final target = path.normalize(path.absolute(output));
  expect(path.equals(allowed, target) || path.isWithin(allowed, target), isTrue,
      reason: 'Guide render artifacts must stay in the task QA directory');
  await tester.runAsync(() async {
    await Directory(target).create(recursive: true);
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(path.join(target, '$name.png')).writeAsBytes(
          bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    } finally {
      image.dispose();
    }
  });
}

Future<void> _choose(WidgetTester tester, PlaybackTransitionMode mode,
    {GlobalKey? boundary, String? captureName}) async {
  final control = find.byKey(_modeKey);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  final segments = find.descendant(
      of: control,
      matching: find.byType(SegmentedButton<PlaybackTransitionMode>));
  if (segments.evaluate().isNotEmpty) {
    await tester
        .tap(find.descendant(of: segments, matching: find.text(_label(mode))));
  } else {
    await tester.tap(
        find.descendant(of: control, matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    final item = find.widgetWithText(MenuItemButton, _label(mode));
    expect(item, findsOneWidget);
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    expect(item.hitTestable(), findsOneWidget);
    if (boundary != null && captureName != null) {
      await _capture(tester, boundary, '$captureName-menu');
    }
    await tester.tap(item);
  }
  await tester.pumpAndSettle();
  expect(
      tester.widget<AppSegmentedControl<PlaybackTransitionMode>>(control).value,
      mode);
}

Future<void> _start(WidgetTester tester) async {
  final button = find.byKey(_startKey);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadPlaylistFeatureFonts();
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
  });
  setUp(() {
    expect(PlayService.isInitialized, isFalse);
  });

  test('every transition demo UI label has a direct four-language translation',
      () {
    for (final key in _transitionUiKeys) {
      for (final language in UiLanguage.values) {
        final translated = translateUi(key, language);
        expect(translated.trim(), isNotEmpty);
        if (language != UiLanguage.zh) {
          expect(translated, isNot(key), reason: '${language.code}: $key');
        }
      }
    }
  });

  for (final mode in PlaybackTransitionMode.values) {
    testWidgets('transition demo shows the actual ${mode.name} handoff',
        (tester) async {
      sizePlaylistFeature(tester, width: 720, height: 720);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      await tester.pumpWidget(_host(_demo(hidden)));
      await tester.pumpAndSettle();
      await _choose(tester, mode);
      expect(_gains(tester), (current: 1.0, next: 0.0));
      expect(_clock(tester).isAnimating, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      await _start(tester);
      expect(_clock(tester).isAnimating, isTrue);
      final samples = <({double current, double next})>[_gains(tester)];
      for (var frame = 0; frame < 130; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        samples.add(_gains(tester));
      }
      for (var index = 0; index < samples.length; index++) {
        final sample = samples[index];
        expect(sample.current, inInclusiveRange(0, 1));
        expect(sample.next, inInclusiveRange(0, 1));
        if (index > 0) {
          expect(sample.current, lessThanOrEqualTo(samples[index - 1].current));
          expect(sample.next, greaterThanOrEqualTo(samples[index - 1].next));
        }
      }
      final silentFrames = samples
          .where((sample) => sample.current == 0 && sample.next == 0)
          .length;
      final overlap =
          samples.any((sample) => sample.current > 0 && sample.next > 0);
      switch (mode) {
        case PlaybackTransitionMode.standard:
          expect(silentFrames, greaterThan(0));
          expect(silentFrames, lessThan(samples.length ~/ 2),
              reason:
                  'The standard handoff has a short gap, not a silent demo');
          expect(overlap, isFalse);
        case PlaybackTransitionMode.gapless:
          expect(silentFrames, 0);
          expect(overlap, isFalse);
        case PlaybackTransitionMode.crossfade:
          expect(silentFrames, 0);
          expect(overlap, isTrue);
      }
      expect(_gains(tester), (current: 0.0, next: 1.0));
      expect(_clock(tester).isAnimating, isFalse);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('selecting a different mode stops the active transition clock',
      (tester) async {
    sizePlaylistFeature(tester, width: 720, height: 720);
    final hidden = ValueNotifier(false);
    addTearDown(hidden.dispose);
    await tester.pumpWidget(_host(_demo(hidden)));
    await tester.pumpAndSettle();
    await _start(tester);
    await tester.pump(const Duration(milliseconds: 120));
    expect(_clock(tester).isAnimating, isTrue);
    // Do not settle the old clock before clicking the new mode.
    final control = find.byKey(_modeKey);
    await tester.tap(find.descendant(
        of: control,
        matching: find.text(_label(PlaybackTransitionMode.standard))));
    await tester.pump();
    expect(_clock(tester).isAnimating, isFalse);
    expect(_gains(tester), (current: 1.0, next: 0.0));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(_gains(tester), (current: 1.0, next: 0.0));
    expect(tester.binding.transientCallbackCount, 0);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final gate in [
    'hidden',
    'ticker',
    'media',
    'category',
    'nativeReduce',
    'nativeDisable',
    'paused',
  ]) {
    testWidgets('transition demo settles and stays idle for $gate',
        (tester) async {
      sizePlaylistFeature(tester, width: 720, height: 720);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      addTearDown(() => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final child = _demo(hidden);
      await tester.pumpWidget(_host(child));
      await tester.pumpAndSettle();
      await _start(tester);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_clock(tester).isAnimating, isTrue);
      switch (gate) {
        case 'hidden':
          hidden.value = true;
        case 'ticker':
          await tester.pumpWidget(_host(child, ticker: false));
        case 'media':
          await tester.pumpWidget(_host(child, reduced: true));
        case 'category':
          await tester.pumpWidget(_host(child,
              preferences:
                  const MotionPreferences(disabled: {MotionKind.layout})));
        case 'nativeReduce':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(reduceMotion: true);
        case 'nativeDisable':
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
        case 'paused':
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pump();
      expect(_clock(tester).isAnimating, isFalse);
      expect(_gains(tester), (current: 0.0, next: 1.0));
      hidden.value = false;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(_host(child));
      await tester.pumpAndSettle();
      expect(_clock(tester).isAnimating, isFalse);
      expect(_gains(tester), (current: 0.0, next: 1.0));
      expect(tester.binding.transientCallbackCount, 0);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.code} transition menu stays usable at 320px large text',
        (tester) async {
      sizePlaylistFeature(tester, width: 320, height: 1000);
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
          _host(_demo(hidden), reduced: true, scale: 1.8, boundary: boundary));
      await tester.pumpAndSettle();
      _expectRenderedLabels(tester);
      for (final mode in PlaybackTransitionMode.values) {
        final translated = _label(mode);
        if (language != UiLanguage.zh) {
          expect(
              translated,
              isNot(switch (mode) {
                PlaybackTransitionMode.standard => '常规切换',
                PlaybackTransitionMode.gapless => '连续输出',
                PlaybackTransitionMode.crossfade => '交叉淡入淡出',
              }));
        }
        await _choose(tester, mode,
            boundary: boundary, captureName: '${language.code}-${mode.name}');
        _expectRenderedLabels(tester);
        final rect = tester.getRect(find.byKey(_modeKey));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        await _capture(
            tester, boundary, '${language.code}-${mode.name}-selected');
        await _start(tester);
        expect(_clock(tester).isAnimating, isFalse);
        expect(_gains(tester), (current: 0.0, next: 1.0));
        final button = tester.getRect(find.byKey(_startKey));
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      expect(PlayService.isInitialized, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('${language.code} transition demo renders wide finite handoffs',
        (tester) async {
      sizePlaylistFeature(tester, width: 800, height: 600);
      final previous = uiLanguage.value;
      addTearDown(() => uiLanguage.value = previous);
      uiLanguage.value = language;
      final hidden = ValueNotifier(false);
      addTearDown(hidden.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(_host(_demo(hidden), boundary: boundary));
      await tester.pumpAndSettle();
      for (final mode in PlaybackTransitionMode.values) {
        await _choose(tester, mode);
        _expectRenderedLabels(tester);
        expect(
            find.descendant(
                of: find.byKey(_modeKey),
                matching: find.byType(SegmentedButton<PlaybackTransitionMode>)),
            findsOneWidget);
        expect(_gains(tester), (current: 1.0, next: 0.0));
        await _capture(
            tester, boundary, '${language.code}-wide-${mode.name}-static');
        await _start(tester);
        var reachedHandoff = false;
        for (var frame = 0; frame < 120; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          final gain = _gains(tester);
          reachedHandoff = switch (mode) {
            PlaybackTransitionMode.standard =>
              gain.current == 0 && gain.next == 0,
            PlaybackTransitionMode.gapless =>
              gain.current == 0 && gain.next == 1,
            PlaybackTransitionMode.crossfade =>
              gain.current >= .25 && gain.next >= .25,
          };
          if (reachedHandoff) break;
        }
        expect(reachedHandoff, isTrue);
        expect(_clock(tester).isAnimating, isTrue);
        _expectRenderedLabels(tester);
        await _capture(
            tester, boundary, '${language.code}-wide-${mode.name}-active');
        await tester.pumpAndSettle();
        expect(_gains(tester), (current: 0.0, next: 1.0));
        expect(_clock(tester).isAnimating, isFalse);
        expect(tester.binding.transientCallbackCount, 0);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
