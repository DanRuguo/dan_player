import 'dart:io';
import 'dart:ui' as ui;
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(danEmbeddedFontFamily)
          ..addFont(rootBundle.load('assets/fonts/PingFangSC-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final korean = File('C:/Windows/Fonts/malgun.ttf');
    if (await korean.exists()) {
      await (FontLoader('Malgun Gothic')
            ..addFont(
                Future.value(ByteData.sublistView(await korean.readAsBytes()))))
          .load();
    }
  });
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final language in UiLanguage.values) {
    for (final dark in [false, true]) {
      testWidgets('component setup layout ${language.name} dark=$dark',
          (tester) async {
        uiLanguage.value = language;
        tester.view.physicalSize = const Size(720, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                fontFamily: danEmbeddedFontFamily,
                fontFamilyFallback: const ['Malgun Gothic'],
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal,
                    brightness: dark ? Brightness.dark : Brightness.light)),
            home: Scaffold(
                body: RepaintBoundary(
                    key: boundary,
                    child: Center(
                        child: SizedBox(
                            width: 540,
                            child: SingleChildScrollView(
                                child: FfmpegSetupCard(onReady: () {}))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(find.byType(OutlinedButton), findsOneWidget);
        const output = String.fromEnvironment('DAN_MODULE_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            await File('$output/setup-${language.name}-$dark.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      });
    }
  }
}
