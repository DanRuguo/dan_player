import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingScanner extends LibraryStatisticsScanner {
  bool fail = false;
  int scans = 0;

  @override
  Future<LibraryStatisticsSnapshot> scan(Iterable<Audio> audios,
      {bool Function()? isCancelled,
      void Function(int completed, int total)? onProgress}) {
    scans++;
    if (fail) throw StateError('Synthetic scan failure');
    return super.scan(audios, isCancelled: isCancelled, onProgress: onProgress);
  }
}

void main() {
  Audio local(String title) => Audio(title, 'Artist', 'Album', 1, 180, 320,
      44100, 'C:/Synthetic/$title.mp3', 1, 1, title,
      language: 'en');
  Audio online(String id) => Audio.online(
      provider: 'netease',
      id: id,
      title: id,
      artist: 'Artist',
      album: 'Album',
      duration: 180);

  test(
      'startup warms once; background recording does not invalidate frozen display',
      () async {
    final stats = PlaybackStatistics.inMemory(
        clock: () => DateTime(2026, 9, 26),
        initialData: {
          'version': 3,
          'playCountTrackingStartedOn': '2026-09-26',
          'dailyPlayCounts': {'2026-09-26': 2},
          'tracks': [
            {'id': 'online:netease:history', 'playCount': 2}
          ],
        });
    var reads = 0;
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => [local('One')],
        scanner: LibraryStatisticsScanner(inspectFile: (_) async {
          reads++;
          return const LocalAudioFileInfo.available(1024);
        }));
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await service.prewarmOnce();
    final captured = service.snapshot!;
    var notifications = 0;
    service.addListener(() => notifications++);
    stats.start(online('new'));
    await service.prewarmOnce();
    expect(reads, 1);
    expect(identical(captured, service.snapshot), isTrue);
    expect(notifications, 0);
    expect(stats.totalPlayCount, 3);
    expect((captured.playbackData['tracks'] as List).length, 1);
    expect(() => captured.playbackData['days'] = {}, throwsUnsupportedError);
    expect(() => (captured.playbackData['tracks'] as List).add({}),
        throwsUnsupportedError);
    expect(
        () => ((captured.playbackData['tracks'] as List).first
            as Map)['playCount'] = 99,
        throwsUnsupportedError);
    expect(() => captured.library.languageCounts[SongLanguage.english] = 99,
        throwsUnsupportedError);
  });

  test(
      'concurrent refreshes share one capture and freeze metadata before awaiting files',
      () async {
    var now = DateTime(2026, 9, 26, 10);
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    final audio = local('One');
    var audios = [audio];
    var revision = 1;
    var reads = 0;
    final gate = Completer<void>();
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => audios,
        readLibraryRevision: () => revision,
        clock: () => now,
        scanner: LibraryStatisticsScanner(inspectFile: (_) async {
          reads++;
          if (reads == 1) await gate.future;
          return const LocalAudioFileInfo.available(1024);
        }));
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    stats.start(online('first'));
    final first = service.prewarmOnce();
    final second = service.refresh();
    expect(identical(first, second), isTrue);
    expect(service.refreshing, isTrue);
    expect(service.snapshot, isNull);
    now = DateTime(2026, 9, 27, 10);
    stats.start(online('second'));
    audio.language = 'ja';
    audio.title = 'Edited';
    revision = 2;
    audios = [audio, local('Two')];
    gate.complete();
    await first;
    expect(reads, 1);
    expect(service.snapshot!.library.localTracks, 1);
    expect(service.snapshot!.library.taggedLanguageCounts[SongLanguage.english],
        1);
    expect(service.snapshot!.library.largestFiles.first.title, 'One');
    expect(service.snapshot!.libraryRevision, 1);
    expect(service.snapshot!.capturedAt, DateTime(2026, 9, 26, 10));
    expect((service.snapshot!.playbackData['tracks'] as List).length, 1);
    await service.refresh();
    expect(reads, 3);
    expect(service.snapshot!.library.localTracks, 2);
    expect(
        service.snapshot!.library.taggedLanguageCounts[SongLanguage.japanese],
        1);
    expect(service.snapshot!.libraryRevision, 2);
    expect(service.snapshot!.capturedAt, now);
    expect((service.snapshot!.playbackData['tracks'] as List).length, 2);
  });

  test(
      'failed refresh keeps the entire previous capture and explicit retry publishes latest',
      () async {
    final stats = PlaybackStatistics.inMemory();
    final scanner = _FailingScanner();
    final service = StatisticsDisplayService(
        statistics: stats, scanner: scanner, readLibrary: () => []);
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await service.prewarmOnce();
    final previous = service.snapshot;
    stats.start(online('new'));
    scanner.fail = true;
    await service.refresh();
    expect(service.failure, isA<StateError>());
    expect(service.refreshing, isFalse);
    expect(identical(service.snapshot, previous), isTrue);
    scanner.fail = false;
    await service.refresh();
    expect(service.failure, isNull);
    expect(identical(service.snapshot, previous), isFalse);
    expect((service.snapshot!.playbackData['tracks'] as List).length, 1);
    await service.prewarmOnce();
    expect(scanner.scans, 3);
  });

  test(
      'disposing the session cancels pending work and does not publish or notify later',
      () async {
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    final gate = Completer<void>();
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => [local('One')],
        scanner: LibraryStatisticsScanner(inspectFile: (_) async {
          await gate.future;
          return const LocalAudioFileInfo.available(1);
        }));
    var notifications = 0;
    service.addListener(() => notifications++);
    final pending = service.prewarmOnce();
    expect(notifications, 1);
    service.dispose();
    gate.complete();
    await pending;
    expect(notifications, 1);
    expect(service.snapshot, isNull);
    await service.refresh();
    expect(notifications, 1);
  });

  test('manual capture before startup callback is reused by startup', () async {
    final stats = PlaybackStatistics.inMemory();
    final scanner = _FailingScanner();
    final service = StatisticsDisplayService(
        statistics: stats, scanner: scanner, readLibrary: () => []);
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await service.refresh();
    await service.prewarmOnce();
    expect(scanner.scans, 1);
  });

  test(
      'display adapter shares no mutable recording state and keeps storage warning',
      () {
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 3,
      'playCountTrackingStartedOn': '2026-09-26',
      'dailyPlayCounts': {'2026-09-26': 2},
      'tracks': [
        {'id': 'online:netease:history', 'playCount': 2}
      ],
    });
    final display = PlaybackStatistics.displayCopy(stats.snapshot(),
        storageWarning: 'warning');
    addTearDown(stats.dispose);
    addTearDown(display.dispose);
    stats.tracks.values.first.playCount = 99;
    stats.dailyPlayCounts['2026-09-26'] = 99;
    expect(display.totalPlayCount, 2);
    expect(display.dailyPlayCounts['2026-09-26'], 2);
    expect(display.storageWarning, 'warning');
  });
}
