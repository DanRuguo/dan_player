import 'dart:convert';
import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/page/settings_page/page.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/page/settings_page/playback_transition_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

final _qaRoot = path.join(Directory.current.parent.path, 'tool', 'qa-local',
    'selection-folders-oct11', 'playback-linkage');
const _sliderKey = ValueKey('playback-crossfade-seconds');
const _modeKey = ValueKey('playback-transition-mode');
const _description = '下次加载歌曲生效。连续输出预先准备当前队列的下一首本地歌曲；手动切歌、定位、A–B 循环和停止目标沿用原行为。';
const _fallbackDescription =
    '仅共享输出混合两曲；独占输出使用连续接续。短曲自动缩短过渡，在线音频、CUE 分轨或未能预备的歌曲使用常规切换。';
const _guideDescription =
    '在“曲库与播放 → 歌曲过渡”选择常规切换、连续输出或交叉淡入淡出，下次加载歌曲生效。连续输出预备已有的下一首本地歌曲；淡入淡出仅在共享输出混合两曲。暂停、定位、循环与停止目标优先，未能预备时沿用常规切换。';

late Directory _fixture;
File get _settingsFile => File(path.join(
    _fixture.path, AppSettings.appDataDirectoryName, 'settings.json'));

Widget _frame(BuildContext context, Widget child,
    {required UiLanguage language, double scale = 1}) {
  final policy = AppFontPolicy.defaults(language: language);
  return UiLanguageScope(
      child: AppFontScope(
          policy: policy,
          child: RenderingPreferencesScope(
              preferences: AppSettings.instance.rendering,
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      disableAnimations: true,
                      textScaler: TextScaler.linear(scale)),
                  child: child))));
}

ThemeData _theme(UiLanguage language) {
  final policy = AppFontPolicy.defaults(language: language);
  return applyAppControlTheme(ThemeData(
      platform: TargetPlatform.windows,
      useMaterial3: true,
      fontFamily: policy.uiFamily,
      fontFamilyFallback: policy.fallback,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)));
}

