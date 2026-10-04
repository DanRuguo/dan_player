import 'package:dan_player/page/statistics_page.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/component/app_data_storage_card.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:dan_player/search/settings_search_index.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playlist_feature_fixture.dart';

void main() {
  setUpAll(loadPlaylistFeatureFonts);
  test(
      'resource setting search links to its actual backup entry in all four languages',
      () {
    for (final language in UiLanguage.values) {
      final entry = searchSettings(translateUi('播放器资源监控', language))
          .singleWhere((item) => item.id == 'process-resources');
      expect(entry.section, 'backup');
      expect(Uri.parse(entry.location).queryParameters['setting'],
          'process-resources');
    }
  });
  for (final section in ['folders', 'cache']) {
    testWidgets(
        'folder menu navigation opens the $section storage card directly',
        (tester) async {
      sizePlaylistFeature(tester, width: 800, height: 900);
      final audio = Audio('A song', 'Artist', 'Album', 1, 120, 320, 44100,
          r'J:\Fixture\Music\song.flac', 1, 1, 'fixture',
          language: 'en');
      final statistics = PlaybackStatistics.inMemory();
      final display = StatisticsDisplayService(
          statistics: statistics,
          readLibrary: () => [audio],
          readLibraryRevision: () => 1,
          scanner: LibraryStatisticsScanner(
              readLyrics: (_) async => null,
              inspectFile: (_) async =>
                  const LocalAudioFileInfo.available(4200)));
      addTearDown(display.dispose);
      addTearDown(statistics.dispose);
      await tester.runAsync(display.prewarmOnce);
      await tester.pumpWidget(playlistFeatureHost(StatisticsPage(
          displayService: display,
          initialStorageSection: section,
          initialStorageFolder:
              section == 'folders' ? r'J:\Fixture\Music' : null)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final target = section == 'cache'
          ? find.byType(AppDataStorageCard)
          : find.byKey(const ValueKey('statistics-folder-card'));
      final rect = tester.getRect(target);
      expect(rect.top, greaterThanOrEqualTo(-1));
      if (section == 'folders') {
        expect(rect.top, lessThan(180));
        expect(
            tester
                .widget<ChoiceChip>(
                    find.byKey(const ValueKey('folder-metric-bytes')))
                .selected,
            true);
        expect(find.text(r'J:\Fixture\Music'), findsWidgets);
      } else {
        // A small final card is clamped to the real scroll extent, without
        // adding blank space just to align its top with the viewport.
        expect(rect.top, lessThan(tester.view.physicalSize.height - 160));
        expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));
        expect(find.text(ui('缓存与播放器数据占用')).hitTestable(), findsOneWidget);
        expect(
            tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels,
            greaterThan(0));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
