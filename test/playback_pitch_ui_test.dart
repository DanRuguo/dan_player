import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/playback_diagnostics_panel.dart';
import 'package:dan_player/component/playback_pitch_control.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/l10n/catalog_listening_tools.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('packages/desktop_lyric/assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });

  test('new messages have all languages and matching placeholders', () {
    final pattern = RegExp(r'\{\d+\}');
    for (final entry in catalogListeningTools.entries) {
      expect(entry.value.length, 3);
      final expected = pattern.allMatches(entry.key).map((m) => m[0]).toSet();
      for (final translated in entry.value) {
        expect(translated.trim(), isNotEmpty);
        expect(
            pattern.allMatches(translated).map((m) => m[0]).toSet(), expected);
      }
    }
    final playback =
        settingsSearchEntries.singleWhere((e) => e.id == 'playback');
    expect(playback.terms, contains('升降调'));
    for (final language in UiLanguage.values) {
      expect(translateUi('升降调', language), isNotEmpty);
    }
  });

  testWidgets('semitone steps, limits and original-pitch reset are actionable',
      (tester) async {
    var pitch = 11.0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, update) => PlaybackPitchControl(
        pitch: pitch,
        onChanged: (value) => update(() => pitch = value),
      ),
    ))));
    await tester.tap(find.byKey(const ValueKey('playback-pitch-up')));
    await tester.pumpAndSettle();
    expect(pitch, 12);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('playback-pitch-up')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('playback-pitch-down')));
    await tester.pumpAndSettle();
    expect(pitch, 11);
    await tester.tap(find.byKey(const ValueKey('playback-pitch-menu')));
    await tester.pumpAndSettle();
    final original = find.byKey(const ValueKey(('playback-pitch', 0.0)));
    await tester.ensureVisible(original);
    await tester.tap(original);
    await tester.pumpAndSettle();
    expect(pitch, 0);
    expect(find.text(ui('原调')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(PlayService.isInitialized, isFalse);
  });

  testWidgets('full-player menu adjusts pitch while preserving chosen speed',
      (tester) async {
    var pitch = 0.0;
    var rate = 1.25;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
                child: StatefulBuilder(
      builder: (context, update) => PlaybackRateMenu(
        rate: rate,
        pitch: pitch,
        onSelected: (value) => update(() => rate = value),
        onPitchSelected: (value) => update(() => pitch = value),
      ),
    )))));
    await tester.tap(find.byKey(const ValueKey('playback-rate-menu')));
    await tester.pumpAndSettle();
    final submenu = find.byKey(const ValueKey('playback-pitch-submenu'));
    await tester.ensureVisible(submenu);
    await tester.tap(submenu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('playback-pitch-step-up')));
    await tester.pumpAndSettle();
    expect(pitch, 1);
    expect(rate, 1.25);
    expect(tester.getSize(find.byKey(const ValueKey('playback-rate-menu'))),
        const Size.square(44));
    expect(find.byType(MenuItemButton), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('missing pitch component disables pitch controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: PlaybackSettingsPanel(
        playbackRate: 1,
        exclusive: false,
        pitchAvailable: false,
        onRateChanged: (_) {},
        onExclusiveChanged: (_) {},
        onPitchChanged: (_) => fail('unavailable component'),
      ),
    ))));
    expect(find.text(ui('当前安装缺少升降调组件，仍可正常播放。')), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('playback-pitch-up')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('playback-pitch-menu')))
            .onPressed,
        isNull);
  });

  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets('pitch controls render ${language.name} narrow=$narrow',
          (tester) async {
        tester.view.physicalSize = Size(narrow ? 320 : 900, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        final boundary = GlobalKey();
        final scheme = ColorScheme.fromSeed(
            seedColor: narrow ? Colors.purple : Colors.teal,
            brightness: narrow ? Brightness.dark : Brightness.light);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: UiLanguageScope(
                child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: Entry(welcome: false)
                  .fromSchemeAndFontFamily(colorScheme: scheme),
              locale: language.locale,
              supportedLocales: UiLanguage.values.map((v) => v.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
                  child: child!),
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: PlaybackSettingsPanel(
                playbackRate: 1.25,
                playbackPitch: 3,
                exclusive: false,
                onRateChanged: (_) {},
                onPitchChanged: (_) {},
                onExclusiveChanged: (_) {},
              ))),
            ))));
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('playback-pitch-menu')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button =
            tester.getRect(find.byKey(const ValueKey('playback-pitch-menu')));
        expect(button.left, greaterThanOrEqualTo(0));
        expect(button.right, lessThanOrEqualTo(narrow ? 320 : 900));
        expect(button.height, greaterThanOrEqualTo(44));
        const output = String.fromEnvironment('DAN_LISTENING_RENDER_DIR');
        Future<void> capture(String state) async {
          if (output.isEmpty) return;
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file =
                File('$output/pitch-${language.name}-$narrow-$state.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('panel');
        await tester.tap(find.byKey(const ValueKey('playback-pitch-menu')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final topOctave = find.byKey(const ValueKey(('playback-pitch', 12.0)));
        await tester.ensureVisible(topOctave);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(topOctave).right,
            lessThanOrEqualTo(narrow ? 320 : 900));
        await capture('menu');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }

  testWidgets('new pitch diagnostic row fits every language and window width',
      (tester) async {
    for (final language in UiLanguage.values) {
      for (final width in [320.0, 1100.0]) {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        uiLanguage.value = language;
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          locale: language.locale,
          supportedLocales: UiLanguage.values.map((v) => v.locale),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 2 : 1)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: PlaybackDiagnosticsContent(
            snapshot: const {
              'phase': 'paused',
              'output': {'playbackPitch': 3.0, 'playbackRate': 1.25}
            },
            onRefresh: () {},
            onExport: (_) async {},
          ))),
        )));
        await tester.pumpAndSettle();
        final shifted = find.text(ui('{0} 半音', ['+3']));
        expect(shifted, findsOneWidget);
        await tester.ensureVisible(shifted);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getRect(shifted).right, lessThanOrEqualTo(width));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    uiLanguage.value = UiLanguage.zh;
  });
}