Future<void> _mount(WidgetTester tester, Widget child,
    {UiLanguage language = UiLanguage.zh,
    double width = 1000,
    double scale = 1,
    GlobalKey? boundary}) async {
  uiLanguage.value = language;
  tester.view.physicalSize = Size(width, 850);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(language),
      builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: _frame(context, child!, language: language, scale: scale)),
      home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> _drainSaves(WidgetTester tester) async {
  // The real settings writer performs filesystem work. Alternate real IO time
  // and fake-async microtask draining rather than awaiting IO in a fake zone.
  for (var i = 0; i < 16; i++) {
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
  await tester.pumpAndSettle();
}

Future<Map<String, dynamic>> _saved(
    WidgetTester tester, PlaybackTransitionMode mode) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump();
    if (_settingsFile.existsSync()) {
      final value =
          jsonDecode(_settingsFile.readAsStringSync()) as Map<String, dynamic>;
      if ((value['PlaybackTransitions'] as Map)['mode'] == mode.name) {
        return value;
      }
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
  fail('The real settings writer did not commit ${mode.name} in isolated QA.');
}

void _completeText(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  expect(paragraph.didExceedMaxLines, isFalse);
  final content = text.data!;
  final tail = paragraph.getBoxesForSelection(TextSelection(
      baseOffset: content.length - 1, extentOffset: content.length));
  expect(tail, isNotEmpty,
      reason: 'The final translated glyph must be laid out.');
  for (final box in tail) {
    expect(box.left, greaterThanOrEqualTo(-1));
    expect(box.right, lessThanOrEqualTo(paragraph.size.width + 1));
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final requested = Platform.environment['DAN_TRANSITION_LINKAGE_RENDER_DIR'];
  if (requested == null) return;
  final output = path.normalize(path.absolute(requested));
  expect(output == _qaRoot || path.isWithin(_qaRoot, output), isTrue,
      reason: 'Linkage screenshots must remain in their QA directory.');
  await tester.runAsync(() async {
    await Directory(output).create(recursive: true);
    final picture = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final png = await picture.toByteData(format: raster.ImageByteFormat.png);
      await File(path.join(output, '$name.png'))
          .writeAsBytes(png!.buffer.asUint8List());
    } finally {
      picture.dispose();
    }
  });
}

Future<void> _selectMode(
    WidgetTester tester, PlaybackTransitionMode mode) async {
  final label = switch (mode) {
    PlaybackTransitionMode.standard => ui('常规切换'),
    PlaybackTransitionMode.gapless => ui('连续输出'),
    PlaybackTransitionMode.crossfade => ui('交叉淡入淡出'),
  };
  final selector = find.byKey(_modeKey);
  await tester.ensureVisible(selector);
  await tester.pumpAndSettle();
  final button =
      find.descendant(of: selector, matching: find.byType(OutlinedButton));
  if (button.evaluate().isNotEmpty) {
    await tester.tap(button, pointer: 2);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label), pointer: 2);
  } else {
    await tester.tap(find.descendant(of: selector, matching: find.text(label)),
        pointer: 2);
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late PlaybackTransitionPreferences previousTransitions;
  late PlayerExperiencePreferences previousExperience;
  late RenderingPreferences previousRendering;
  late UiLanguage previousLanguage;
  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    for (final font in [
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  setUp(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty,
        reason: 'This explicit path_provider fixture must not be bypassed.');
    final root = await Directory(_qaRoot).create(recursive: true);
    _fixture = await root.createTemp('settings-');
    messenger.setMockMethodCallHandler(pathChannel, (_) async => _fixture.path);
    final settings = AppSettings.instance;
    previousTransitions = settings.playbackTransitions.value;
    previousExperience = settings.experience.value;
    previousRendering = settings.rendering.value;
    previousLanguage = uiLanguage.value;
    settings.playbackTransitions.value = const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade);
    settings.rendering.value = const RenderingPreferences()
        .copyWith(animations: const MotionPreferences().all(false));
    expect(PlayService.isInitialized, isFalse);
  });
  tearDown(() async {
    final settings = AppSettings.instance;
    settings.playbackTransitions.value = previousTransitions;
    settings.experience.value = previousExperience;
    settings.rendering.value = previousRendering;
    uiLanguage.value = previousLanguage;
    messenger.setMockMethodCallHandler(pathChannel, null);
    if (_fixture.existsSync()) await _fixture.delete(recursive: true);
  });

  testWidgets(
      'transition search reaches the real settings surface in four languages',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final missed = <String>[];
    for (final language in UiLanguage.values) {
      for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
        final query = translateUi('连续输出', language);
        final destination = searchSettings(query).single;
        final uri = Uri.parse(destination.location);
        expect(uri.queryParameters['section'], 'library');
        final boundary = GlobalKey();
        await _mount(
            tester,
            SettingsPage(
                initialSection: uri.queryParameters['section'],
                initialSetting: uri.queryParameters['setting']),
            language: language,
            width: size.$1,
            scale: size.$2,
            boundary: boundary);
        final selector = find.byKey(_modeKey);
        final playback = find.byKey(const ValueKey('setting-playback'));
        final position = tester
            .state<ScrollableState>(
                find.ancestor(of: selector, matching: find.byType(Scrollable)))
            .position;
        final reached = selector.hitTestable().evaluate().isNotEmpty;
        final description = '${language.code} ${size.$1} ${size.$2}';
        debugPrint('TRANSITION_SEARCH $description '
            'title=${translateUi(destination.title, language)} '
            'id=${destination.id} pixels=${position.pixels} '
            'playback=${tester.getRect(playback)} '
            'transition=${tester.getRect(selector)} reached=$reached');
        if (!reached) missed.add(description);
        await _capture(tester, boundary,
            'search-initial-${language.code}-${size.$1.toInt()}');
        // Independently prove user scrolling can reach every existing control.
        for (final title in ['播放速度', '升降调', 'WASAPI 独占输出']) {
          final text = find.text(translateUi(title, language));
          await tester.ensureVisible(text);
          await tester.pumpAndSettle();
          _completeText(tester, text);
          expect(text.hitTestable(), findsOneWidget);
        }
        await tester.ensureVisible(selector);
        await tester.pumpAndSettle();
        expect(selector.hitTestable(), findsOneWidget);
        final compact = find.descendant(
            of: selector, matching: find.byType(OutlinedButton));
        if (compact.evaluate().isNotEmpty) {
          await tester.tap(compact);
          await tester.pumpAndSettle();
          for (final label in ['常规切换', '连续输出', '交叉淡入淡出']) {
            final item = find.widgetWithText(
                MenuItemButton, translateUi(label, language));
            expect(item.hitTestable(), findsOneWidget);
            _completeText(
                tester,
                find.descendant(
                    of: item,
                    matching: find.text(translateUi(label, language))));
            expect(tester.getRect(item).left, greaterThanOrEqualTo(-1));
            expect(tester.getRect(item).right, lessThanOrEqualTo(size.$1 + 1));
          }
          await _capture(
              tester, boundary, 'choices-${language.code}-${size.$1.toInt()}');
          await tester.sendKeyEvent(LogicalKeyboardKey.escape,
              physicalKey: PhysicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
        for (final original in [_description, _fallbackDescription]) {
          final text = find.text(translateUi(original, language));
          await tester.ensureVisible(text);
          await tester.pumpAndSettle();
          _completeText(tester, text);
        }
        expect(_settingsFile.existsSync(), isFalse,
            reason: 'Opening settings and its menu must not persist anything.');
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    expect(missed, isEmpty,
        reason: 'A transition search must reveal the transition surface.');
  });

  testWidgets(
      'real playback settings mode switch cancels its draft before saving',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(
        tester,
        const SettingsPage(
            initialSection: 'library', initialSetting: 'playback'));
    final settings = AppSettings.instance;
    final baseline = settings.experience.value;
    await tester.runAsync(() =>
        settings.saveSettings(throwOnError: true, captureWindowSize: false));
    final previousBytes = _settingsFile.readAsBytesSync();
    final slider = find.byKey(_sliderKey);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(slider), pointer: 1);
    var released = false;
    try {
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, greaterThan(3));
      expect(_settingsFile.readAsBytesSync(), previousBytes);
      await _selectMode(tester, PlaybackTransitionMode.standard);
      final saved = await _saved(tester, PlaybackTransitionMode.standard);
      expect((saved['PlaybackTransitions'] as Map)['crossfadeSeconds'], 3);
      final switchedBytes = _settingsFile.readAsBytesSync();
      await gesture.up();
      released = true;
      await _drainSaves(tester);
      expect(_settingsFile.readAsBytesSync(), switchedBytes);
      expect(settings.experience.value, baseline);
      await _selectMode(tester, PlaybackTransitionMode.crossfade);
      await _saved(tester, PlaybackTransitionMode.crossfade);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final fresh = await tester.startGesture(tester.getCenter(slider));
      await fresh.moveBy(const Offset(80, 0));
      await tester.pump();
      final draft = tester.widget<Slider>(slider).value;
      expect(settings.playbackTransitions.value.crossfadeSeconds, 3);
      await fresh.up();
      await _drainSaves(tester);
      final finalSaved = await _saved(tester, PlaybackTransitionMode.crossfade);
      expect((finalSaved['PlaybackTransitions'] as Map)['crossfadeSeconds'],
          draft);
      expect(settings.playbackTransitions.value.crossfadeSeconds, draft);
      expect(settings.experience.value, baseline);
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      if (!released) await gesture.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'leaving the actual settings section cancels held transition input',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppSettings.instance.rendering.value =
        AppSettings.instance.rendering.value.copyWith(pauseWhenHidden: false);
    await _mount(
        tester,
        const SettingsPage(
            initialSection: 'library', initialSetting: 'playback'));
    final slider = find.byKey(_sliderKey);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(tester.getCenter(slider), pointer: 1);
    var released = false;
    try {
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(tester.widget<Slider>(slider).value, greaterThan(3));
      await tester.tap(find.byKey(const ValueKey('settings-category-lyrics')),
          pointer: 2);
      await tester.pumpAndSettle();
      final retained =
          find.byType(PlaybackTransitionSettings, skipOffstage: false);
      final context = tester.element(retained);
      expect(TickerMode.valuesOf(context).enabled, isTrue,
          reason:
              'This case keeps hidden visual updates enabled intentionally.');
      expect(SettingsSectionVisibility.isVisibleOf(context), isFalse);
      await gesture.up();
      released = true;
      await _drainSaves(tester);
      expect(
          AppSettings.instance.playbackTransitions.value.crossfadeSeconds, 3);
      expect(_settingsFile.existsSync(), isFalse,
          reason:
              'Hidden visual effects do not authorize hidden input commits.');
      await tester.tap(find.byKey(const ValueKey('settings-category-library')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final fresh = await tester.startGesture(tester.getCenter(slider));
      await fresh.moveBy(const Offset(80, 0));
      await tester.pump();
      final draft = tester.widget<Slider>(slider).value;
      await fresh.up();
      await _drainSaves(tester);
      expect(AppSettings.instance.playbackTransitions.value.crossfadeSeconds,
          draft);
      expect(
          (await _saved(
              tester, PlaybackTransitionMode.crossfade))['PlaybackTransitions'],
          containsPair('crossfadeSeconds', draft));
      expect(PlayService.isInitialized, isFalse);
      expect(tester.takeException(), isNull);
    } finally {
      if (!released) await gesture.cancel();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
      'guide sound link opens real settings and reaches transition options',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    uiLanguage.value = UiLanguage.zh;
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
              body: Center(
                  child: TextButton(
                      key: const ValueKey('fixture-open-guide'),
                      onPressed: () => showPlayerFeatureGuide(context),
                      child: const Text('Guide'))))),
      GoRoute(
          path: '/settings',
          builder: (_, state) => Scaffold(
              body: SettingsPage(
                  initialSection: state.uri.queryParameters['section'],
                  initialSetting: state.uri.queryParameters['setting']))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        theme: _theme(UiLanguage.zh),
        builder: (context, child) =>
            _frame(context, child!, language: UiLanguage.zh)));
    await tester.tap(find.byKey(const ValueKey('fixture-open-guide')));
    await tester.pumpAndSettle();
    final header = find
        .descendant(
            of: find.byKey(const ValueKey('guide-section-sound')),
            matching: find.byType(ListTile))
        .first;
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
    final description = find.text(_guideDescription);
    await tester.ensureVisible(description);
    await tester.pumpAndSettle();
    _completeText(tester, description);
    final link = find.byKey(const ValueKey('guide-speed-pitch-settings'));
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(PlayerFeatureGuideDialog), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.toString(),
        '/settings?section=library&setting=playback');
    expect(find.byType(PlaybackSettings), findsOneWidget);
    final selector = find.byKey(_modeKey);
    await tester.ensureVisible(selector);
    await tester.pumpAndSettle();
    expect(selector.hitTestable(), findsOneWidget);
    expect(find.byKey(_sliderKey), findsOneWidget);
    expect(
        AppSettings.instance.playbackTransitions.value,
        const PlaybackTransitionPreferences(
            mode: PlaybackTransitionMode.crossfade));
    expect(_settingsFile.existsSync(), isFalse);
    expect(PlayService.isInitialized, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
