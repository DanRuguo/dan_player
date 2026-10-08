import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/component/statistics_resize.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/playlist_feature_fixture.dart';

class _Cache extends AppDataStorageScanner {
  const _Cache();
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) async =>
      AppDataStorageSnapshot(
          path: directory.path,
          parts: const [],
          unreadable: 0,
          skippedLinks: 0,
          truncated: false);
}

class _Rig {
  _Rig(Directory directory,
      {Future<LocalAudioFileInfo>? pending, bool duplicate = false}) {
    final now = DateTime(2026, 10, 8, 12);
    statistics = PlaybackStatistics.inMemory(initialData: {
      'version': 4,
      'days': {for (var day = 1; day <= 8; day++) '2026-10-0$day': day * 60000},
      'hours': [for (var hour = 0; hour < 24; hour++) (hour + 1) * 60000],
      'playCountTrackingStartedOn': '2026-10-01',
      'dailyPlayCounts': {'2026-10-08': 3},
      'recentTrackingStartedAt':
          now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      'recentPlayStarts': [
        now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch
      ],
      'recentListeningIntervals': [
        [
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          now.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch,
        ]
      ],
    });
    final tracks = <Audio>[];
    for (var index = 0; index < 10; index++) {
      final audio = Audio(
          'Song $index',
          'Artist ${index % 2}',
          'Album ${index % 3}',
          index,
          180,
          320,
          44100,
          p.join(directory.path, 'song-$index.flac'),
          1,
          1,
          'fixture-$index',
          language: 'en');
      tracks.add(audio);
      statistics.tracks[audio.stableTrackId] = TrackPlaybackStatistics(
          id: audio.stableTrackId,
          title: audio.title,
          artist: audio.artist,
          album: audio.album,
          online: false,
          playCount: index + 1,
          listenMilliseconds: (index + 1) * 60000);
    }
    display = StatisticsDisplayService(
        statistics: statistics,
        readLibrary: () => duplicate ? [...tracks, tracks.first] : tracks,
        readLibraryRevision: () => 1,
        readPersonal: () => const {},
        clock: () => now,
        scanner: LibraryStatisticsScanner(
            readLyrics: (_) async => null,
            inspectFile: (_) =>
                pending ??
                Future.value(const LocalAudioFileInfo.available(120000))));
  }
  late final PlaybackStatistics statistics;
  late final StatisticsDisplayService display;
  final visible = ValueNotifier(true);
  final reduced = ValueNotifier(false);
  final preferences = ValueNotifier(const MotionPreferences());
  Widget get host => UiLanguageScope(
      child: MaterialApp(
          theme: Entry(welcome: false).fromSchemeAndFontFamily(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
          home: AnimatedBuilder(
              animation: Listenable.merge([visible, reduced, preferences]),
              builder: (context, _) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduced.value),
                  child: MotionPreferencesScope(
                      preferences: preferences.value,
                      child: TickerMode(
                          enabled: visible.value,
                          child: Scaffold(
                              body: StatisticsPage(
                                  displayService: display,
                                  storageScanner: const _Cache()))))))));
  void dispose() {
    display.dispose();
    statistics.dispose();
    visible.dispose();
    reduced.dispose();
    preferences.dispose();
  }
}

Finder _key(String name) => find.byKey(ValueKey(name), skipOffstage: false);
Finder _calendar() => _key('statistics-calendar-card');
Finder _calendarResize() => find
    .ancestor(
        of: _calendar(),
        matching: find.byType(StatisticsResize, skipOffstage: false))
    .first;
Finder _rankingCards() => find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_RankingCard',
    skipOffstage: false);
Finder _rankingResize() => find
    .ancestor(
        of: _rankingCards().first,
        matching: find.byType(StatisticsResize, skipOffstage: false))
    .first;
ScrollPosition _outer(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable))
        .first)
    .position;
double _footerY(WidgetTester tester) {
  final render = tester
      .renderObject<RenderSliverPadding>(_key('statistics-bottom-section'));
  final position = _outer(tester);
  // Use the footer's content position. A shrinking long ranking may correctly
  // clamp the viewport at its new end; off-screen sliver paint offsets also
  // clamp to the viewport and cannot measure this following layout anchor.
  return position.maxScrollExtent +
      position.viewportDimension -
      render.geometry!.scrollExtent;
}

