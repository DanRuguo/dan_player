import 'dart:io';

import 'package:dan_player/category_presentation.dart';
import 'package:dan_player/component/app_sort_button.dart';
import 'package:dan_player/component/category_display_controls.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/page/now_playing_page/component/current_playlist_view.dart';
import 'package:dan_player/play_service/queue_order.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';
import 'support/playlist_feature_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

class _SortPlayback extends PlaylistFeaturePlayback {
  _SortPlayback()
      : super([
          CategoryTestAudio('Active'),
          CategoryTestAudio('Zulu'),
          CategoryTestAudio('Alpha')
        ]);

  var reversals = 0;
  final arrangements = <UpcomingQueueOrder>[];

  @override
  bool orderUpcomingQueue({AudioSortField? field, bool reverse = false}) {
    if (reverse) reversals++;
    return true;
  }

  @override
  bool arrangeUpcomingQueue(UpcomingQueueOrder order) {
    arrangements.add(order);
    return true;
  }
}

Widget _host(Widget child, GlobalKey boundary, double scale) {
  final themed = playlistFeatureHost(child) as MaterialApp;
  return UiLanguageScope(
      child: MaterialApp(
    theme: themed.theme,
    locale: uiLanguage.value.locale,
    supportedLocales: UiLanguage.values.map((language) => language.locale),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: true, textScaler: TextScaler.linear(scale)),
            child: child!)),
    home: Scaffold(body: child),
  ));
}

Rect _panelRect(WidgetTester tester, Finder row) => tester.getRect(find
    .ancestor(
        of: row,
        matching: find.byWidgetPredicate((widget) =>
            widget is Material && widget.type == MaterialType.canvas))
    .first);

void _expectPanel(WidgetTester tester, Finder row, Finder trigger,
    double viewportWidth, double viewportHeight) {
  final panel = _panelRect(tester, row);
  final anchor = tester.getRect(trigger);
  expect(panel.width, lessThanOrEqualTo(appSortMenuMaxWidth + .01));
  expect(panel.left, greaterThanOrEqualTo(-.01));
  expect(panel.right, lessThanOrEqualTo(viewportWidth + .01));
  expect(panel.top, greaterThanOrEqualTo(-.01));
  expect(panel.bottom, lessThanOrEqualTo(viewportHeight + .01));
  if (anchor.bottom - panel.height >= 0) {
    expect(panel.bottom, closeTo(anchor.bottom, .01),
        reason: 'enough space above preserves bottom attachment');
  } else if (anchor.top + panel.height <= viewportHeight) {
    expect(panel.top, closeTo(anchor.top, .01),
        reason: 'top attachment applies when bottom alignment would overflow');
  }
}

Future<void> _expectFullLabel(
    WidgetTester tester, Finder row, String label) async {
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  expect(row.hitTestable(), findsOneWidget);
  final text = find.descendant(of: row, matching: find.text(ui(label)));
  expect(text, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)).first);
  expect(paragraph.didExceedMaxLines, isFalse,
      reason: 'sort labels wrap without dropping characters');
  final panel = _panelRect(tester, row);
  final rowBounds = tester.getRect(row);
  final paragraphBounds = MatrixUtils.transformRect(
      paragraph.getTransformTo(null), Offset.zero & paragraph.size);
  expect(paragraphBounds.left, greaterThanOrEqualTo(rowBounds.left - .1));
  expect(paragraphBounds.right, lessThanOrEqualTo(rowBounds.right + .1));
  expect(paragraphBounds.top, greaterThanOrEqualTo(rowBounds.top - .1));
  expect(paragraphBounds.bottom, lessThanOrEqualTo(rowBounds.bottom + .1));
  final plainText = paragraph.text.toPlainText();
  final boxes = [
    for (final run in RegExp(r'\S+').allMatches(plainText))
      ...paragraph.getBoxesForSelection(
          TextSelection(baseOffset: run.start, extentOffset: run.end)),
  ];
  expect(boxes, isNotEmpty);
  final suffix = paragraph.getBoxesForSelection(TextSelection(
      baseOffset: plainText.length - 1, extentOffset: plainText.length));
  expect(suffix.any((box) => box.right > box.left), isTrue,
      reason: 'The final authored character must have a laid-out glyph box');
  for (final box in boxes) {
    final glyphs =
        MatrixUtils.transformRect(paragraph.getTransformTo(null), box.toRect());
    expect(glyphs.left, greaterThanOrEqualTo(panel.left - .1));
    expect(glyphs.right, lessThanOrEqualTo(panel.right + .1));
    // Native fallback fonts can extend tight selection metrics beyond the
    // rounded paragraph/row height (Japanese: 0.21px). MenuItemButton does not
    // clip its row; the menu viewport is the actual vertical clipping boundary.
    expect(glyphs.top, greaterThanOrEqualTo(panel.top - .1));
    expect(glyphs.bottom, lessThanOrEqualTo(panel.bottom + .1));
  }
}

