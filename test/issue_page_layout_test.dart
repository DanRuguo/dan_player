import 'dart:io';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/settings_page/create_issue.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const output = String.fromEnvironment('DAN_ISSUE_RENDER');
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
    testWidgets(
        'issue form remains editable in a short large-text window ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(440, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      final capture = GlobalKey();
      Future<void> render(String stage) async {
        if (output.isEmpty) return;
        await tester.pump();
        await tester.runAsync(() async {
          final image = await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final data =
              await image.toByteData(format: drawing.ImageByteFormat.png);
          final file = File('$output/issue-${language.name}-$stage.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(
                    seedColor: Colors.teal,
                    brightness: language.index.isEven
                        ? Brightness.light
                        : Brightness.dark)),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true),
              child: UiLanguageScope(child: child!),
            ),
            home: const Scaffold(body: SettingsIssuePage()),
          )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await render('top');
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      for (var index = 0; index < 3; index++) {
        await tester.ensureVisible(fields.at(index));
        await tester.pumpAndSettle();
        await tester.enterText(fields.at(index), 'Draft $index');
        expect(tester.widget<TextField>(fields.at(index)).controller!.text,
            'Draft $index');
        expect(tester.takeException(), isNull);
      }
      await render('bottom');
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