/// Measure the occupied section and a real following layout anchor, rather
/// than an animation controller's value or an already-final child size.
Future<void> _transition(WidgetTester tester,
    {required Finder control,
    required Finder resize,
    required double Function() anchor}) async {
  final oldHeight = tester.getSize(resize).height;
  final oldAnchor = anchor();
  await tester.tap(control);
  await tester.pump();
  final firstHeight = tester.getSize(resize).height;
  final firstAnchor = anchor();
  await tester.pump(AppMotion.standard ~/ 2);
  final middleHeight = tester.getSize(resize).height;
  final middleAnchor = anchor();
  await tester.pumpAndSettle();
  final finalHeight = tester.getSize(resize).height;
  final finalAnchor = anchor();
  expect((finalHeight - oldHeight).abs(), greaterThan(.5));
  expect(firstHeight, closeTo(oldHeight, .05));
  expect(middleHeight, greaterThan(math.min(oldHeight, finalHeight) + .01));
  expect(middleHeight, lessThan(math.max(oldHeight, finalHeight) - .01));
  expect((finalAnchor - oldAnchor).abs(), greaterThan(.5));
  expect(firstAnchor, closeTo(oldAnchor, .05));
  expect(middleAnchor, greaterThan(math.min(oldAnchor, finalAnchor) + .01));
  expect(middleAnchor, lessThan(math.max(oldAnchor, finalAnchor) - .01));
  expect(tester.binding.transientCallbackCount, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory =
        await Directory.systemTemp.createTemp('statistics-page-resize-');
    expect(
        p.isWithin(p.normalize(p.absolute('..', 'tool', 'qa-local')),
            directory.absolute.path),
        true);
    await TrackIdentityRegistry.instance.initialize(directory: directory);
    // This injected path_provider fixture owns all application-directory reads.
    // Do not replace it with a process-wide DAN_PLAYER_DATA_DIR override.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
    await loadPlaylistFeatureFonts();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await directory.delete(recursive: true);
  });
  setUp(() {
    final previous = uiLanguage.value;
    uiLanguage.value = UiLanguage.zh;
    addTearDown(() => uiLanguage.value = previous);
  });
  Future<_Rig> mount(WidgetTester tester,
      {bool ready = true,
      Future<LocalAudioFileInfo>? pending,
      bool duplicate = false}) async {
    sizePlaylistFeature(tester, width: 1100, height: 1100);
    final rig = _Rig(directory, pending: pending, duplicate: duplicate);
    addTearDown(rig.dispose);
    if (ready) await tester.runAsync(rig.display.prewarmOnce);
    await tester.pumpWidget(rig.host);
    if (ready) await tester.pumpAndSettle();
    return rig;
  }

  Future<void> rankings(WidgetTester tester) async {
    await tester.scrollUntilVisible(_key('statistics-ranking-tracks'), 350,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'actual calendar periods resize and move the following section smoothly',
      (tester) async {
    await mount(tester);
    final position = _outer(tester);
    final anchor = _key('statistics-listening-trends');
    for (final range in ['twelveWeeks', 'daily']) {
      final pixels = position.pixels;
      await _transition(tester,
          control: _key('statistics-calendar-$range'),
          resize: _calendarResize(),
          anchor: () => tester.getTopLeft(anchor).dy);
      expect(_outer(tester), same(position));
      expect(position.pixels, pixels);
      expect(
          tester
              .widget<ChoiceChip>(_key('statistics-calendar-$range'))
              .selected,
          true);
    }
  });

  testWidgets(
      'recent and historical hours retain the page while height settles',
      (tester) async {
    await mount(tester);
    final position = _outer(tester);
    for (final mode in ['history', 'recent']) {
      await tester.ensureVisible(_key('statistics-hours-$mode'));
      await tester.pumpAndSettle();
      final pixels = position.pixels;
      await _transition(tester,
          control: _key('statistics-hours-$mode'),
          resize: _calendarResize(),
          anchor: () =>
              tester.getTopLeft(_key('statistics-listening-trends')).dy);
      expect(_outer(tester), same(position));
      expect(position.pixels, pixels);
      expect(tester.widget<ChoiceChip>(_key('statistics-hours-$mode')).selected,
          true);
    }
  });

  testWidgets(
      'ranking groups animate occupied height and the page footer anchor',
      (tester) async {
    await mount(tester);
    await rankings(tester);
    final position = _outer(tester);
    for (final (group, count) in [
      ('artists', 4),
      // Album ownership includes the artist: this fixture has six groups.
      ('albums', 12),
      ('tracks', 20)
    ]) {
      await _transition(tester,
          control: _key('statistics-ranking-$group'),
          resize: _rankingResize(),
          anchor: () => _footerY(tester));
      expect(
          tester.widget<ChoiceChip>(_key('statistics-ranking-$group')).selected,
          true);
      expect(
          tester
              .widgetList<StatisticsBarRow>(
                  find.byType(StatisticsBarRow, skipOffstage: false))
              .where((row) => row.rank != null),
          hasLength(count));
      expect(_outer(tester), same(position));
      expect(position.pixels,
          inInclusiveRange(position.minScrollExtent, position.maxScrollExtent));
    }
  });

  testWidgets(
      'disabled page motion applies calendar and hour selection immediately',
      (tester) async {
    final rig = await mount(tester);
    rig.preferences.value = rig.preferences.value.all(false);
    await tester.pump();
    final resize = _calendarResize();
    final old = tester.getSize(resize).height;
    await tester.tap(_key('statistics-calendar-twelveWeeks'));
    await tester.pump();
    final finalHeight = tester.getSize(resize).height;
    expect((old - finalHeight).abs(), greaterThan(.5));
    expect(finalHeight, closeTo(tester.getSize(_calendar()).height, .05));
    // SDK chip/ink feedback and the calendar's one-shot positioning frame are
    // independent of the section height clock. Its height must land first.
    await tester.pumpAndSettle();
    expect(tester.getSize(resize).height, closeTo(finalHeight, .05));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.tap(_key('statistics-calendar-daily'));
    await tester.pump();
    await tester.ensureVisible(_key('statistics-hours-history'));
    await tester.tap(_key('statistics-hours-history'));
    await tester.pump();
    expect(tester.widget<ChoiceChip>(_key('statistics-hours-history')).selected,
        true);
    expect(tester.getSize(resize).height,
        closeTo(tester.getSize(_calendar()).height, .05));
    await tester.pumpAndSettle();
    expect(tester.getSize(resize).height,
        closeTo(tester.getSize(_calendar()).height, .05));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final gate in ['hidden', 'reduced']) {
    testWidgets(
        'actual page $gate completes an in-flight period without replay',
        (tester) async {
      final rig = await mount(tester);
      final resize = _calendarResize();
      await tester.tap(_key('statistics-calendar-twelveWeeks'));
      await tester.pump();
      await tester.pump(AppMotion.standard ~/ 3);
      final target = tester.getSize(_calendar()).height;
      expect((tester.getSize(resize).height - target).abs(), greaterThan(.1));
      if (gate == 'hidden') {
        rig.visible.value = false;
      } else {
        rig.reduced.value = true;
      }
      await tester.pump();
      expect(tester.getSize(resize).height, closeTo(target, .05));
      if (gate == 'hidden') {
        expect(tester.binding.transientCallbackCount, 0);
      } else {
        // Reducing section motion does not remove SDK chip selection feedback.
        await tester.pumpAndSettle();
        expect(tester.getSize(resize).height, closeTo(target, .05));
        expect(tester.binding.transientCallbackCount, 0);
      }
      expect(
          tester
              .widget<ChoiceChip>(_key('statistics-calendar-twelveWeeks'))
              .selected,
          true);
      rig.visible.value = true;
      rig.reduced.value = false;
      await tester.pump();
      expect(tester.getSize(resize).height, closeTo(target, .05));
      await tester.pump(AppMotion.standard ~/ 2);
      expect(tester.getSize(resize).height, closeTo(target, .05));
      await tester.pumpAndSettle();
      expect(tester.getSize(resize).height, closeTo(target, .05));
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'wide to narrow rankings retain card elements and the chosen group',
      (tester) async {
    await mount(tester);
    await rankings(tester);
    await tester.tap(_key('statistics-ranking-artists'));
    await tester.pumpAndSettle();
    final cards = _rankingCards().evaluate().toList();
    final position = _outer(tester);
    tester.view.physicalSize = const Size(420, 1100);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(_rankingCards().evaluate().toList(), orderedEquals(cards));
    expect(_outer(tester), same(position));
    expect(
        tester.widget<ChoiceChip>(_key('statistics-ranking-artists')).selected,
        true);
    expect(
        tester
            .widgetList<StatisticsBarRow>(
                find.byType(StatisticsBarRow, skipOffstage: false))
            .where((row) => row.rank != null),
        hasLength(4));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'first capture inserts conditional sections without resetting folder metric',
      (tester) async {
    final file = Completer<LocalAudioFileInfo>();
    final rig = await mount(tester, ready: false, pending: file.future);
    rig.preferences.value = rig.preferences.value.all(false);
    final capture = rig.display.prewarmOnce();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.scrollUntilVisible(_key('folder-metric-bytes'), 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pump();
    expect(_key('folder-metric-bytes').hitTestable(), findsOneWidget);
    await tester.tap(_key('folder-metric-bytes'));
    await tester.pump();
    expect(
        tester.widget<ChoiceChip>(_key('folder-metric-bytes')).selected, true);
    final section = _key('statistics-distributions-section').evaluate().single;
    final position = _outer(tester);
    file.complete(const LocalAudioFileInfo.available(120000));
    await tester.runAsync(() => capture);
    await tester.pumpAndSettle();
    expect(rig.display.snapshot, isNotNull);
    expect(_key('statistics-distributions-section').evaluate().single,
        same(section));
    expect(
        tester.widget<ChoiceChip>(_key('folder-metric-bytes')).selected, true);
    expect(_key('statistics-listening-trends'), findsOneWidget);
    expect(find.text(ui('占用空间最多')), findsOneWidget);
    expect(_outer(tester), same(position));
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual duplicate-file caption uses all four localized numbers',
      (tester) async {
    final rig = await mount(tester, duplicate: true);
    expect(rig.display.snapshot!.library.duplicateEntries, 1);
    for (final language in UiLanguage.values) {
      uiLanguage.value = language;
      await tester.pumpAndSettle();
      final translated = ui('已合并 {0} 条重复记录。', [1]);
      final caption = find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data?.contains(translated) == true,
          skipOffstage: false);
      expect(caption, findsOneWidget, reason: language.name);
      expect(tester.widget<Text>(caption).data, contains('1'));
      if (language != UiLanguage.zh) {
        expect(tester.widget<Text>(caption).data, isNot(contains('已合并')));
      }
      expect(tester.takeException(), isNull);
    }
  });
}
