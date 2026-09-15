import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/animation_settings.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'animation preferences tolerate legacy data and keep categories independent',
      () {
    expect(RenderingPreferences.fromMap({}).animations.allEnabled, isTrue);
    final value =
        const MotionPreferences().withKind(MotionKind.tracking, false);
    expect(value.allows(MotionKind.layout), isTrue);
    expect(value.allows(MotionKind.transitions), isTrue);
    final rendering = RenderingPreferences(animations: value);
    expect(RenderingPreferences.fromMap(rendering.toMap()), rendering);
    expect(MotionPreferences.fromMap({'tracking': 'false'}).allEnabled, isTrue);
    expect(value.all(false).allDisabled, isTrue);
    expect(value.all(true).allEnabled, isTrue);
  });
  testWidgets('bulk controls use existing settings and independent switches',
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
    var saves = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: SingleChildScrollView(child: AnimationSettings(persist: () async {
      saves++;
    })))));
    await tester.tap(find.byKey(const ValueKey('animations-all-off')));
    await tester.pumpAndSettle();
    expect(settings.rendering.value.animations.allDisabled, isTrue);
    expect(settings.rendering.value.lyricSpectrum, isFalse);
    expect(settings.rendering.value.compactSpectrum, isFalse);
    expect(settings.experience.value.springLyrics, isFalse);
    await tester.tap(find.byKey(const ValueKey('animations-all-on')));
    await tester.pumpAndSettle();
    expect(settings.rendering.value.animations.allEnabled, isTrue);
    expect(settings.rendering.value.lyricSpectrum, isTrue);
    final tracking = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('animation-tracking')));
    tracking.onChanged!(false);
    await tester.pumpAndSettle();
    expect(settings.rendering.value.animations.allows(MotionKind.tracking),
        isFalse);
    expect(
        settings.rendering.value.animations.allows(MotionKind.layout), isTrue);
    expect(settings.rendering.value.animations.allows(MotionKind.transitions),
        isTrue);
    expect(saves, 3);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
  setUpAll(() async {
    for (final font in [
      (danEmbeddedFontFamily, 'assets/fonts/PingFangSC-Regular.ttf'),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
      (
        'packages/material_symbols_icons/MaterialSymbolsOutlined',
        'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf'
      ),
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
    for (final narrow in [false, true]) {
      testWidgets('animation controls ${language.code} narrow=$narrow',
          (tester) async {
        final original = AppSettings.instance.rendering.value;
        addTearDown(() => AppSettings.instance.rendering.value = original);
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 4400 : 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: const ['Malgun Gothic'],
              colorScheme: ColorScheme.fromSeed(
                  seedColor: narrow ? Colors.indigo : Colors.deepOrange,
                  brightness: narrow ? Brightness.dark : Brightness.light))),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.8 : 1)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
                key: boundary,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(ui('背景与动效'),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w600))),
                      AnimationSettings(persist: () async {}),
                    ])),
          ))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        const output = String.fromEnvironment('DAN_ANIMATIONS_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(output).create(recursive: true);
            await File('$output/animations-${language.code}-$narrow.png')
                .writeAsBytes((await image.toByteData(
                        format: drawing.ImageByteFormat.png))!
                    .buffer
                    .asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
