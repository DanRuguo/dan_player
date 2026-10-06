import 'dart:collection';
import 'dart:io';

import 'package:dan_player/component/listening_calendar_card.dart';
import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/statistics/app_data_storage.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/listening_status_fixture.dart';
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

class _ObservedInterval extends ListBase<int> {
  _ObservedInterval(this.values);
  final List<int> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  int operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, int value) => values[index] = value;
}

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  tearDown(() => uiLanguage.value = UiLanguage.zh);

  testWidgets(
      'a frozen recent projection survives language theme and range input',
      (tester) async {
    sizePlaylistFeature(tester, width: 1100, height: 1000);
    final now = DateTime(2026, 10, 6, 12);
    final start = now.subtract(const Duration(hours: 4)).millisecondsSinceEpoch;
    final recorder = PlaybackStatistics.inMemory(initialData: {
      'version': 4,
      'recentTrackingStartedAt': start,
      'recentPlayStarts': [start],
      'recentListeningIntervals': [
        for (var i = 0; i < 1000; i++)
          [start + i * 3000, start + i * 3000 + 1000],
      ],
    });
    addTearDown(recorder.dispose);
    final display = StatisticsDisplayService(
        statistics: recorder,
        scanner: LibraryStatisticsScanner(),
        readLibrary: () => [],
        clock: () => now);
    addTearDown(display.dispose);
    await tester.runAsync(display.prewarmOnce);
    Future<void> mount({Brightness brightness = Brightness.light}) async {
      await tester.pumpWidget(listeningStatusHost(
          StatisticsPage(
              displayService: display, storageScanner: const _NoStorageScan()),
          brightness: brightness));
      await tester.pumpAndSettle();
    }

    await mount();
    final card = tester
        .widget<ListeningCalendarCard>(find.byType(ListeningCalendarCard));
    final projection = card.recentActivitySnapshot!;
    expect(
        identical(
            (card.dailyChart as dynamic).recentActivitySnapshot, projection),
        isTrue);
    final intervals = [
      for (final interval in card.statistics.recentListeningIntervals)
        _ObservedInterval(interval),
    ];
    card.statistics.recentListeningIntervals
      ..clear()
      ..addAll(intervals);
    for (final language in [UiLanguage.en, UiLanguage.ja, UiLanguage.ko]) {
      uiLanguage.value = language;
      await tester.pumpAndSettle();
      await mount(brightness: Brightness.dark);
      await tester.tap(find.byKey(const ValueKey('statistics-hours-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('statistics-hours-recent')));
      await tester.pumpAndSettle();
    }
    expect(intervals.fold<int>(0, (sum, interval) => sum + interval.reads), 0,
        reason:
            'The recorder is frozen for this display capture; UI input must not rescan its intervals.');
    expect(
        identical(
            tester
                .widget<ListeningCalendarCard>(
                    find.byType(ListeningCalendarCard))
                .statistics,
            card.statistics),
        isTrue);
    // New recorder data remains separate until the existing explicit refresh.
    recorder.recentListeningIntervals.add([
      now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch,
      now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    ]);
    await mount();
    expect(
        tester
            .widget<ListeningCalendarCard>(find.byType(ListeningCalendarCard))
            .recentActivitySnapshot,
        same(projection));
    expect(projection.milliseconds, 1000000);
    await tester.runAsync(display.refresh);
    await tester.pumpAndSettle();
    final refreshed = tester
        .widget<ListeningCalendarCard>(find.byType(ListeningCalendarCard));
    expect(refreshed.recentActivitySnapshot, isNot(same(projection)));
    expect(refreshed.recentActivitySnapshot!.milliseconds, 1120000);
    expect(
        refreshed.recentActivitySnapshot!.longestIntervalMilliseconds, 120000);
    expect(
        identical((refreshed.dailyChart as dynamic).recentActivitySnapshot,
            refreshed.recentActivitySnapshot),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final language in UiLanguage.values) {
    for (final width in [320.0, 1100.0]) {
      testWidgets('continuous insight renders $language at $width',
          (tester) async {
        uiLanguage.value = language;
        sizePlaylistFeature(tester, width: width, height: 1000);
        final now = DateTime(2026, 10, 6, 12);
        final recorder = PlaybackStatistics.inMemory(initialData: {
          'version': 4,
          'recentTrackingStartedAt':
              now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          'recentListeningIntervals': [
            [
              now.subtract(const Duration(minutes: 90)).millisecondsSinceEpoch,
              now.subtract(const Duration(minutes: 55)).millisecondsSinceEpoch
            ],
            [
              now.subtract(const Duration(minutes: 54)).millisecondsSinceEpoch,
              now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch
            ],
          ],
        });
        addTearDown(recorder.dispose);
        final display = StatisticsDisplayService(
            statistics: recorder,
            scanner: LibraryStatisticsScanner(),
            readLibrary: () => [],
            clock: () => now);
        addTearDown(display.dispose);
        await tester.runAsync(display.prewarmOnce);
        final boundary = GlobalKey();
        await tester.pumpWidget(listeningStatusHost(
            StatisticsPage(
                displayService: display,
                storageScanner: const _NoStorageScan()),
            boundary: boundary,
            scale: width < 400 ? 1.8 : 1,
            brightness: width < 400 ? Brightness.dark : Brightness.light));
        await tester.pumpAndSettle();
        final metric =
            find.byKey(const ValueKey('statistics-longest-listening-interval'));
        await tester.ensureVisible(metric);
        await tester.pumpAndSettle();
        expect(
            tester.widget<Text>(metric).data,
            ui('最长连续收听：{0}', [
              ui('{0} 分 {1} 秒', [35, 0])
            ]));
        final rect = tester.getRect(metric);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);
        await captureListeningStatus(
            tester, boundary, 'continuous-${language.name}-${width.toInt()}');
      });
    }
  }
}
