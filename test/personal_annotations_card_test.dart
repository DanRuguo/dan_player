import 'dart:io';

import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/component/personal_annotations_card.dart';
import 'package:dan_player/component/statistics_distribution_view.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/player_directory_storage.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
import 'support/playlist_feature_fixture.dart';

PersonalOrganizationSummary _project(List<PersonalTrack> tracks) =>
    PersonalOrganizationSummary.fromTrackIds(trackIds: [
      for (var index = 0; index < tracks.length; index++) 'online://qq/$index'
    ], personal: {
      for (final (index, track) in tracks.indexed) 'online://qq/$index': track
    }, identities: TrackIdentityRegistry.inMemory());

PersonalOrganizationSummary _fixture() => _project([
      for (var index = 0; index < 7; index++)
        PersonalTrack(
            rating: [1, 2, 3, 4, 5, 5, null][index],
            tags: ['Alpha', 'Beta', 'Chi', 'Delta', 'Eta', 'Phi', 'Zulu']
                .take(7 - index)
                .toList()),
    ]);

class _WatchedSummary implements PersonalOrganizationSummary {
  _WatchedSummary(this.summary);
  final PersonalOrganizationSummary summary;
  int tagReads = 0;
  @override
  Map<String, int> get tagCounts {
    tagReads++;
    return summary.tagCounts;
  }

  @override
  Map<int, int> get ratingCounts => summary.ratingCounts;
  @override
  int get ratedTracks => summary.ratedTracks;
  @override
  int get tagAnnotations => summary.tagAnnotations;
  @override
  int get bookmarkCount => summary.bookmarkCount;
  @override
  int get totalAnnotations => summary.totalAnnotations;
}

class _PageStorage extends PlayerDirectoryStorageScanner {
  int reads = 0;
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory,
      {bool Function()? isCancelled}) async {
    reads++;
    return AppDataStorageSnapshot(
        path: directory.path,
        parts: const [],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);
  }
}

class _PageCache extends AppDataStorageScanner {
  int reads = 0;
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) async {
    reads++;
    return AppDataStorageSnapshot(
        path: directory.path,
        parts: const [],
        unreadable: 0,
        skippedLinks: 0,
        truncated: false);
  }
}

Finder _key(String name) => find.byKey(ValueKey(name), skipOffstage: false);

StatisticsDistributionView _view(WidgetTester tester) =>
    tester.widget(find.byType(StatisticsDistributionView));

List<double> _fractions(WidgetTester tester, String group) => tester
    .widgetList<FractionallySizedBox>(find.descendant(
        of: _key('statistics-legend-$group'),
        matching: find.byType(FractionallySizedBox, skipOffstage: false),
        skipOffstage: false))
    .map((bar) => bar.widthFactor!)
    .toList();

