import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/page/settings_page/playback_transition_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_control.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_preview.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

const _themeKey = ValueKey('feedback-reference-theme');
const _lyricsKey = ValueKey('feedback-lyrics');
const _transitionKey = ValueKey('feedback-transition');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final qa = path.join(Directory.current.parent.path, 'tool', 'qa-local',
      'lyric-settings-feedback-oct11', 'ui');
  final data = Directory(path.join(qa, 'data'));
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late NowPlayingProgressStyle previousProgress;
  late WaveformBarDensity previousDensity;
  late LocalLyricLineOrder previousOrder;
  late UiLanguage previousLanguage;
  late ValueNotifier<DesktopLyricAppearance> appearance;
  late ValueNotifier<JapaneseReadingPreferences> readings;
  late ValueNotifier<PlayerExperiencePreferences> experience;
  late ValueNotifier<PlaybackTransitionPreferences> transitions;
  var saves = 0;

  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    expect(Directory.systemTemp.absolute.path.replaceAll('\\', '/'),
        contains('/tool/qa-local/'));
    await data.create(recursive: true);
    messenger.setMockMethodCallHandler(provider, (_) async => data.path);
    expect(path.isWithin(data.path, (await getAppDataDir()).path), isTrue);
    for (final language in UiLanguage.values) {
      await ensureAppFontsLoaded(AppFontPolicy.defaults(language: language));
    }
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
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));
  setUp(() {
    previousLanguage = uiLanguage.value;
    final settings = AppSettings.instance;
    previousProgress = settings.nowPlayingProgressStyle.value;
    previousDensity = settings.waveformBarDensity.value;
    previousOrder = settings.localLyricLineOrder;
    settings.nowPlayingProgressStyle.value = NowPlayingProgressStyle.waveform;
    settings.waveformBarDensity.value = WaveformBarDensity.automatic;
    appearance = ValueNotifier(
        DesktopLyricAppearance.defaults.copyWith(lyricLetterSpacing: 6));
    readings = ValueNotifier(const JapaneseReadingPreferences());
    experience = ValueNotifier(const PlayerExperiencePreferences());
    transitions = ValueNotifier(const PlaybackTransitionPreferences(
        mode: PlaybackTransitionMode.crossfade));
    saves = 0;
  });
  tearDown(() {
    appearance.dispose();
    readings.dispose();
    experience.dispose();
    transitions.dispose();
    final settings = AppSettings.instance;
    settings.nowPlayingProgressStyle.value = previousProgress;
    settings.waveformBarDensity.value = previousDensity;
    settings.localLyricLineOrder = previousOrder;
    uiLanguage.value = previousLanguage;
  });

  Future<void> mount(WidgetTester tester, UiLanguage language,
      {required double width,
      required double scale,
      required GlobalKey boundary}) async {
    uiLanguage.value = language;
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final policy = AppFontPolicy.defaults(language: language);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: Entry(welcome: false)
            .fromSchemeAndFontFamily(
                fontFamily: policy.uiFamily,
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.blue,
                    brightness:
                        width > 560 ? Brightness.dark : Brightness.light))
            .copyWith(platform: TargetPlatform.windows),
        builder: (context, child) => RepaintBoundary(
            key: boundary,
            child: UiLanguageScope(
                child: AppFontScope(
                    policy: policy,
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(scale),
                            disableAnimations: true),
                        child: child!)))),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ThemeAppearanceSettings(key: _themeKey),
                          const SizedBox(height: 16),
                          LyricExperienceSettings(
                              key: _lyricsKey,
                              appearance: appearance,
                              japaneseReadings: readings,
                              preferences: experience,
                              persist: () async {
                                saves++;
                              }),
                          const SizedBox(height: 16),
                          PlaybackTransitionSettings(
                              key: _transitionKey,
                              preferences: transitions,
                              persist: () async {
                                saves++;
                              }),
                        ]))))));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    for (final size in [(1000.0, 1.0), (360.0, 2.0)]) {
      testWidgets(
          'settings feedback ${language.code} ${size.$1} ${size.$2} matches theme rows',
          (tester) async {
        final initiallyInitialized = PlayService.isInitialized;
        final boundary = GlobalKey();
        await mount(tester, language,
            width: size.$1, scale: size.$2, boundary: boundary);
        final spacing = find.byType(LyricLetterSpacingControl);
        // Export the actual settings/reference before the assertions so a new
        // geometry regression still leaves the rendered frame for diagnosis.
        final suffix = '${language.code}-${size.$1.toInt()}-${size.$2.toInt()}';
        for (final capture in [
          (find.byKey(_themeKey), 'theme'),
          (find.byKey(_lyricsKey), 'lyrics'),
          (spacing, 'spacing'),
          (find.byKey(_transitionKey), 'transition'),
        ]) {
          await tester.ensureVisible(capture.$1);
          await tester.pumpAndSettle();
          await _capture(tester, boundary, qa, '${capture.$2}-$suffix');
        }
        final themeSurface = find.descendant(
            of: find.byKey(_themeKey), matching: find.byType(SettingsSurface));
        final lyricSurface = find.descendant(
            of: find.byKey(_lyricsKey), matching: find.byType(SettingsSurface));
        final transitionSurface = find.descendant(
            of: find.byKey(_transitionKey),
            matching: find.byType(SettingsSurface));
        for (final surface in [themeSurface, lyricSurface, transitionSurface]) {
          expect(tester.widget<SettingsSurface>(surface).padding,
              const EdgeInsets.all(16));
          final bounds = tester.getRect(surface);
          for (final divider in find
              .descendant(of: surface, matching: find.byType(Divider))
              .evaluate()) {
            final rect = tester.getRect(find
                .byElementPredicate((element) => identical(element, divider)));
            expect(rect.left, closeTo(bounds.left + 16, .01));
            expect(rect.right, closeTo(bounds.right - 16, .01));
          }
        }
        final shared = tester.widget<LyricLetterSpacingControl>(spacing);
        expect(shared.heading, isA<SettingsHeader>());
        expect(shared.alignResetToEnd, isTrue);
        expect(shared.previewBuilder, isNotNull);
        final preview = tester.widget<LyricLetterSpacingPreview>(
            find.byType(LyricLetterSpacingPreview));
        expect(preview.text, ui('音乐伴每一天'));
        expect(preview.value, appearance.value.lyricLetterSpacing);
        expect(preview.visible, isTrue);
        final header = shared.heading! as SettingsHeader;
        expect(header.icon, Symbols.format_letter_spacing);
        expect(header.title, ui('歌词字间距'));
        final spacingHeader = find.byWidget(header);
        await tester.ensureVisible(spacing);
        await tester.pumpAndSettle();
        _expectHeader(tester, spacingHeader, lyricSurface);
        final value = find
            .descendant(
                of: find.byKey(
                    const ValueKey('settings-lyric-letter-spacing-value')),
                matching: find.byType(RichText))
            .evaluate()
            .single
            .renderObject! as RenderParagraph;
        final titleText = find
            .descendant(of: spacingHeader, matching: find.byType(Text))
            .first;
        final title = find
            .descendant(of: titleText, matching: find.byType(RichText))
            .evaluate()
            .single
            .renderObject! as RenderParagraph;
        expect(_baseline(value), closeTo(_baseline(title), .01));
        final reset =
            find.byKey(const ValueKey('settings-lyric-letter-spacing-reset'));
        final resetRect = tester.getRect(reset);
        expect(resetRect.height, greaterThanOrEqualTo(44));
        expect(resetRect.right,
            closeTo(tester.getRect(lyricSurface).right - 16, .01));
        final resetText =
            find.descendant(of: reset, matching: find.byType(Text));
        expect(tester.widget<Text>(resetText).textAlign, TextAlign.end);
        final resetParagraph = find
            .descendant(of: resetText, matching: find.byType(RichText))
            .evaluate()
            .single
            .renderObject! as RenderParagraph;
        for (final line in resetParagraph.getBoxesForSelection(TextSelection(
            baseOffset: 0,
            extentOffset: resetParagraph.text.toPlainText().length))) {
          expect(line.right, closeTo(resetParagraph.size.width, .5),
              reason: 'Every wrapped reset-label line follows the end edge.');
        }
        _expectTextPaint(tester, lyricSurface);
        for (final heading in find
            .descendant(
                of: transitionSurface, matching: find.byType(SettingsHeader))
            .evaluate()) {
          _expectHeader(
              tester, find.byWidget(heading.widget), transitionSurface);
        }
        _expectTextPaint(tester, transitionSurface);
        expect(saves, 0,
            reason: 'Layout and preview must not persist preferences.');
        expect(PlayService.isInitialized, initiallyInitialized);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('settings spacing draft previews locally and commits at release',
      (tester) async {
    await mount(tester, UiLanguage.zh,
        width: 1000, scale: 1, boundary: GlobalKey());
    final slider =
        find.byKey(const ValueKey('settings-lyric-letter-spacing-slider'));
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();
    final draft = tester.widget<Slider>(slider).value;
    expect(draft, greaterThan(6));
    expect(
        tester
            .widget<LyricLetterSpacingPreview>(
                find.byType(LyricLetterSpacingPreview))
            .value,
        draft);
    expect(appearance.value.lyricLetterSpacing, 6);
    expect(saves, 0);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LyricLetterSpacingPreview>(
                find.byType(LyricLetterSpacingPreview))
            .value,
        6);
    expect(saves, 0);
    final fresh = await tester.startGesture(tester.getCenter(slider));
    await fresh.moveBy(const Offset(-48, 0));
    await tester.pump();
    final committed = tester.widget<Slider>(slider).value;
    expect(committed, lessThan(6));
    expect(appearance.value.lyricLetterSpacing, 6);
    expect(saves, 0);
    await fresh.up();
    await tester.pumpAndSettle();
    expect(appearance.value.lyricLetterSpacing, committed);
    expect(saves, 1);
    expect(
        tester
            .widget<LyricLetterSpacingPreview>(
                find.byType(LyricLetterSpacingPreview))
            .value,
        committed);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets(
      'settings Japanese choice hint follows online gate without starting work',
      (tester) async {
    final automatic = AppSettings.instance.automaticOnlineLyrics;
    final previousAutomatic = automatic.value;
    addTearDown(() => automatic.value = previousAutomatic);
    automatic.value = false;
    readings.value = readings.value.copyWith(enabled: true);
    final initiallyInitialized = PlayService.isInitialized;
    final boundary = GlobalKey();
    await mount(tester, UiLanguage.en,
        width: 360, scale: 2, boundary: boundary);
    final switchTile =
        find.byKey(const ValueKey('japanese-reading-auto-switch'));
    await tester.ensureVisible(switchTile);
    await tester.pumpAndSettle();
    final hint = ui('自动联网已关闭，可在阅读工具勾选显示日语假名；联网生成与字典安装请使用下方设置。');
    expect(find.textContaining(hint), findsOneWidget);
    expect(saves, 0);
    automatic.value = true;
    await tester.pumpAndSettle();
    expect(find.textContaining(hint), findsNothing);
    expect(saves, 0);
    expect(PlayService.isInitialized, initiallyInitialized);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
}

double _baseline(RenderParagraph paragraph) {
  // getDistanceToBaseline is restricted to a parent's layout/paint phase.
  // Paragraph's public dry baseline uses the same text metrics with its actual
  // laid-out constraints and can be queried without changing those contents.
  final baseline =
      paragraph.getDryBaseline(paragraph.constraints, TextBaseline.alphabetic);
  expect(baseline, isNotNull);
  return paragraph.localToGlobal(Offset(0, baseline!)).dy;
}

void _expectHeader(WidgetTester tester, Finder header, Finder surface) {
  final icon = find.descendant(of: header, matching: find.byType(Icon));
  expect(icon, findsOneWidget);
  expect(tester.widget<Icon>(icon).size, 22);
  final card = tester.getRect(surface);
  final rect = tester.getRect(icon);
  expect(rect.center.dx, closeTo(card.left + 16 + 12, .01));
  // SettingsHeader reserves a 24px layout slot; SDK Icon centers its 22px
  // glyph inside those tight constraints, so the Icon's outer rect is 24px.
  expect(rect.width, 24);
  expect(rect.height, 24);
  final glyph = find.descendant(of: icon, matching: find.byType(RichText));
  expect(tester.widget<RichText>(glyph).text.style!.fontSize, 22);
  final glyphRect = tester.getRect(glyph);
  expect(glyphRect.center.dx, closeTo(rect.center.dx, .01));
  expect(glyphRect.center.dy, closeTo(rect.center.dy, .01));
  expect(glyphRect.height, 22);
  expect(glyphRect.width, lessThanOrEqualTo(24));
  final title = find.descendant(of: header, matching: find.byType(Text)).first;
  expect(tester.getRect(title).left, closeTo(card.left + 16 + 24 + 12, .01));
}

void _expectTextPaint(WidgetTester tester, Finder surface) {
  final bounds = tester.getRect(surface);
  for (final element in find
      .descendant(of: surface, matching: find.byType(RichText))
      .evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    final text = paragraph.text.toPlainText();
    // Buttons may intentionally shorten their compact selected summary. Their
    // full native menu labels retain the previously verified wrap contract.
    if (paragraph.overflow == TextOverflow.ellipsis ||
        paragraph.overflow == TextOverflow.fade) {
      continue;
    }
    expect(paragraph.didExceedMaxLines, isFalse, reason: text);
    var offset = 0;
    // A supplementary icon, combining mark or emoji is one cluster. Partial
    // UTF-16 selections have no glyph boxes and do not describe clipped text.
    for (final cluster in text.characters) {
      final start = offset;
      offset += cluster.length;
      if (cluster.trim().isEmpty) continue;
      final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: offset));
      expect(boxes, isNotEmpty, reason: text);
      for (final box in boxes) {
        final topLeft = paragraph.localToGlobal(Offset(box.left, box.top));
        final bottomRight =
            paragraph.localToGlobal(Offset(box.right, box.bottom));
        expect(topLeft.dx, greaterThanOrEqualTo(bounds.left + 15.5),
            reason: text);
        expect(bottomRight.dx, lessThanOrEqualTo(bounds.right - 15.5),
            reason: text);
        expect(topLeft.dy, greaterThanOrEqualTo(bounds.top), reason: text);
        expect(bottomRight.dy, lessThanOrEqualTo(bounds.bottom), reason: text);
      }
    }
  }
}

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String qa, String name) async {
  final directory = Platform.environment['DAN_SETTINGS_FEEDBACK_RENDER_DIR'];
  if (directory == null) return;
  expect(path.isWithin(qa, path.normalize(directory)), isTrue,
      reason: 'The render export stays in this explicit QA directory.');
  await tester.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final bytes = await image.toByteData(format: raster.ImageByteFormat.png);
      await File(path.join(directory, '$name.png'))
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