void main() {
  // Select only failed native cases for resuming; default registration stays 8.
  final caseFilter = Platform.environment['DAN_INDEPENDENT_SORT_COMPACT_CASE'];
  bool includesCase(String name) =>
      caseFilter == null || caseFilter.isEmpty || name.contains(caseFilter);
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  for (final language in UiLanguage.values) {
    final categoryName =
        'compact category sort width and full labels ${language.name}';
    if (includesCase(categoryName)) {
      testWidgets(categoryName, (tester) async {
        uiLanguage.value = language;
        for (final width in [1100.0, 360.0]) {
          for (final scale in [1.0, 2.0]) {
            sizePlaylistFeature(tester, width: width, height: 620);
            final boundary = GlobalKey();
            var presentation = const CategoryPresentation();
            await tester.pumpWidget(_host(
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                            width: 600,
                            child: StatefulBuilder(builder: (context, update) {
                              return CategoryDisplayControls(
                                  value: presentation,
                                  onChanged: (value) =>
                                      update(() => presentation = value),
                                  search: const TextField());
                            })))),
                boundary,
                scale));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip(ui('分类显示选项')));
            await tester.pumpAndSettle();
            final trigger = find.widgetWithText(SubmenuButton, ui('排序'));
            await tester.ensureVisible(trigger);
            await tester.tap(trigger);
            await tester.pumpAndSettle();
            final first = find.widgetWithText(MenuItemButton, ui('默认顺序'));
            _expectPanel(tester, first, trigger, width, 620);
            for (final label in ['默认顺序', '名称', '歌曲数量', '自定义', '升序', '降序']) {
              await _expectFullLabel(tester,
                  find.widgetWithText(MenuItemButton, ui(label)), label);
            }
            await capturePlaylistFeature(tester, boundary,
                'category-sort-${language.name}-${width.toInt()}-$scale');
            await tester.tap(find.widgetWithText(MenuItemButton, ui('降序')));
            await tester.pumpAndSettle();
            expect(presentation.descending, isTrue);
            expect(presentation.sort, CategorySort.standard);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      });
    }

    final queueName =
        'queue sort and arrange compact width full labels ${language.name}';
    if (includesCase(queueName)) {
      testWidgets(queueName, (tester) async {
        uiLanguage.value = language;
        final playback = _SortPlayback();
        addTearDown(playback.dispose);
        final active = playback.nowPlaying;
        for (final width in [1100.0, 360.0]) {
          for (final scale in [1.0, 2.0]) {
            sizePlaylistFeature(tester, width: width, height: 1100);
            final boundary = GlobalKey();
            await tester.pumpWidget(_host(
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: CurrentPlaylistView(playbackService: playback)),
                boundary,
                scale));
            await tester.pumpAndSettle();
            for (final arrange in [false, true]) {
              await tester.tap(_key('queue-organize'));
              await tester.pumpAndSettle();
              final trigger =
                  _key('queue-extra-${arrange ? 'arrange' : 'sort'}');
              await tester.ensureVisible(trigger);
              await tester.tap(trigger);
              await tester.pumpAndSettle();
              final rows = <(String, String)>[
                if (!arrange) ...[
                  ('queue-sort-name', '待播歌曲按名称排序'),
                  ('queue-sort-artist', '待播歌曲按艺术家排序'),
                  ('queue-sort-album', '待播歌曲按专辑排序'),
                  ('queue-sort-duration', '待播歌曲按时长排序'),
                ],
                for (final order in UpcomingQueueOrder.values
                    .where((order) => order.arrangement == arrange))
                  ('queue-order-${order.name}', order.label),
                if (!arrange) ('queue-reverse-upcoming', '反转待播歌曲顺序'),
              ];
              _expectPanel(tester, _key(rows.first.$1), trigger, width, 1100);
              for (final row in rows) {
                await _expectFullLabel(tester, _key(row.$1), row.$2);
              }
              await capturePlaylistFeature(tester, boundary,
                  'queue-${arrange ? 'arrange' : 'sort'}-${language.name}-${width.toInt()}-$scale');
              final reversals = playback.reversals;
              final arrangements = playback.arrangements.length;
              await tester.tap(_key(rows.last.$1));
              await tester.pumpAndSettle();
              if (arrange) {
                expect(playback.arrangements.length, arrangements + 1);
                expect(playback.arrangements.last,
                    UpcomingQueueOrder.interleaveArtists);
              } else {
                expect(playback.reversals, reversals + 1);
              }
              expect(playback.nowPlaying, same(active));
              expect(playback.playlist.value.first, same(active));
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      });
    }
  }
}
