import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/category_display_controls.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'submenu_layout_regression_test.dart' show panelRect;
import 'support/playlist_feature_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);
  for (final language in UiLanguage.values) {
    testWidgets(
        'compact category sort and pitch use app theme ${language.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      uiLanguage.value = language;
      final boundary = GlobalKey();
      var presentation = const CategoryPresentation();
      final theme = Entry(welcome: false).fromSchemeAndFontFamily(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.amber, brightness: Brightness.dark));
      await tester.pumpWidget(UiLanguageScope(
          child: MaterialApp(
        theme: theme,
        locale: language.locale,
        supportedLocales: UiLanguage.values.map((v) => v.locale),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => RepaintBoundary(
          key: boundary,
          child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  disableAnimations: true,
                  textScaler: const TextScaler.linear(1.75)),
              child: child!),
        ),
        home: Scaffold(
            body: Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                    alignment: Alignment.bottomLeft,
                    child: StatefulBuilder(builder: (context, update) {
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        CategoryDisplayControls(
                            value: presentation,
                            onChanged: (value) =>
                                update(() => presentation = value),
                            search: const TextField()),
                        PlaybackRateMenu(
                            rate: 1.25,
                            onSelected: (_) {},
                            onPitchSelected: (_) {}),
                      ]);
                    })))),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(ui('分类显示选项')));
      await tester.pumpAndSettle();
      final sort = find.widgetWithText(SubmenuButton, ui('排序'));
      await tester.ensureVisible(sort);
      await tester.tap(sort);
      await tester.pumpAndSettle();
      final name = find.widgetWithText(MenuItemButton, ui('名称'));
      final panel = panelRect(tester, name);
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(360));
      await capturePlaylistFeature(
          tester, boundary, 'category-sort-app-theme-${language.name}');
      await tester.ensureVisible(name);
      await tester.tap(name);
      await tester.pumpAndSettle();
      expect(presentation.sort, CategorySort.name);

      await tester.tap(find.byKey(const ValueKey('playback-rate-menu')));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('playback-pitch-submenu'));
      await tester.ensureVisible(trigger);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final down = find.byKey(const ValueKey('playback-pitch-step-down'));
      final pitchPanel = panelRect(tester, down);
      expect(pitchPanel.bottom, closeTo(tester.getRect(trigger).bottom, .01));
      for (final text in find
          .descendant(of: down, matching: find.byType(RichText))
          .evaluate()) {
        final paragraph = text.renderObject! as RenderParagraph;
        final boxes = paragraph.getBoxesForSelection(TextSelection(
            baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
        for (final box in boxes) {
          final rect = MatrixUtils.transformRect(
              paragraph.getTransformTo(null), box.toRect());
          expect(rect.left, greaterThanOrEqualTo(pitchPanel.left));
          expect(rect.right, lessThanOrEqualTo(pitchPanel.right));
        }
      }
      await capturePlaylistFeature(
          tester, boundary, 'pitch-app-theme-${language.name}');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
