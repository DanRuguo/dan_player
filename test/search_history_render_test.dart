import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/page/search_page/search_page.dart';
import 'support/search_history_fixture.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/gestures.dart';
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
    await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
          ..addFont(rootBundle.load(
              'packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
        .load();
    for (final entry in {
      'Malgun Gothic': 'malgun.ttf',
      'Segoe UI Emoji': 'seguiemj.ttf'
    }.entries) {
      final file = File('C:/Windows/Fonts/${entry.value}');
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  for (final language in UiLanguage.values) {
    testWidgets(
        'render ${language.name} real font centers history labels and delete mark',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = UiLanguage.zh);
      final history = MemorySearchHistory();
      addTearDown(history.dispose);
      const queries = [
        '春日影',
        '夜に駆ける',
        '다시 만날 그날까지',
        'Hotel California',
        '周杰伦 晴天',
        'L’été 🎶',
        'A very long song title / 長い曲名を最後まで保存して検索できます / 아주 긴 노래 제목'
      ];
      await tester.runAsync(() async {
        for (final query in queries) {
          await history.record(query, capacity: (_) => 12);
        }
      });
      final boundary = GlobalKey();
      final theme = applyAppControlTheme(ThemeData(
        fontFamily: danEmbeddedFontFamily,
        fontFamilyFallback: danFontFamilyFallback,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: language == UiLanguage.zh || language == UiLanguage.ko
                ? Brightness.dark
                : Brightness.light),
        visualDensity: VisualDensity.compact,
      ));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: UiLanguageScope(
              child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(body: SearchPage(history: history))))));
      await tester.pumpAndSettle();
      // Remove the editing caret from visual comparisons.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      Future<ui.Image> capture(String stage) async {
        final image = await tester.runAsync(() => (boundary.currentContext!
                .findRenderObject() as RenderRepaintBoundary)
            .toImage());
        const output = String.fromEnvironment('DAN_SEARCH_RENDER');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final bytes =
                await image!.toByteData(format: ui.ImageByteFormat.png);
            final file = File('$output/${language.name}-$stage.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        return image!;
      }

      (await capture('normal')).dispose();
      final target = find.byKey(const ValueKey(('search-history', '春日影')));
      final before = tester.getRect(target);
      await tester.tap(target,
          buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.getRect(target), before);
      final image = await capture('delete');
      final pixels = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      final foreground = theme.colorScheme.onPrimary;
      final expected = [
        foreground.r * 255,
        foreground.g * 255,
        foreground.b * 255
      ];
      int? left, top, right, bottom;
      for (var y = before.top.ceil() + 5; y < before.bottom.floor() - 5; y++) {
        for (var x = before.left.ceil() + 12;
            x < before.right.floor() - 12;
            x++) {
          final offset = (y * image.width + x) * 4;
          if (List.generate(
                  3, (i) => (pixels.getUint8(offset + i) - expected[i]).abs())
              .every((d) => d < 35)) {
            left = left == null || x < left ? x : left;
            right = right == null || x > right ? x : right;
            top = top == null || y < top ? y : top;
            bottom = bottom == null || y > bottom ? y : bottom;
          }
        }
      }
      image.dispose();
      expect(left, isNotNull);
      expect((left! + right! + 1) / 2, closeTo(before.center.dx, 1.2));
      expect((top! + bottom! + 1) / 2, closeTo(before.center.dy, 1.2));
      tester.view.physicalSize = const Size(360, 470);
      await tester.pumpAndSettle();
      (await capture('narrow')).dispose();
      expect(tester.takeException(), isNull);
    });
  }
}
