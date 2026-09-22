import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as drawing;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/animation_settings.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/src/bass/spectrum_analysis.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });

  test('passive bass level reuses only existing low frequency bands', () {
    final low = SpectrumAnalysis();
    final high = SpectrumAnalysis();
    final toneOnly = SpectrumAnalysis();
    final fft = Float32List(SpectrumAnalysis.fftValues)..[8] = .2;
    low.update(fft, 48000, frequencyDemand: true, toneDemand: false);
    toneOnly.update(fft, 48000, frequencyDemand: false, toneDemand: true);
    fft[8] = 0;
    fft[85] = .2;
    high.update(fft, 48000, frequencyDemand: true, toneDemand: false);
    expect(low.lowFrequencyLevel, inExclusiveRange(0, 1));
    expect(high.lowFrequencyLevel, 0);
    expect(toneOnly.lowFrequencyLevel, 0);
    final snapshot = List<double>.of(low.frequencies);
    for (var index = 0; index < 10000; index++) {
      expect(low.lowFrequencyLevel, greaterThan(0));
    }
    expect(low.frequencies, snapshot,
        reason: 'Reading does not smooth or request another sample');
    expect(low.tones, everyElement(0));
  });

  test('bass snapshot rejects invalid cached levels and remains bounded', () {
    final analysis = SpectrumAnalysis();
    analysis.frequencies.fillRange(0, 12, 2);
    expect(analysis.lowFrequencyLevel, 1);
    analysis.frequencies.fillRange(0, 12, double.nan);
    expect(analysis.lowFrequencyLevel, 0);
    analysis.frequencies.fillRange(0, 12, -.1);
    expect(analysis.lowFrequencyLevel, 0);
  });

  test(
      'bass preference defaults off and survives snapshots without changing other scenes',
      () {
    expect(BackgroundPreferences.fromMap(const {}).nowPlaying.bassReactive,
        isFalse);
    expect(
        BackgroundPreferences.fromMap(const {
          'nowPlaying': {'bassReactive': 'yes'}
        }).nowPlaying.bassReactive,
        isFalse);
    const original = BackgroundPreferences(
        nowPlaying: BackgroundAppearance(
            source: BackgroundSource.artwork,
            motion: true,
            bassReactive: true));
    expect(BackgroundPreferences.fromMap(original.toMap()), original);
    final snapshot = PerformanceSnapshot.capture(const RenderingPreferences(),
        original, const PlayerExperiencePreferences(), false);
    final restored = PerformanceSnapshot.fromMap(snapshot.toMap())!;
    expect(restored.backgrounds, original);
    expect(
        restored
            .forMode(PerformanceMode.economy)
            .backgrounds
            .nowPlaying
            .bassReactive,
        isFalse);
    expect(
        restored
            .forMode(PerformanceMode.performance)
            .backgrounds
            .nowPlaying
            .bassReactive,
        isTrue);
    expect(
        restored
            .forMode(PerformanceMode.performance)
            .backgrounds
            .main
            .bassReactive,
        isFalse);
    expect(restored.forMode(PerformanceMode.custom).backgrounds, original);
  });

  test('preset switching restores a legacy snapshot without bass response',
      () async {
    final original = PerformanceSnapshot.capture(
        const RenderingPreferences(),
        const BackgroundPreferences(),
        const PlayerExperiencePreferences(),
        false);
    final legacy = original.toMap();
    final backgroundMap = legacy['backgrounds'] as Map<String, Object>;
    for (final scene in BackgroundScene.values) {
      (backgroundMap[scene.name] as Map<String, Object>).remove('bassReactive');
    }
    var live = original;
    final controller = PerformancePresetController(
        capture: () => live,
        apply: (value) => live = value,
        persist: () async {});
    addTearDown(controller.dispose);
    await controller.select(PerformanceMode.performance);
    expect(live.backgrounds.nowPlaying.bassReactive, isTrue);
    await controller.select(PerformanceMode.economy);
    expect(live.backgrounds.nowPlaying.bassReactive, isFalse);
    controller.value =
        PerformancePresetState.fromMap({'mode': 'economy', 'before': legacy});
    await controller.select(PerformanceMode.custom);
    expect(live.backgrounds.nowPlaying.bassReactive, isFalse);
    expect(live.toMap(), original.toMap());
  });

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'bass setting ${language.name} ${brightness.name} fits and respects spectrum demand',
          (tester) async {
        final settings = AppSettings.instance;
        final savedRendering = settings.rendering.value;
        settings.rendering.value = const RenderingPreferences();
        uiLanguage.value = language;
        addTearDown(() {
          settings.rendering.value = savedRendering;
          uiLanguage.value = UiLanguage.zh;
        });
        tester.view.physicalSize = const Size(520, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = ValueNotifier(const BackgroundPreferences(
          nowPlaying: BackgroundAppearance(
              source: BackgroundSource.artwork, motion: true),
        ));
        final status = ValueNotifier(
            const WindowBackdropStatus(available: true, effect: 'blur'));
        addTearDown(preferences.dispose);
        addTearDown(status.dispose);
        var saves = 0;
        final boundary = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: UiLanguageScope(
                child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  fontFamily: danEmbeddedFontFamily,
                  fontFamilyFallback: danFontFamilyFallback,
                  colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.orange, brightness: brightness)),
              home: MediaQuery(
                  data: const MediaQueryData(
                      size: Size(520, 1200),
                      textScaler: TextScaler.linear(1.3)),
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: BackgroundSettingsPanel(
                    preferences: preferences,
                    status: status,
                    onSave: () async => saves++,
                  )))),
            ))));
        final toggle = find.byKey(const ValueKey('background-bass-reactive'));
        expect(toggle, findsNothing);
        await tester
            .tap(find.byKey(const ValueKey('background-scene-nowPlaying')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(toggle);
        final title = translateUi('低频律动背景', language);
        expect(find.text(title), findsOneWidget);
        if (language != UiLanguage.zh) expect(title, isNot('低频律动背景'));
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(preferences.value.nowPlaying.bassReactive, isTrue);
        expect(preferences.value.main.bassReactive, isFalse);
        expect(saves, 1);
        settings.rendering.value =
            settings.rendering.value.copyWith(lyricSpectrum: false);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
        expect(preferences.value.nowPlaying.bassReactive, isTrue);
        preferences.value = preferences.value.withScene(
            BackgroundScene.nowPlaying,
            preferences.value.nowPlaying.copyWith(layeredMotion: false));
        await tester.pumpAndSettle();
        expect(toggle, findsNothing,
            reason: 'Gentle drift does not use the reactive flow renderer');
        preferences.value = preferences.value.withScene(
            BackgroundScene.nowPlaying,
            preferences.value.nowPlaying.copyWith(layeredMotion: true));
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(toggle), alignment: 1);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('DAN_NATIVE_LYRIC_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            await File(
                    '$output/bass-settings-${language.name}-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        preferences.value = preferences.value.withScene(
            BackgroundScene.nowPlaying,
            preferences.value.nowPlaying.copyWith(motion: false));
        await tester.pumpAndSettle();
        expect(toggle, findsNothing);
        expect(preferences.value.nowPlaying.bassReactive, isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
      'animation bulk controls include bass response without changing unrelated scenes',
      (tester) async {
    final settings = AppSettings.instance;
    final rendering = settings.rendering.value;
    final backgrounds = settings.backgrounds.value;
    final experience = settings.experience.value;
    addTearDown(() {
      settings.rendering.value = rendering;
      settings.backgrounds.value = backgrounds;
      settings.experience.value = experience;
    });
    settings.backgrounds.value = const BackgroundPreferences();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AnimationSettings(persist: () async {})))));
    await tester.tap(find.byKey(const ValueKey('animations-all-on')));
    await tester.pumpAndSettle();
    expect(settings.backgrounds.value.nowPlaying.bassReactive, isTrue);
    expect(settings.backgrounds.value.main.bassReactive, isFalse);
    await tester.tap(find.byKey(const ValueKey('animations-all-off')));
    await tester.pumpAndSettle();
    expect(settings.backgrounds.value.nowPlaying.bassReactive, isFalse);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