void _expectCompactDescriptions(
    WidgetTester tester, StatisticsDistributionView view) {
  final chart = _key('statistics-chart-${view.chartId}');
  final center = find.descendant(
      of: chart, matching: find.text(view.centerValue, skipOffstage: false));
  final ratings = view.chartId == 'ratings';
  final count = int.parse(view.centerValue);
  expect(view.centerLabel, ui(ratings ? '个评级' : '个标签'));
  expect(
      view.centerSemanticsLabel,
      ui(
          ratings
              ? (count == 1 ? '1 个评级' : '{0} 个评级')
              : (count == 1 ? '1 次标签标注' : '{0} 次标签标注'),
          [count]));
  final caption = find.descendant(
      of: chart, matching: find.text(view.centerLabel, skipOffstage: false));
  expect(find.descendant(of: chart, matching: find.byType(Text)),
      findsNWidgets(2));
  expect(caption, findsOneWidget);
  expect(tester.getRect(center).center.dx,
      closeTo(tester.getRect(chart).center.dx, .05));
  expect(tester.getRect(caption).center.dx,
      closeTo(tester.getRect(chart).center.dx, .05));
  expect(
      tester.getRect(caption).top, greaterThan(tester.getRect(center).bottom));
  final centerBounds =
      tester.getRect(center).expandToInclude(tester.getRect(caption));
  expect(centerBounds.center.dy, closeTo(tester.getRect(chart).center.dy, .05));
  final innerBounds = tester.getRect(chart).deflate(32);
  for (final text in [center, caption]) {
    final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
        of: text, matching: find.byType(RichText, skipOffstage: false)));
    expect(paragraph.didExceedMaxLines, isFalse);
    final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: 0, extentOffset: paragraph.text.toPlainText().length));
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final rect = MatrixUtils.transformRect(
          paragraph.getTransformTo(null), box.toRect());
      expect(rect.left, greaterThanOrEqualTo(innerBounds.left - 1));
      expect(rect.right, lessThanOrEqualTo(innerBounds.right + 1));
      expect(rect.top, greaterThanOrEqualTo(innerBounds.top - 3));
      expect(rect.bottom, lessThanOrEqualTo(innerBounds.bottom + 3));
    }
  }
  expect(
      tester.getSemantics(chart).label.split('\n'),
      contains(
          '${view.centerSemanticsLabel}。${view.slices.map((slice) => '${slice.label} ${slice.amount}').join('，')}'));
  for (final (index, slice) in view.slices.indexed) {
    final row = _key('statistics-comparison-${view.chartId}-$index');
    final bar = find.descendant(of: row, matching: find.byType(ClipRRect));
    final percent = '${slice.percentage!.toStringAsFixed(1)}%';
    expect(tester.getSemantics(bar).label.split('\n'),
        contains('${slice.label} ${slice.amount} $percent'));
    if (slice.detail.isEmpty) {
      expect(find.descendant(of: row, matching: find.text('')), findsNothing);
      final padding = tester.widget<Padding>(
          find.descendant(of: row, matching: find.byType(Padding)).first);
      final content = padding.child! as Column;
      // Equal-height legend pairs may inherit the Other row's extra detail
      // height. Check the actual last content rather than that shared allocation.
      expect(content.children.last, isA<Semantics>());
      expect(tester.getRect(find.byWidget(content.children.last)).bottom,
          closeTo(tester.getRect(bar).bottom, .05));
      expect(
          content.children
              .whereType<SizedBox>()
              .any((spacing) => spacing.height == 5),
          isFalse,
          reason: 'An empty description leaves no text or trailing detail gap');
    } else {
      expect(find.descendant(of: row, matching: find.text(slice.detail)),
          findsOneWidget);
    }
  }
}

Future<void> _choose(WidgetTester tester, String group) async {
  final chip = _key('personal-annotations-$group');
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  expect(chip.hitTestable(), findsOneWidget);
  expect(tester.widget<ChoiceChip>(chip).onSelected, isNotNull);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
  expect(
      tester
          .widget<RawChip>(
              find.descendant(of: chip, matching: find.byType(RawChip)))
          .showCheckmark,
      isTrue);
}

