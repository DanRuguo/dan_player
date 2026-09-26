import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    for (final font in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf'
    }.entries) {
      final file = File('C:/Windows/Fonts/${font.value}');
      if (await file.exists()) {
        await (FontLoader(font.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });
  for (final language in UiLanguage.values) {
    for (final width in [900.0, 320.0]) {
      testWidgets('local lyric options render ${language.name} at $width',
          (tester) async {
        final settings = AppSettings.instance;
        final originalOrder = settings.localLyricLineOrder;
        final originalStyle = settings.nowPlayingProgressStyle.value;
        final originalDensity = settings.waveformBarDensity.value;
        final previousLanguage = uiLanguage.value;
        uiLanguage.value = language;
        settings.localLyricLineOrder = LocalLyricLineOrder.automatic;
        settings.nowPlayingProgressStyle.value =
            NowPlayingProgressStyle.standard;
        settings.waveformBarDensity.value = WaveformBarDensity.automatic;
        addTearDown(() {
          settings.localLyricLineOrder = originalOrder;
          settings.nowPlayingProgressStyle.value = originalStyle;
          settings.waveformBarDensity.value = originalDensity;
          uiLanguage.value = previousLanguage;
        });
        tester.view.physicalSize = Size(width, width == 320 ? 2300 : 1300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = ValueNotifier(const PlayerExperiencePreferences());
        addTearDown(preferences.dispose);
        final boundary = GlobalKey();
        var saves = 0;
        await tester.pumpWidget(MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.orange, brightness: Brightness.dark))),
          home: UiLanguageScope(
              child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                      body: MediaQuery(
                          data: MediaQueryData(
                              size: tester.view.physicalSize,
                              textScaler:
                                  TextScaler.linear(width == 320 ? 1.4 : 1)),
                          child: SingleChildScrollView(
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: LyricExperienceSettings(
                                      preferences: preferences,
                                      persist: () async {
                                        saves++;
                                      }))))))),
        ));
        await tester.pumpAndSettle();
        expect(PlayService.isInitialized, isFalse);
        expect(saves, 0);
        expect(
            find.byKey(const ValueKey('waveform-bar-density')), findsNothing);
        expect(tester.takeException(), isNull);
        final root = Platform.environment['DAN_PLAYER_DATA_DIR']!;
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final bytes =
              (await image.toByteData(format: drawing.ImageByteFormat.png))!;
          await File(path.join(
                  root, 'settings-${language.name}-${width.toInt()}.png'))
              .writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        final order = tester.widget<AppSegmentedControl<LocalLyricLineOrder>>(
            find.byKey(const ValueKey('local-lyric-line-order')));
        order.onChanged!(LocalLyricLineOrder.romanizationOriginalTranslation);
        await tester.pumpAndSettle();
        expect(settings.localLyricLineOrder,
            LocalLyricLineOrder.romanizationOriginalTranslation);
        final progress =
            tester.widget<AppSegmentedControl<NowPlayingProgressStyle>>(
                find.byKey(const ValueKey('now-playing-progress-style')));
        progress.onChanged!(NowPlayingProgressStyle.waveform);
        await tester.pumpAndSettle();
        expect(settings.nowPlayingProgressStyle.value,
            NowPlayingProgressStyle.waveform);
        expect(saves, 2);
        final densityFinder =
            find.byKey(const ValueKey('waveform-bar-density'));
        expect(densityFinder, findsOneWidget);
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 1);
          final bytes =
              (await image.toByteData(format: drawing.ImageByteFormat.png))!;
          await File(path.join(root,
                  'settings-waveform-${language.name}-${width.toInt()}.png'))
              .writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
        await tester.ensureVisible(densityFinder);
        await tester.tap(find
            .descendant(
                of: densityFinder, matching: find.byType(OutlinedButton))
            .first);
        await tester.pumpAndSettle();
        expect(find.text(ui('密集')), findsOneWidget);
        expect(find.text(ui('少量')), findsOneWidget);
        await tester.tap(find.text(ui('密集')));
        await tester.pumpAndSettle();
        expect(settings.waveformBarDensity.value, WaveformBarDensity.dense);
        expect(saves, 3);
        progress.onChanged!(NowPlayingProgressStyle.standard);
        await tester.pumpAndSettle();
        expect(densityFinder, findsNothing);
        expect(settings.waveformBarDensity.value, WaveformBarDensity.dense);
        expect(PlayService.isInitialized, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
