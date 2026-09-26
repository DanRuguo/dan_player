import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/page/settings_page/custom_music_source_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

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
      testWidgets('${language.name} source actions align and wrap at $narrow',
          (tester) async {
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = UiLanguage.zh);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 1400 : 760);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final profiles = ValueNotifier([
          for (final name in ['first', 'second'])
            CustomMusicSourceProfile.tryCreate(
                id: name,
                name: name,
                baseUrl: 'https://example.com',
                capabilities: const {
                  CustomMusicSourceCapability.search
                },
                endpoints: {
                  CustomMusicSourceCapability.search:
                      'https://example.com/search'
                })!,
        ]);
        addTearDown(profiles.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applyAppControlTheme(ThemeData(
              fontFamily: danEmbeddedFontFamily,
              fontFamilyFallback: danFontFamilyFallback,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: narrow ? Brightness.dark : Brightness.light))),
          builder: (context, child) => UiLanguageScope(
              child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(narrow ? 2 : 1),
                      disableAnimations: true),
                  child: child!)),
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    CustomMusicSourceSettings(
                        profiles: profiles, persist: () async {}),
                  ]))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (!narrow) {
          final centers = [
            for (final icon in [
              Symbols.arrow_upward,
              Symbols.arrow_downward,
              Symbols.network_check,
              Symbols.edit,
              Symbols.delete
            ])
              tester
                  .getCenter(find.descendant(
                      of: find
                          .byKey(const ValueKey('custom-source-profile-first')),
                      matching: find.byIcon(icon)))
                  .dy,
          ];
          for (final y in centers) {
            expect(y, closeTo(centers.first, 1));
          }
        }
        const output = String.fromEnvironment('DAN_SOURCE_ACTION_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: drawing.ImageByteFormat.png);
            final file = File(
                '$output/${language.name}-${narrow ? 'narrow' : 'wide'}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