void _expectLabelFits(WidgetTester tester, Finder text, Rect bounds) {
  final paragraph = tester.renderObject<RenderParagraph>(find.descendant(
      of: text,
      matching: find.byType(RichText, skipOffstage: false),
      skipOffstage: false));
  final value = tester.widget<Text>(text).data!;
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.text.toPlainText(), value);
  final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: value.length));
  expect(boxes, isNotEmpty);
  for (final box in boxes) {
    final rect = box.toRect().shift(paragraph.localToGlobal(Offset.zero));
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 1));
    expect(rect.right, lessThanOrEqualTo(bounds.right + 1));
    expect(rect.top, greaterThanOrEqualTo(bounds.top - 3));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 3));
  }
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  setUp(() {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    addTearDown(() => uiLanguage.value = previous);
  });
  Future<void> mount(WidgetTester tester, PersonalOrganizationSummary? summary,
      {double width = 1080,
      double scale = 1,
      GlobalKey? boundary,
      Color seed = Colors.teal}) async {
    sizePlaylistFeature(tester, width: width, height: 1500);
    await tester.pumpWidget(listeningStatusHost(
        SingleChildScrollView(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: PersonalAnnotationsCard(snapshot: summary))),
        scale: scale,
        boundary: boundary,
        seed: seed));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'rating rings and bars count only rated tracks across all five levels',
      (tester) async {
    uiLanguage.value = UiLanguage.en;
    final summary = _fixture();
    await mount(tester, summary);
    final view = _view(tester);
    expect(view.chartId, 'ratings');
    expect(view.centerValue, '6');
    expect(view.slices.map((slice) => slice.label), [
      for (var rating = 1; rating <= 5; rating++) ui('{0} 星', [rating])
    ]);
    expect(view.slices.map((slice) => slice.value), [1, 1, 1, 1, 2]);
    expect(view.slices.map((slice) => slice.amount),
        ['1 song', '1 song', '1 song', '1 song', '2 songs']);
    final expected = [1 / 6, 1 / 6, 1 / 6, 1 / 6, 2 / 6];
    final bars = _fractions(tester, 'ratings');
    expect(bars, hasLength(5));
    for (var index = 0; index < bars.length; index++) {
      expect(bars[index], closeTo(expected[index], .000001));
    }
    expect(find.text(ui('按已评级歌曲计算比例；未评级歌曲不参与。')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'personal center units and spoken counts cover all four languages',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final language in UiLanguage.values) {
        uiLanguage.value = language;
        for (final count in [0, 1, 14]) {
          await mount(
              tester,
              _project([
                for (var index = 0; index < count; index++)
                  PersonalTrack(
                      rating: 3, tags: ['Shared', if (count > 1) 'Second']),
              ]));
          for (final group in ['ratings', 'tags']) {
            await _choose(tester, group);
            final view = _view(tester);
            _expectCompactDescriptions(tester, view);
            final total = group == 'ratings' || count <= 1 ? count : count * 2;
            expect(view.centerValue, '$total');
            final expected = switch (language) {
              UiLanguage.zh =>
                group == 'ratings' ? '$total 个评级' : '$total 次标签标注',
              UiLanguage.en => group == 'ratings'
                  ? '$total ${total == 1 ? 'rating' : 'ratings'}'
                  : '$total tag ${total == 1 ? 'assignment' : 'assignments'}',
              UiLanguage.ja =>
                group == 'ratings' ? '$total 件の評価' : '$total 件のタグ付与',
              UiLanguage.ko =>
                group == 'ratings' ? '평점 $total개' : '태그 부여 $total회',
            };
            expect(view.centerSemanticsLabel, expected);
            expect(view.slices.every((slice) => slice.detail.isEmpty), isTrue);
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tag top five and other retain the full multi-tag denominator',
      (tester) async {
    await mount(tester, _fixture());
    await _choose(tester, 'tags');
    final view = _view(tester);
    expect(view.chartId, 'tags');
    expect(view.centerValue, '28');
    expect(view.slices.map((slice) => slice.label),
        ['Alpha', 'Beta', 'Chi', 'Delta', 'Eta', ui('其他标签')]);
    expect(view.slices.map((slice) => slice.value), [7, 6, 5, 4, 3, 3]);
    expect(view.slices.last.detail, ui('其他 {0} 个标签', [2]));
    final bars = _fractions(tester, 'tags');
    expect(bars, hasLength(6));
    for (final (index, value) in [7, 6, 5, 4, 3, 3].indexed) {
      expect(bars[index], closeTo(value / 28, .000001));
    }
    expect(bars.fold(0.0, (sum, value) => sum + value), closeTo(1, .000001));
    expect(view.slices.first.percentage, 25);
    expect(tester.takeException(), isNull);
    // A one-assignment total uses the same singular text for an explicit tag
    // and the bounded Other segment; grouping never changes its denominator.
    uiLanguage.value = UiLanguage.en;
    await mount(
        tester,
        _project([
          const PersonalTrack(tags: ['F', 'D', 'B', 'E', 'C', 'A'])
        ]));
    final singles = _view(tester);
    expect(singles.centerValue, '6');
    expect(singles.slices.map((slice) => slice.label),
        ['A', 'B', 'C', 'D', 'E', 'Other tags']);
    expect(singles.slices.map((slice) => slice.amount),
        List.filled(6, '1 assignment'));
    expect(find.text('1 assignment'), findsNWidgets(6));
    expect(_fractions(tester, 'tags').fold(0.0, (sum, value) => sum + value),
        closeTo(1, .000001));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'equal tag counts use title order and small snapshots invent no other group',
      (tester) async {
    await mount(
        tester,
        _project([
          const PersonalTrack(tags: ['G', 'B', 'E', 'A', 'F', 'D', 'C'])
        ]));
    await _choose(tester, 'tags');
    expect(_view(tester).slices.map((slice) => slice.label),
        ['A', 'B', 'C', 'D', 'E', ui('其他标签')]);
    expect(_view(tester).slices.last.value, 2);
    for (final count in [5, 0, 1, 2, 3, 4]) {
      await mount(
          tester,
          _project([
            PersonalTrack(tags: [
              for (var index = 0; index < count; index++) 'Tag $index'
            ])
          ]));
      expect(_view(tester).chartId, 'tags');
      expect(_view(tester).slices, hasLength(count));
      expect(_view(tester).slices.any((slice) => slice.label == ui('其他标签')),
          isFalse);
      expect(_view(tester).centerValue, '$count');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'tag sorting is snapshot owned across toggles locale palette and refresh',
      (tester) async {
    final first = _WatchedSummary(_fixture());
    await mount(tester, first);
    final state = tester.state(find.byType(PersonalAnnotationsCard));
    expect(first.tagReads, 1);
    for (var index = 0; index < 3; index++) {
      await _choose(tester, 'tags');
      await _choose(tester, 'ratings');
    }
    uiLanguage.value = UiLanguage.ja;
    await mount(tester, first, scale: 2, seed: Colors.amber);
    expect(tester.state(find.byType(PersonalAnnotationsCard)), same(state));
    expect(first.tagReads, 1);
    final next = _WatchedSummary(_project([
      const PersonalTrack(rating: 3, tags: ['New'])
    ]));
    await mount(tester, next);
    await _choose(tester, 'tags');
    expect(next.tagReads, 1);
    expect(first.tagReads, 1);
    expect(_view(tester).slices.single.label, 'New');
    expect(_view(tester).slices.single.value, 1);
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('large tag snapshot preserves top five ties and every attachment',
      (tester) async {
    final summary = _WatchedSummary(_project([
      for (var index = 1199; index >= 0; index--)
        PersonalTrack(tags: [
          'Rare ${index.toString().padLeft(4, '0')}',
          if (index.isEven) ...['Zulu', 'Alpha'],
          if (index % 3 == 0) ...['Omega', 'Beta'],
          if (index % 4 == 0) 'Gamma',
        ])
    ]));
    await mount(tester, summary);
    await _choose(tester, 'tags');
    final view = _view(tester);
    expect(view.centerValue, '3500');
    expect(view.slices.map((slice) => slice.label),
        ['Alpha', 'Zulu', 'Beta', 'Omega', 'Gamma', ui('其他标签')]);
    expect(view.slices.map((slice) => slice.value),
        [600, 600, 400, 400, 300, 1200]);
    expect(view.slices.last.detail, ui('其他 {0} 个标签', [1200]));
    expect(_fractions(tester, 'tags').fold(0.0, (sum, value) => sum + value),
        closeTo(1, .000001));
    await _choose(tester, 'ratings');
    await _choose(tester, 'tags');
    expect(summary.tagReads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'not ready and unannotated snapshots expose accurate empty states',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, null);
      expect(find.text(ui('个人标注统计尚未就绪')), findsOneWidget);
      expect(find.byType(StatisticsDistributionView), findsNothing);
      await _choose(tester, 'tags');
      expect(find.byType(StatisticsDistributionView), findsNothing);
      await mount(tester, _project([const PersonalTrack()]));
      expect(_view(tester).slices, isEmpty);
      expect(_view(tester).centerValue, '0');
      _expectCompactDescriptions(tester, _view(tester));
      await _choose(tester, 'ratings');
      expect(_view(tester).slices, isEmpty);
      _expectCompactDescriptions(tester, _view(tester));
      await mount(tester, null);
      expect(find.byType(StatisticsDistributionView), findsNothing);
      expect(find.text(ui('个人标注统计尚未就绪')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'actual page places populated personal charts after distributions',
      (tester) async {
    final fixture = Directory.systemTemp.createTempSync('personal-page-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => fixture.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(pathProvider, null);
      fixture.deleteSync(recursive: true);
    });
    final audio = Audio('Fixture', 'Artist', 'Album', 1, 120, 320, 44100,
        '${fixture.path}/song.flac', 1, 1, 'personal-page',
        language: 'en');
    final statistics = PlaybackStatistics.inMemory();
    final display = StatisticsDisplayService(
        statistics: statistics,
        readLibrary: () => [audio],
        readLibraryRevision: () => 1,
        readPersonal: () => {
              audio.stableTrackId:
                  const PersonalTrack(rating: 4, tags: ['Favorite'])
            },
        scanner: LibraryStatisticsScanner(
            readLyrics: (_) async => null,
            inspectFile: (_) async =>
                const LocalAudioFileInfo.available(1234)));
    addTearDown(display.dispose);
    addTearDown(statistics.dispose);
    await tester.runAsync(display.prewarmOnce);
    final cache = _PageCache(), player = _PageStorage();
    sizePlaylistFeature(tester, width: 1800, height: 1100);
    await tester.pumpWidget(listeningStatusHost(StatisticsPage(
        displayService: display,
        storageScanner: cache,
        playerStorageScanner: player,
        playerDirectory: Directory('${fixture.path}/player'))));
    final deadline = Stopwatch()..start();
    while (cache.reads == 0 && deadline.elapsed < const Duration(seconds: 5)) {
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }
    expect(cache.reads, 1,
        reason:
            'The injected path-provider continuation must reach the scanner');
    await tester.pumpAndSettle();
    final personal = find.byType(PersonalAnnotationsCard, skipOffstage: false);
    expect(personal, findsOneWidget);
    await tester.ensureVisible(personal);
    await tester.pumpAndSettle();
    final view = tester.widget<StatisticsDistributionView>(find.descendant(
        of: personal,
        matching: find.byType(StatisticsDistributionView, skipOffstage: false),
        skipOffstage: false));
    expect(view.centerValue, '1');
    expect(view.slices.single.value, 1);
    expect(view.slices.single.label, ui('{0} 星', [4]));
    final personalRect = tester.getRect(personal);
    for (final group in ['language', 'format', 'folders']) {
      final originalCard = find
          .ancestor(
              of: _key('statistics-chart-$group'),
              matching: find.byType(Card, skipOffstage: false))
          .first;
      final rect = tester.getRect(originalCard);
      expect(rect.bottom, lessThan(personalRect.top));
      expect(rect.width, lessThan(personalRect.width / 2),
          reason: 'The original three-column grid stays intact');
    }
    final largest = find
        .ancestor(
            of: _key('statistics-storage-group'),
            matching: find.byType(Card, skipOffstage: false))
        .first;
    final directory = find.byType(AppDataStorageCard, skipOffstage: false);
    expect(personalRect.bottom, lessThan(tester.getRect(largest).top));
    expect(personalRect.bottom, lessThan(tester.getRect(directory).top));
    expect(cache.reads, 1);
    expect(player.reads, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  for (final language in UiLanguage.values) {
    for (final wide in [true, false]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'personal annotations ${language.code} ${wide ? 'wide' : 'narrow'} ${scale.toInt()}x real layout',
            (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            uiLanguage.value = language;
            final boundary = GlobalKey();
            await mount(tester, _fixture(),
                width: wide ? 1080 : 360, scale: scale, boundary: boundary);
            final selector = _key('personal-annotations-selector');
            final title = find.text(ui('个人标注'));
            final titleRect = tester.getRect(title);
            final selectorRect = tester.getRect(selector);
            if (wide || (scale == 1 && language != UiLanguage.en)) {
              expect(titleRect.center.dy, closeTo(selectorRect.center.dy, 1),
                  reason: 'A naturally fitting heading shares the choices row');
              expect(titleRect.right, lessThan(selectorRect.left));
            } else {
              expect(selectorRect.top, greaterThan(titleRect.bottom),
                  reason: 'Large narrow headings precede the wrapped choices');
            }
            final content = find
                .ancestor(of: selector, matching: find.byType(Column))
                .first;
            expect(tester.getRect(selector).right,
                closeTo(tester.getRect(content).right, 1));
            final rowEnds = <double, double>{};
            for (final group in ['ratings', 'tags']) {
              final chip = _key('personal-annotations-$group');
              expect(chip.hitTestable(), findsOneWidget);
              final rect = tester.getRect(chip);
              rowEnds.update(
                  rect.top, (value) => value > rect.right ? value : rect.right,
                  ifAbsent: () => rect.right);
              _expectLabelFits(tester,
                  find.descendant(of: chip, matching: find.byType(Text)), rect);
            }
            for (final end in rowEnds.values) {
              expect(end, closeTo(tester.getRect(selector).right, 1));
            }
            for (final group in ['ratings', 'tags']) {
              await _choose(tester, group);
              final chart = _key('statistics-chart-$group');
              final legend = _key('statistics-legend-$group');
              final card = find.byType(Card).first;
              final cardRect = tester.getRect(card);
              for (final area in [chart, legend]) {
                final rect = tester.getRect(area);
                expect(rect.left, greaterThanOrEqualTo(cardRect.left));
                expect(rect.right, lessThanOrEqualTo(cardRect.right + 1));
              }
              final view = _view(tester);
              _expectCompactDescriptions(tester, view);
              expect(view.slices.take(5).every((slice) => slice.detail.isEmpty),
                  isTrue);
              if (group == 'tags') {
                expect(view.slices.last.detail, ui('其他 {0} 个标签', [2]));
                expect(find.text(ui('标签附着次数')), findsNothing);
                expect(find.text(ui('按逐歌标签附着次数计算；一首歌可有多个标签，次数不等于歌曲总数。')),
                    findsNothing);
                expect(
                    find.textContaining(ui('按逐歌标签附着次数计算；一首歌可有多个标签，次数不等于歌曲总数。')),
                    findsOneWidget);
              } else {
                expect(find.text(ui('已评级歌曲')), findsNothing);
                expect(find.text(ui('按已评级歌曲计算比例；未评级歌曲不参与。')), findsOneWidget);
              }
              for (final slice in view.slices) {
                final text = find.descendant(
                    of: legend,
                    matching: find.text(slice.label, skipOffstage: false),
                    skipOffstage: false);
                expect(text, findsOneWidget);
                _expectLabelFits(tester, text, tester.getRect(legend));
              }
              expect(
                  _fractions(tester, group)
                      .every((value) => value >= 0 && value <= 1),
                  isTrue);
              await tester.ensureVisible(card);
              await tester.pumpAndSettle();
              await captureListeningStatus(tester, boundary,
                  'personal-$group-${language.code}-${wide ? 'wide' : 'narrow'}-${scale.toInt()}x');
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox.shrink());
            expect(tester.binding.transientCallbackCount, 0);
          } finally {
            semantics.dispose();
          }
        });
      }
    }
  }
}
