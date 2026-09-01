import 'dart:math' as math;

import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/page/categories_page.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _viewport(WidgetTester tester,
    {required double width, double height = 700}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
}

Widget _host({double scale = 1}) => UiLanguageScope(
      child: MaterialApp(
        theme: ThemeData(
          platform: TargetPlatform.windows,
          visualDensity: VisualDensity.compact,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: const Scaffold(body: CategoriesPage(audios: [])),
      ),
    );

void main() {
  tearDown(() {
    uiLanguage.value = UiLanguage.zh;
  });

  testWidgets('wide category header gives unused title space to the selector',
      (tester) async {
    _viewport(tester, width: 1440);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();

      final title = tester.getRect(find.text(ui('分类')));
      final subtitle = tester.getRect(find.text(ui('{0} 首歌曲 · {1} {2}',
          [0, 0, ui(MusicCategoryKind.artist.countLabel)])));
      final selector =
          tester.getRect(find.byKey(const ValueKey('category-kind-scroll')));
      final identityRight = math.max(title.right, subtitle.right);

      expect(selector.left - identityRight, closeTo(20, .01),
          reason: '${language.name} should not leave a flexible middle gap');
      expect(selector.right, closeTo(1408, .01));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('four languages stay usable in the 200 percent narrow header',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [320.0, 507.0]) {
      _viewport(tester, width: width, height: 507);
      for (final language in UiLanguage.values) {
        uiLanguage.value = language;
        await tester.pumpWidget(_host(scale: 2));
        await tester.pumpAndSettle();

        final selector = find.byKey(const ValueKey('category-kind-scroll'));
        final selectorRect = tester.getRect(selector);
        final search =
            tester.getRect(find.byKey(const ValueKey('category-search')));
        final scrollbar = tester.widget<Scrollbar>(find
            .ancestor(of: selector, matching: find.byType(Scrollbar))
            .first);

        expect(find.byType(ChoiceChip), findsNWidgets(7));
        expect(selectorRect.width, lessThanOrEqualTo(width - 64));
        expect(selectorRect.height, greaterThanOrEqualTo(44));
        expect(search.left, greaterThanOrEqualTo(24));
        expect(search.right, lessThanOrEqualTo(width - 24));
        expect(search.height, greaterThanOrEqualTo(44));
        expect(scrollbar.thumbVisibility, isTrue);
        expect(scrollbar.interactive, isTrue);
        expect(tester.takeException(), isNull,
            reason: '${language.name} at ${width.toInt()}px');
      }
    }
  });
}
