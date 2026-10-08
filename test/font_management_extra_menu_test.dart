import 'dart:io';
import 'dart:ui' as raster;

import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/font/app_font_manager.dart';
import 'package:dan_player/page/settings_page/font_management_dialog.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _capture(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final directory = Platform.environment['DAN_FONT_EXTRA_RENDER_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final image = await (boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary)
        .toImage();
    try {
      final data = await image.toByteData(format: raster.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(() async {
    await ensureAppFontsLoaded(AppFontPolicy.defaults());
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final language in UiLanguage.values) {
    testWidgets(
        'font slot menu retains complete ${language.code} glyphs at 200%',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final policy = AppFontPolicy.defaults(language: language);
      final manager = AppFontManager(load: (_) async {});
      addTearDown(manager.dispose);
      var enumerations = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
              locale: language.locale,
              supportedLocales: UiLanguage.values.map((value) => value.locale),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: applyAppControlTheme(ThemeData(
                  fontFamily: policy.uiFamily,
                  fontFamilyFallback: danFontFamilyFallback,
                  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal))),
              builder: (context, child) => RepaintBoundary(
                  key: boundary,
                  child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(2)),
                      child: AppFontScope(policy: policy, child: child!))),
              home: Scaffold(
                  body: FontManagementDialog(
                      manager: manager,
                      getFonts: () async {
                        enumerations++;
                        return [];
                      })))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('font-slot-en')));
      await tester.tap(find.byKey(const ValueKey('font-slot-en')));
      await tester.pumpAndSettle();
      await _capture(tester, boundary, 'font-menu-${language.code}-360-2x');
      for (final label in [
        ui('思源黑体 SC'),
        'Google Sans',
        ui('思源黑体 JP'),
        'Pretendard',
        ui('选择已安装字体'),
      ]) {
        final row = find.widgetWithText(MenuItemButton, label);
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(row.hitTestable(), findsOneWidget);
        final panel = tester.getRect(find
            .ancestor(
                of: row,
                matching: find.byWidgetPredicate((widget) =>
                    widget is Material && widget.type == MaterialType.canvas))
            .first);
        final viewport = tester.getRect(find.byKey(boundary));
        expect(panel.left, greaterThanOrEqualTo(viewport.left - .1));
        expect(panel.right, lessThanOrEqualTo(viewport.right + .1),
            reason: 'The menu must stay inside the actual window');
        final text = find.descendant(of: row, matching: find.text(label));
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        for (final run in RegExp(r'\S+').allMatches(label)) {
          final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: run.start, extentOffset: run.end));
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            final bounds = MatrixUtils.transformRect(
                paragraph.getTransformTo(null), box.toRect());
            expect(bounds.left, greaterThanOrEqualTo(panel.left - .1));
            expect(bounds.right, lessThanOrEqualTo(panel.right + .1),
                reason: 'The actual menu must paint the complete $label');
            expect(bounds.top, greaterThanOrEqualTo(panel.top - .1));
            expect(bounds.bottom, lessThanOrEqualTo(panel.bottom + .1));
          }
        }
      }
      await tester.tap(find.widgetWithText(MenuItemButton, ui('选择已安装字体')));
      await tester.pumpAndSettle();
      expect(enumerations, 1);
      expect(find.text(ui('无法获取字体')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
