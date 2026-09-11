import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/rendering_settings.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf')
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
  test('density persists and malformed/old settings retain original high count',
      () {
    for (final density in SpectrumDensity.values) {
      final prefs = RenderingPreferences(spectrumDensity: density);
      expect(RenderingPreferences.fromMap(prefs.toMap()), prefs);
      expect(prefs.copyWith(lyricSpectrum: false).spectrumDensity, density);
    }
    expect(
        RenderingPreferences.fromMap(const {'spectrumDensity': 'invalid'})
            .spectrumDensity,
        SpectrumDensity.high);
  });
  for (final language in UiLanguage.values) {
    for (final narrow in [false, true]) {
      testWidgets(
          '${language.code} frame and density settings layout narrow=$narrow',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        windowDisplayRate.value = 144;
        addTearDown(() {
          uiLanguage.value = previous;
          windowDisplayRate.value = null;
        });
        tester.view.physicalSize =
            Size(narrow ? 320 : 900, narrow ? 2400 : 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var prefs = const RenderingPreferences(
            frameRate: FrameRatePreference(mode: FrameRateMode.fixed, fps: 60));
        final key = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: const ['Malgun Gothic'],
              colorScheme: ColorScheme.fromSeed(
                  seedColor: narrow ? Colors.teal : Colors.pink,
                  brightness: narrow ? Brightness.light : Brightness.dark))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: RepaintBoundary(
                          key: key,
                          child: StatefulBuilder(
                              builder: (context, setState) => RenderingSettings(
                                  value: prefs,
                                  onChanged: (next) =>
                                      setState(() => prefs = next))))))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final control = tester.widget<AppSegmentedControl<SpectrumDensity>>(
            find.byKey(const ValueKey('spectrum-density')));
        control.onChanged!(SpectrumDensity.low);
        await tester.pumpAndSettle();
        expect(prefs.spectrumDensity, SpectrumDensity.low);
        const output = String.fromEnvironment('DAN_RENDERING_SETTINGS_RENDER');
        if (output.isNotEmpty) {
          final frameControl = tester.widget<AppSegmentedControl<FrameRateMode>>(
              find.byKey(const ValueKey('frame-rate-mode')));
          frameControl.onChanged!(FrameRateMode.adaptive);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(output).create(recursive: true);
            await File('$output/${language.code}-$narrow.png').writeAsBytes(
                (await image.toByteData(format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
