import 'dart:io';
import 'dart:ui' as drawing;
import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/feature_onboarding.dart';
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
      testWidgets('${language.code} interactive tour narrow=$narrow',
          (tester) async {
        final previousLanguage = uiLanguage.value;
        uiLanguage.value = language;
        addTearDown(() => uiLanguage.value = previousLanguage);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            Size(narrow ? 360 : 1000, narrow ? 760 : 740);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var completions = 0;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(UiLanguageScope(
            child: MaterialApp(
          theme: applyAppControlTheme(ThemeData(
            fontFamily: danEmbeddedFontFamily,
            fontFamilyFallback: const ['Malgun Gothic'],
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: narrow ? Brightness.light : Brightness.dark),
          )),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(narrow ? 1.7 : 1)),
              child: child!),
          home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                  body: FeatureOnboarding(onComplete: () => completions++))),
        )));
        await tester.pumpAndSettle();
        for (var step = 0; step < 3; step++) {
          expect(
              find.byKey(ValueKey('onboarding-preview-$step')), findsOneWidget);
          expect(tester.takeException(), isNull);
          const renderRoot = String.fromEnvironment('DAN_ONBOARDING_RENDER');
          if (renderRoot.isNotEmpty) {
            await tester.runAsync(() async {
              final boundary = boundaryKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
              final image = await boundary.toImage();
              try {
                final bytes = (await image.toByteData(
                    format: drawing.ImageByteFormat.png))!;
                await Directory(renderRoot).create(recursive: true);
                await File(
                        '$renderRoot/${language.code}-${narrow ? 'narrow' : 'wide'}-$step.png')
                    .writeAsBytes(bytes.buffer.asUint8List());
              } finally {
                image.dispose();
              }
            });
          }
          if (step == 0) {
            await tester
                .ensureVisible(find.byKey(const ValueKey('onboarding-play')));
            await tester.tap(find.byKey(const ValueKey('onboarding-play')));
            await tester.pumpAndSettle();
            expect(find.widgetWithText(FilledButton, ui('暂停')), findsOneWidget);
          }
          if (step == 1) {
            final tag = find.widgetWithText(FilterChip, ui('喜欢的音乐'));
            await tester.ensureVisible(tag);
            await tester.tap(tag);
            await tester.pumpAndSettle();
            expect(tester.widget<FilterChip>(tag).selected, isTrue);
          }
          if (step == 2) {
            final purple = find.widgetWithText(ChoiceChip, ui('紫色'));
            await tester.ensureVisible(purple);
            await tester.tap(purple);
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(purple).selected, isTrue);
          }
          await tester.tap(find.byKey(const ValueKey('onboarding-next')));
          await tester.pumpAndSettle();
        }
        expect(completions, 1);
        await tester.tap(find.text(ui('跳过引导')));
        expect(completions, 2);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
