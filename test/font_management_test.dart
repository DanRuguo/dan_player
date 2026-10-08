import 'dart:async';
import 'dart:io';
import 'dart:ui' as raster;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/font_preview_loader.dart';
import 'package:dan_player/font/app_font_manager.dart';
import 'package:dan_player/font/font_preferences.dart';
import 'package:dan_player/page/settings_page/font_management_dialog.dart';
import 'package:dan_player/page/settings_page/font_selector_dialog.dart';
import 'package:dan_player/src/rust/api/installed_font.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppFontPreferences original;
  late UiLanguage language;
  setUp(() {
    original = AppSettings.instance.fontPreferences;
    language = uiLanguage.value;
  });
  tearDown(() {
    AppSettings.instance.fontPreferences = original;
    uiLanguage.value = language;
  });

  test('legacy custom choice migrates without replacing its family or file',
      () {
    final prefs = AppFontPreferences.decode(null,
        legacyFamily: 'Private Typeface', legacyPath: 'J:/fixture/private.ttf');
    expect(prefs.perLanguage, false);
    expect(prefs.mixedScripts, false);
    expect(prefs.shared.family, 'Private Typeface');
    expect(prefs.shared.path, 'J:/fixture/private.ttf');
    expect(AppFontPreferences.decode(prefs.toJson()), prefs);
    expect(AppFontPreferences.decode(null, legacyFamily: 'DanPingFangSC'),
        const AppFontPreferences());
  });
  test('bundled settings have stable IDs and preserve inactive language slots',
      () {
    const prefs = AppFontPreferences(ja: AppFontChoice.bundled('google-sans'));
    final unified = prefs.copyWith(perLanguage: false);
    expect(unified.ja, prefs.ja);
    expect(
        AppFontPreferences.decode(unified.toJson()).copyWith(perLanguage: true),
        prefs);
    expect(prefs.toJson().toString(), isNot(contains('flutter_assets')));
    expect(
        AppFontPreferences.decode({
          'version': 1,
          'zh': {'id': 'unknown'},
          'perLanguage': []
        }),
        const AppFontPreferences());
  });
  test(
      'missing or invalid custom files fall back and keep the persisted choice',
      () async {
    const custom =
        AppFontChoice.custom(family: 'Missing', path: 'J:/fixture/missing.ttf');
    final manager =
        AppFontManager(fileExists: (_) async => false, load: (_) async {});
    addTearDown(manager.dispose);
    await manager.apply(const AppFontPreferences(ko: custom));
    expect(manager.policy.value.ko.id, 'pretendard');
    expect(manager.missingCustomFonts.value, [custom]);
    await manager
        .apply(const AppFontPreferences(perLanguage: false, shared: custom));
    expect(manager.policy.value.faces.map((face) => face.id).toSet(),
        {'source-han-sc'});
    await expectLater(
        manager.prepare(const AppFontPreferences(ko: custom), UiLanguage.ko,
            strict: true),
        throwsStateError);
    final corrupt = AppFontManager(
        fileExists: (_) async => true,
        load: (policy) async {
          if (policy.faces.any((font) => font.id == 'custom')) {
            throw StateError('invalid font');
          }
        });
    addTearDown(corrupt.dispose);
    await corrupt.apply(const AppFontPreferences(ko: custom));
    expect(corrupt.policy.value.ko.id, 'pretendard');
    expect(corrupt.missingCustomFonts.value, [custom]);
  });
  test('late font loading cannot overwrite a newer choice', () async {
    final old = Completer<void>();
    final manager = AppFontManager(
        load: (policy) =>
            policy.zh.id == 'google-sans' ? old.future : Future.value());
    addTearDown(manager.dispose);
    final pending = manager.apply(
        const AppFontPreferences(zh: AppFontChoice.bundled('google-sans')));
    await manager.apply(const AppFontPreferences());
    old.complete();
    await pending;
    expect(manager.policy.value.zh.id, 'source-han-sc');
  });
  test('invalid custom bytes never become an active font', () async {
    final fixture = await Directory.systemTemp.createTemp('dan-font-invalid-');
    addTearDown(() => fixture.delete(recursive: true));
    final file = File('${fixture.path}/invalid.ttf');
    await file.writeAsBytes(List.filled(16, 0));
    final manager = AppFontManager();
    addTearDown(manager.dispose);
    await manager.apply(AppFontPreferences(
        zh: AppFontChoice.custom(
            family: 'Invalid font fixture', path: file.path)));
    expect(manager.policy.value.zh.id, 'source-han-sc');
  });
  test('failed save keeps settings and the active policy unchanged', () async {
    final manager = AppFontManager(load: (_) async {});
    addTearDown(manager.dispose);
    await manager.apply(original);
    final before = manager.policy.value;
    await expectLater(
        manager.commit(const AppFontPreferences(perLanguage: false),
            persist: () async => throw StateError('disk full')),
        throwsStateError);
    expect(AppSettings.instance.fontPreferences, original);
    expect(manager.policy.value, before);
  });
  test('malformed SFNT directory is rejected and a restored font can retry',
      () async {
    final fixture =
        await Directory.systemTemp.createTemp('dan-font-directory-');
    addTearDown(() => fixture.delete(recursive: true));
    final file = File('${fixture.path}/restorable.ttf');
    final bytes = ByteData(28)
      ..setUint32(0, 0x00010000)
      ..setUint16(4, 1)
      ..setUint32(12, 0x6e616d65)
      ..setUint32(20, 28);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final choice =
        AppFontChoice.custom(family: 'Restored font fixture', path: file.path);
    final preferences = AppFontPreferences(zh: choice);
    final manager = AppFontManager();
    addTearDown(manager.dispose);
    await manager.apply(preferences);
    expect(manager.policy.value.zh.id, 'source-han-sc');
    final active = manager.policy.value;
    await expectLater(manager.commit(preferences, persist: () async {}),
        throwsFormatException);
    expect(manager.policy.value, active);
    expect(AppSettings.instance.fontPreferences, original);
    await File('third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')
        .copy(file.path);
    await manager.apply(preferences);
    expect(manager.policy.value.zh, choice.face);
    expect(manager.missingCustomFonts.value, isEmpty);
  });
  test('language switches reuse loaded faces, including a switch during save',
      () async {
    var loads = 0;
    final manager = AppFontManager(load: (_) async {
      loads++;
    });
    addTearDown(manager.dispose);
    await manager.initialize();
    final count = loads;
    uiLanguage.value = UiLanguage.en;
    expect(manager.policy.value.uiFamily, appBundledFonts[1].family);
    expect(loads, count);
    final saved = Completer<void>();
    final pending = manager.commit(
        const AppFontPreferences(en: AppFontChoice.bundled('pretendard')),
        persist: () => saved.future);
    await Future<void>.delayed(Duration.zero);
    uiLanguage.value = UiLanguage.ko;
    expect(manager.policy.value.language, UiLanguage.ko);
    expect(manager.policy.value.en.id, original.en.id);
    saved.complete();
    await pending;
    expect(manager.policy.value.language, UiLanguage.ko);
    expect(manager.policy.value.en.id, 'pretendard');
    expect(AppSettings.instance.fontPreferences.en.id, 'pretendard');
  });
  test('language switch during initial loading keeps the newest language',
      () async {
    final loaded = Completer<void>();
    final manager = AppFontManager(load: (_) => loaded.future);
    addTearDown(manager.dispose);
    final initialized = manager.initialize();
    uiLanguage.value = UiLanguage.ja;
    loaded.complete();
    await initialized;
    expect(manager.policy.value.language, UiLanguage.ja);
    expect(manager.policy.value.baseFallback.path, contains('packages'));
  });
  test('mixed font runs preserve authored UTF16 and complete graphemes', () {
    const text = 'A\u0301 汉字かな 한글 👨‍👩‍👧‍👦 🇰🇷 𠮷';
    final runs = appFontRuns(text, UiLanguage.zh);
    expect(runs.map((run) => run.text).join(), text);
    expect(runs.first.text.startsWith('A\u0301'), true);
    expect(
        runs.any((run) =>
            run.language == UiLanguage.ja && run.text.contains('汉字かな')),
        true);
    expect(
        runs.any(
            (run) => run.language == UiLanguage.ko && run.text.contains('한글')),
        true);
    expect(identical(runs, appFontRuns(text, UiLanguage.zh)), true);
    final span = appFontSpan(text,
        style: const TextStyle(color: Colors.red, fontSize: 28),
        policy: AppFontPolicy.defaults());
    expect(span.toPlainText(), text);
    expect(span.children!.whereType<TextSpan>().first.style!.fontFamily,
        appBundledFonts[1].family);
    expect(appFontRuns('漢字', UiLanguage.ja).single.language, UiLanguage.ja);
    expect(appFontRuns('汉字', UiLanguage.zh).single.language, UiLanguage.zh);
  });

  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  testWidgets(
      'font enumeration can be cancelled without late results reopening the dialog',
      (tester) async {
    final fonts = Completer<List<InstalledFont>?>();
    final manager = AppFontManager(load: (_) async {});
    addTearDown(manager.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => FontManagementDialog(
                            manager: manager, getFonts: () => fonts.future)),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('font-slot-ko')));
    await tester.tap(find.byKey(const ValueKey('font-slot-ko')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('选择已安装字体')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(find.byType(FontManagementDialog), findsNothing);
    fonts.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(FontManagementDialog), findsNothing);
    expect(AppSettings.instance.fontPreferences, original);
    expect(tester.takeException(), isNull);
  });
  testWidgets('installed selection stages a draft until the outer apply',
      (tester) async {
    final manager = AppFontManager(load: (_) async {});
    addTearDown(manager.dispose);
    final font = InstalledFont(
        fullName: 'Installed Preview SC',
        path: File(
                'third_party/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')
            .absolute
            .path);
    final family = await tester.runAsync(() async {
      final preview = FontPreviewLoader.instance.acquire(font, explicit: true);
      try {
        return await preview.family;
      } finally {
        preview.release();
      }
    });
    expect(family, font.fullName);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => FontManagementDialog(
                            manager: manager, getFonts: () async => [font])),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('font-slot-ko')));
    await tester.tap(find.byKey(const ValueKey('font-slot-ko')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ui('选择已安装字体')));
    await tester.pumpAndSettle();
    final row = find.byKey(ValueKey(('font-row', font)));
    await tester.ensureVisible(row);
    await tester.tap(row);
    // The real file loader completes outside the widget fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('font-selector-apply')))
            .onPressed,
        isNotNull);
    await tester.tap(find.text(ui('使用此字体')));
    await tester.pumpAndSettle();
    expect(find.byType(FontSelectorDialog), findsNothing);
    expect(find.byType(FontManagementDialog), findsOneWidget);
    expect(AppSettings.instance.fontPreferences, original);
    await tester.tap(find.text(ui('取消')));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.fontPreferences, original);
    expect(tester.takeException(), isNull);
  });
  testWidgets('duplicate apply keeps save ownership until persistence finishes',
      (tester) async {
    final manager = AppFontManager(load: (_) async {});
    addTearDown(manager.dispose);
    final saved = Completer<void>();
    var commits = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => FontManagementDialog(
                            manager: manager,
                            initial:
                                const AppFontPreferences(perLanguage: false),
                            persist: () {
                              commits++;
                              return saved.future;
                            })),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final apply = find.byKey(const ValueKey('font-management-apply'));
    await tester.tap(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(commits, 1);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, ui('取消')))
            .onPressed,
        isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    expect(find.byKey(const ValueKey('font-management-error')), findsNothing);
    saved.complete();
    await tester.pumpAndSettle();
    expect(find.byType(FontManagementDialog), findsNothing);
    expect(AppSettings.instance.fontPreferences.perLanguage, isFalse);
    expect(tester.takeException(), isNull);
  });
  for (final locale in UiLanguage.values) {
    for (final width in [360.0, 920.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
            'font manager renders ${locale.code} at $width/$scale with reachable controls',
            (tester) async {
          uiLanguage.value = locale;
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final manager = AppFontManager(load: (_) async {});
          addTearDown(manager.dispose);
          final boundary = GlobalKey();
          await tester.pumpWidget(UiLanguageScope(
              child: MaterialApp(
                  locale: locale.locale,
                  theme: applyAppControlTheme(ThemeData(
                      fontFamily:
                          AppFontPolicy.defaults(language: locale).uiFamily,
                      fontFamilyFallback: danFontFamilyFallback,
                      useMaterial3: true,
                      colorScheme:
                          ColorScheme.fromSeed(seedColor: Colors.teal))),
                  builder: (_, child) => MediaQuery(
                      data: MediaQuery.of(_)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!),
                  home: Scaffold(
                      body: RepaintBoundary(
                          key: boundary,
                          child: FontManagementDialog(
                              manager: manager,
                              initial: const AppFontPreferences(),
                              persist: () async {}))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('font-management-apply')),
              findsOneWidget);
          await tester
              .ensureVisible(find.byKey(const ValueKey('font-slot-ko')));
          await tester.tap(find.byKey(const ValueKey('font-slot-ko')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('font-choice-ko-source-han-jp')),
              findsOneWidget);
          await tester
              .tap(find.byKey(const ValueKey('font-choice-ko-source-han-jp')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final scroll = tester.widget<SingleChildScrollView>(
              find.byKey(const ValueKey('font-management-scroll')));
          final scrollState = tester.state<ScrollableState>(find
              .descendant(
                  of: find.byWidget(scroll), matching: find.byType(Scrollable))
              .first);
          scrollState.position.jumpTo(0);
          await tester.pumpAndSettle();
          final output = Platform.environment['DAN_FONT_MANAGEMENT_RENDER_DIR'];
          if (output != null) {
            await tester.runAsync(() async {
              final image = await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: raster.ImageByteFormat.png);
              await Directory(output).create(recursive: true);
              await File(
                      '$output/font-${locale.code}-${width.toInt()}-$scale.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
    }
  }
}
