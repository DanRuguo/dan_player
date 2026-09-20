import 'dart:io';
import 'package:dan_player/component/app_fonts.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as drawing;
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/page/settings_page/background_settings.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  for (final language in UiLanguage.values) {
    for (final brightness in Brightness.values) {
      testWidgets('layered setting ${language.name} ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(520, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        final preferences = ValueNotifier(const BackgroundPreferences(
            nowPlaying: BackgroundAppearance(
                source: BackgroundSource.artwork, motion: true)));
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
                                    onSave: () async => saves++))))))));
        expect(find.byKey(const ValueKey('background-layered-true')),
            findsNothing);
        await tester
            .tap(find.byKey(const ValueKey('background-scene-nowPlaying')));
        await tester.pumpAndSettle();
        final drift = find.byKey(const ValueKey('background-layered-false'));
        await tester.ensureVisible(drift);
        await tester.tap(drift);
        await tester.pumpAndSettle();
        expect(preferences.value.nowPlaying.layeredMotion, isFalse);
        expect(preferences.value.main.layeredMotion, isTrue);
        expect(saves, 1);
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
                    '$output/settings-${language.name}-${brightness.name}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        preferences.value = preferences.value.withScene(
            BackgroundScene.nowPlaying,
            preferences.value.nowPlaying.copyWith(motion: false));
        await tester.pumpAndSettle();
        expect(drift, findsNothing);
        expect(preferences.value.nowPlaying.layeredMotion, isFalse);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
