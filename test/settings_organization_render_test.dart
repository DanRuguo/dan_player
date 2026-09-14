import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      testWidgets('theme organization ${language.code} narrow=$narrow',
          (tester) async {
        final previous = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previous);
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 2500 : 850);
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
                          child: Text(ui('界面与主题'),
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w600))),
                      InterfaceSettings(
                          group: InterfaceSettingsGroup.language,
                          persist: () async {}),
                      const SizedBox(height: 16),
                      const ThemeAppearanceSettings(),
                      const SizedBox(height: 16),
                      const SelectFontCombobox(),
                    ])),
          ))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.binding.hasScheduledFrame, isFalse);
        const output =
            String.fromEnvironment('DAN_SETTINGS_ORGANIZATION_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
            await Directory(output).create(recursive: true);
            await File('$output/theme-${language.code}-$narrow.png')
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
