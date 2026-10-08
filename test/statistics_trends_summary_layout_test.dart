import 'package:dan_player/component/statistics_listening_trends.dart';
import 'package:dan_player/statistics/listening_calendar.dart';
import 'package:dan_player/statistics/listening_trends.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

ListeningTrendsSnapshot _snapshot({bool hasPrevious = true}) =>
    ListeningTrendsSnapshot.fromDaily(dailyMilliseconds: {
      for (var offset = 1; offset <= 14; offset++)
        listeningDayKey(DateTime(2026, 10, 8 - offset)): offset <= 7
            ? (8 - offset) * 3600000
            : hasPrevious
                ? (15 - offset) * 1800000
                : 0,
    }, capturedAt: DateTime(2026, 10, 8, 12));

Finder _metric(String label) => find
    .ancestor(
        of: find.text(ui(label), skipOffstage: false),
        matching: find.byType(DecoratedBox, skipOffstage: false))
    .first;

void _expectCompleteText(WidgetTester tester, Finder metric) {
  final rect = tester.getRect(metric);
  final texts = find.descendant(
      of: metric,
      matching: find.byType(Text, skipOffstage: false),
      skipOffstage: false);
  for (final text in texts.evaluate()) {
    final finder = find.byElementPredicate(
        (element) => identical(element, text),
        skipOffstage: false);
    final widget = text.widget as Text;
    final value = widget.data ?? widget.textSpan!.toPlainText();
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
        of: finder,
        matching: find.byType(RichText, skipOffstage: false),
        skipOffstage: false));
    expect(paragraph.text.toPlainText(), value);
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: value.length));
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final glyph = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
      expect(glyph.left, greaterThanOrEqualTo(rect.left - 1));
      expect(glyph.right, lessThanOrEqualTo(rect.right + 1));
      expect(glyph.top, greaterThanOrEqualTo(rect.top - 1));
      expect(glyph.bottom, lessThanOrEqualTo(rect.bottom + 1));
    }
  }
}

void _expectSummary(WidgetTester tester, {required bool wide}) {
  final metrics = [
    _metric('本期收听'),
    _metric('相比前期'),
    _metric('活跃日期'),
  ];
  final rects = metrics.map(tester.getRect).toList();
  final firstTexts = find.descendant(
      of: metrics.first,
      matching: find.byType(Text, skipOffstage: false),
      skipOffstage: false);
  expect(firstTexts, findsNWidgets(2),
      reason: 'Do not manufacture a detail or blank line for equal sizing');
  if (wide) {
    for (final rect in rects.skip(1)) {
      expect(rect.top, closeTo(rects.first.top, .01));
      expect(rect.bottom, closeTo(rects.first.bottom, .01),
          reason: 'Actual same-row metric surfaces must share their bottom');
      expect(rect.height, closeTo(rects.first.height, .01));
    }
    expect(rects[1].left, closeTo(rects[0].right + 12, .01));
    expect(rects[2].left, closeTo(rects[1].right + 12, .01));
  } else {
    for (var index = 1; index < rects.length; index++) {
      expect(rects[index].left, closeTo(rects.first.left, .01));
      expect(rects[index].right, closeTo(rects.first.right, .01));
      expect(rects[index].top, closeTo(rects[index - 1].bottom + 10, .01));
    }
    expect(rects.first.height, lessThan(rects[1].height),
        reason: 'Stacked metrics retain their individual natural content size');
  }
  for (final metric in metrics) {
    _expectCompleteText(tester, metric);
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final previous = uiLanguage.value;
    addTearDown(() => uiLanguage.value = previous);
  });

  Future<void> mount(WidgetTester tester,
      {required UiLanguage language,
      required bool wide,
      required double scale,
      bool hasPrevious = true,
      GlobalKey? boundary}) async {
    uiLanguage.value = language;
    sizePlaylistFeature(tester,
        width: wide ? (scale == 2 ? 1800 : 1080) : 360, height: 1200);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: StatisticsListeningTrends(
                    snapshot: _snapshot(hasPrevious: hasPrevious)))),
        scale: scale,
        boundary: boundary));
    await tester.pumpAndSettle();
  }

  for (final language in UiLanguage.values) {
    for (final wide in [true, false]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'trend summary ${language.code} ${wide ? 'wide' : 'narrow'} ${scale.toInt()}x aligns natural cards',
            (tester) async {
          final boundary = GlobalKey();
          await mount(tester,
              language: language, wide: wide, scale: scale, boundary: boundary);
          _expectSummary(tester, wide: wide);
          await tester.ensureVisible(_metric('本期收听'));
          await tester.pumpAndSettle();
          await captureListeningStatus(tester, boundary,
              'trends-summary-${language.code}-${wide ? 'wide' : 'narrow'}-${scale.toInt()}x');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.binding.transientCallbackCount, 0);
        });
      }
    }
  }
  testWidgets(
      'wide 200 percent summaries follow the tallest translated explanation',
      (tester) async {
    final boundary = GlobalKey();
    await mount(tester,
        language: UiLanguage.en,
        wide: true,
        scale: 2,
        hasPrevious: false,
        boundary: boundary);
    final explanation = find.text(ui('前期无收听记录，不计算百分比。'));
    expect(explanation, findsOneWidget);
    _expectSummary(tester, wide: true);
    await captureListeningStatus(
        tester, boundary, 'trends-summary-en-wide-2x-no-previous');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
