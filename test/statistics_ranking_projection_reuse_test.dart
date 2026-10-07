import 'dart:io';

import 'package:dan_player/component/listening_calendar_card.dart';
import 'package:dan_player/component/statistics_bar_row.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playlist_feature_fixture.dart';

class _NoStorageScan extends AppDataStorageScanner {
  const _NoStorageScan();
  @override
  Future<AppDataStorageSnapshot> scan(Directory directory) async =>
      AppDataStorageSnapshot(
          path: directory.path,
          parts: const [],
          unreadable: 0,
          skippedLinks: 0,
          truncated: false);
}

class _ObservedTrack extends TrackPlaybackStatistics {
  _ObservedTrack(TrackPlaybackStatistics source)
      : super(
            id: source.id,
            title: source.title,
            artist: source.artist,
            album: source.album,
            online: source.online,
            playCount: source.playCount,
            listenMilliseconds: source.listenMilliseconds);
  int countReads = 0;
  @override
  int get playCount {
    countReads++;
    return super.playCount;
  }
}

Finder _key(String name) => find.byKey(ValueKey(name));

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('ranking-projection-');
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
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  Future<(PlaybackStatistics, StatisticsDisplayService)> fixture(
      WidgetTester tester) async {
    final recorder = PlaybackStatistics.inMemory();
    for (var index = 0; index < 10; index++) {
      recorder.tracks['fixture-$index'] = TrackPlaybackStatistics(
          id: 'fixture-$index',
          title: 'Track $index',
          artist: 'Artist $index',
          album: 'Album $index',
          online: false,
          playCount: index + 1,
          listenMilliseconds: (index + 1) * 60000);
    }
    final display = StatisticsDisplayService(
        statistics: recorder,
        scanner: LibraryStatisticsScanner(),
        readLibrary: () => [],
        clock: () => DateTime(2026, 10, 7, 12));
    addTearDown(display.dispose);
    addTearDown(recorder.dispose);
    await tester.runAsync(display.prewarmOnce);
    return (recorder, display);
  }

  Future<void> mount(WidgetTester tester, StatisticsDisplayService display,
      {double width = 1100, double scale = 1, Color seed = Colors.teal}) async {
    sizePlaylistFeature(tester, width: width, height: 1100);
    await tester.pumpWidget(UiLanguageScope(
        child: MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: Entry(welcome: false).fromSchemeAndFontFamily(
                colorScheme: ColorScheme.fromSeed(seedColor: seed)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: StatisticsPage(
                    displayService: display,
                    storageScanner: const _NoStorageScan())))));
    await tester.pumpAndSettle();
  }

  List<_ObservedTrack> observe(WidgetTester tester) {
    final model = tester
        .widget<ListeningCalendarCard>(find.byType(ListeningCalendarCard))
        .statistics;
    final tracks = model.tracks.values.map(_ObservedTrack.new).toList();
    model.tracks
      ..clear()
      ..addEntries(tracks.map((track) => MapEntry(track.id, track)));
    return tracks;
  }

  void observeProjectedRows(WidgetTester tester, List<_ObservedTrack> tracks) {
    // Also instrument rows already projected while the viewport lays out its
    // slivers. This is fixture-only replacement: production records are frozen.
    final byId = {for (final track in tracks) track.id: track};
    for (final card in tester.widgetList(find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_RankingCard'))) {
      final rows = (card as dynamic).tracks as List<TrackPlaybackStatistics>;
      rows.setAll(0, rows.map((track) => byId[track.id]!).toList());
    }
  }

  Future<void> revealRankings(WidgetTester tester) async {
    await tester.scrollUntilVisible(_key('statistics-ranking-tracks'), 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.ensureVisible(_key('statistics-ranking-tracks'));
    await tester.pumpAndSettle();
  }

  void reset(List<_ObservedTrack> tracks) {
    for (final track in tracks) {
      track.countReads = 0;
    }
  }

  int reads(List<_ObservedTrack> tracks) =>
      tracks.fold(0, (sum, track) => sum + track.countReads);

  testWidgets('ten ranking rows format values with linear shared measurement',
      (tester) async {
    final (_, display) = await fixture(tester);
    await mount(tester, display);
    final tracks = observe(tester);
    await revealRankings(tester);
    observeProjectedRows(tester, tracks);
    for (final language in UiLanguage.values) {
      reset(tracks);
      uiLanguage.value = language;
      await mount(tester, display, seed: Colors.amber);
      final count = reads(tracks);
      // Ten values, ten maximum reads and ten bars; small framework rebuild
      // variation must never restore an N*N measurement or history sort.
      // ignore: avoid_print
      print('Ranking reads ${language.name}: $count');
      expect(count, greaterThan(0));
      expect(count, lessThanOrEqualTo(40));
      final rows = tester
          .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
          .where((row) => row.rank != null)
          .toList();
      expect(rows, hasLength(20));
      expect(rows.take(10).map((row) => row.valueColumnWidth).toSet(),
          hasLength(1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'grouped rankings reuse frozen rows and refresh publishes new totals',
      (tester) async {
    final (recorder, display) = await fixture(tester);
    await mount(tester, display);
    final tracks = observe(tester);
    await revealRankings(tester);
    observeProjectedRows(tester, tracks);
    await tester.tap(_key('statistics-ranking-artists'));
    await tester.pumpAndSettle();
    for (final language in UiLanguage.values) {
      reset(tracks);
      uiLanguage.value = language;
      await mount(tester, display, width: 420, scale: 1.6, seed: Colors.amber);
      expect(reads(tracks), 0);
      expect(tester.takeException(), isNull);
    }
    await revealRankings(tester);
    await tester.tap(_key('statistics-ranking-albums'));
    await tester.pumpAndSettle();
    reset(tracks);
    await tester.tap(_key('statistics-ranking-artists'));
    await tester.pumpAndSettle();
    expect(reads(tracks), 0);
    recorder.tracks['fixture-9']!.playCount = 100;
    await tester.runAsync(display.refresh);
    await tester.pumpAndSettle();
    final rows = tester
        .widgetList<StatisticsBarRow>(find.byType(StatisticsBarRow))
        .where((row) => row.rank != null)
        .toList();
    expect(rows.first.valueLabel, ui('{0} 次', [100]));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
