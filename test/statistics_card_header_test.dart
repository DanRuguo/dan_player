import 'package:dan_player/component/app_control_theme.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/component/statistics_card_header.dart';
import 'package:desktop_lyric/font_loader.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => ensureAppFontsLoaded(AppFontPolicy.defaults()));
  for (final language in UiLanguage.values) {
    testWidgets(
        '${language.code} statistics header uses real widths and keeps children',
        (tester) async {
      final previous = uiLanguage.value;
      uiLanguage.value = language;
      addTearDown(() => uiLanguage.value = previous);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const titleKey = ValueKey('header-title');
      const controlsKey = ValueKey('header-controls');
      Element? titleElement;
      Element? controlsElement;
      var clicks = 0;
      for (final layout in [(1100.0, 1.0), (360.0, 2.0), (1100.0, 1.0)]) {
        tester.view.physicalSize = Size(layout.$1, 1000);
        final policy = AppFontPolicy.defaults(language: language);
        await tester.pumpWidget(MaterialApp(
            locale: language.locale,
            supportedLocales: UiLanguage.values.map((item) => item.locale),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: applyAppControlTheme(ThemeData(
                fontFamily: policy.uiFamily,
                fontFamilyFallback: danFontFamilyFallback)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(layout.$2)),
                child: AppFontScope(policy: policy, child: child!)),
            home: Scaffold(
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: StatisticsCardHeader(
                                title: Row(key: titleKey, children: [
                                  const SizedBox(width: 24, height: 24),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(ui('缓存与播放器数据占用'),
                                          style:
                                              const TextStyle(fontSize: 16))),
                                ]),
                                controls: LayoutBuilder(
                                    builder: (context, constraints) => Wrap(
                                            key: controlsKey,
                                            alignment: WrapAlignment.end,
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final label in [
                                                '缓存与播放器数据',
                                                '播放器目录'
                                              ])
                                                TextButton(
                                                    onPressed: () => clicks++,
                                                    child: ConstrainedBox(
                                                        constraints: BoxConstraints(
                                                            maxWidth: constraints
                                                                    .maxWidth -
                                                                40),
                                                        child: Text(ui(label),
                                                            softWrap: true))),
                                            ])))))))));
        await tester.pumpAndSettle();
        final title = tester.getRect(find.byKey(titleKey));
        final controls = tester.getRect(find.byKey(controlsKey));
        expect(title.left, closeTo(34, .1));
        expect(controls.right, closeTo(layout.$1 - 34, .1));
        if (layout.$1 == 1100) {
          expect(title.center.dy, closeTo(controls.center.dy, .1));
          expect(title.right + 12, lessThanOrEqualTo(controls.left + .1));
        } else {
          expect(controls.top, closeTo(title.bottom + 12, .1));
        }
        for (final label in ['缓存与播放器数据占用', '缓存与播放器数据', '播放器目录']) {
          final text = find.text(ui(label));
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse);
          final bounds = label.endsWith('占用') ? title : controls;
          for (final run in RegExp(r'\S+').allMatches(ui(label))) {
            for (final box in paragraph.getBoxesForSelection(
                TextSelection(baseOffset: run.start, extentOffset: run.end))) {
              final glyph = MatrixUtils.transformRect(
                  paragraph.getTransformTo(null), box.toRect());
              expect(bounds.inflate(.5).contains(glyph.topLeft), isTrue);
              expect(bounds.inflate(.5).contains(glyph.bottomRight), isTrue);
            }
          }
        }
        if (titleElement == null) {
          titleElement = tester.element(find.byKey(titleKey));
          controlsElement = tester.element(find.byKey(controlsKey));
        } else {
          expect(tester.element(find.byKey(titleKey)), same(titleElement));
          expect(
              tester.element(find.byKey(controlsKey)), same(controlsElement));
        }
        await tester.tap(find.text(ui('播放器目录')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(clicks, 3);
    });
  }
}
