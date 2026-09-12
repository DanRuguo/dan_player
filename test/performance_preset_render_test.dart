import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/performance_preset_settings.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
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
  for (final language in UiLanguage.values) {
    for (final width in [360.0, 1000.0]) {
      testWidgets('preset ${language.code} width=$width', (tester) async {
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var live = PerformanceSnapshot.capture(
            const RenderingPreferences(),
            const BackgroundPreferences(),
            const PlayerExperiencePreferences(),
            true);
        final controller = PerformancePresetController(
            capture: () => live, apply: (v) => live = v, persist: () async {});
        addTearDown(controller.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: const ['Malgun Gothic'],
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.teal,
                  brightness:
                      width < 400 ? Brightness.light : Brightness.dark))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width < 400 ? 1.7 : 1)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: RepaintBoundary(
                          key: key,
                          child: PerformancePresetSettings(
                              controller: controller))))),
        )));
        await tester.pumpAndSettle();
        for (final mode in PerformanceMode.values) {
          tester
              .widget<AppSegmentedControl<PerformanceMode>>(
                  find.byKey(const ValueKey('performance-preset')))
              .onChanged!(mode);
          await tester.pumpAndSettle();
          expect(controller.value.mode, mode);
          expect(tester.takeException(), isNull);
          const output = String.fromEnvironment('DAN_PRESET_RENDER');
          if (output.isNotEmpty) {
            await tester.runAsync(() async {
              final image = await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
              await Directory(output).create(recursive: true);
              await File('$output/${language.code}-$width-${mode.name}.png')
                  .writeAsBytes((await image.toByteData(
                          format: drawing.ImageByteFormat.png))!
                      .buffer
                      .asUint8List());
              image.dispose();
            });
          }
        }
      });
    }
  }
}
