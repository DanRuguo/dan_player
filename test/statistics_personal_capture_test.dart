import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/statistics/statistics_display_service.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(String id) => Audio.online(
    provider: 'netease',
    id: id,
    title: id,
    artist: 'Artist',
    album: 'Album',
    duration: 180);

class _GateScanner extends LibraryStatisticsScanner {
  final gate = Completer<void>();
  int calls = 0;

  @override
  Future<LibraryStatisticsSnapshot> scan(Iterable<Audio> audios,
      {bool Function()? isCancelled,
      void Function(int completed, int total)? onProgress}) {
    calls++;
    final captured =
        super.scan(audios, isCancelled: isCancelled, onProgress: onProgress);
    return gate.future.then((_) => captured);
  }
}

void main() {
  test('synchronous personal capture freezes tags before the file await',
      () async {
    final stats = PlaybackStatistics.inMemory();
    final audio = _audio('one');
    final tags = ['rock'];
    final personal = {
      audio.stableTrackId: PersonalTrack(rating: 4, tags: tags),
      _audio('outside').stableTrackId:
          const PersonalTrack(rating: 5, tags: ['outside']),
    };
    final scanner = _GateScanner();
    final service = StatisticsDisplayService(
        statistics: stats,
        scanner: scanner,
        readLibrary: () => [audio, audio],
        readPersonal: () => personal);
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    final pending = service.refresh();
    tags.add('later');
    personal[audio.stableTrackId] =
        const PersonalTrack(rating: 1, tags: ['replaced']);
    scanner.gate.complete();
    await pending;
    expect(service.snapshot!.personalSummary!.ratingCounts[4], 1);
    expect(service.snapshot!.personalSummary!.ratedTracks, 1);
    expect(service.snapshot!.personalSummary!.tagCounts, {'rock': 1});
    expect(service.snapshot!.personalWarning, isNull);
  });

  test('async personal reads use frozen identities and run beside the scanner',
      () async {
    final stats = PlaybackStatistics.inMemory();
    final audio = _audio('one'), other = _audio('two');
    final originalId = audio.stableTrackId;
    var library = [audio];
    final personalGate = Completer<Map<String, PersonalTrack>>();
    final scanner = _GateScanner();
    var reads = 0;
    final service = StatisticsDisplayService(
        statistics: stats,
        scanner: scanner,
        readLibrary: () => library,
        readPersonal: () {
          reads++;
          return personalGate.future;
        });
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    final pending = service.refresh();
    expect(scanner.calls, 1);
    expect(reads, 1);
    expect(identical(pending, service.refresh()), isTrue);
    audio.path = other.path;
    library = [other];
    scanner.gate.complete();
    personalGate.complete({
      originalId: const PersonalTrack(rating: 3, tags: ['original']),
      other.stableTrackId: const PersonalTrack(rating: 5, tags: ['later']),
    });
    await pending;
    expect(service.snapshot!.personalSummary!.tagCounts, {'original': 1});
    expect(service.snapshot!.personalSummary!.ratingCounts[3], 1);
    expect(service.snapshot!.library.totalTracks, 1);
  });

  test('personal edits enter only the next explicit display capture', () async {
    final stats = PlaybackStatistics.inMemory();
    final audio = _audio('one');
    var reads = 0;
    var personal = {
      audio.stableTrackId: const PersonalTrack(rating: 2, tags: ['old'])
    };
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => [audio],
        readPersonal: () {
          reads++;
          return personal;
        });
    addTearDown(stats.dispose);
    addTearDown(service.dispose);
    await service.prewarmOnce();
    final before = service.snapshot!;
    var notifications = 0;
    service.addListener(() => notifications++);
    personal = {
      audio.stableTrackId: const PersonalTrack(rating: 5, tags: ['new'])
    };
    PersonalLibrary.changes.value++;
    await service.prewarmOnce();
    expect(reads, 1);
    expect(notifications, 0);
    expect(identical(service.snapshot, before), isTrue);
    await service.refresh();
    expect(reads, 2);
    expect(service.snapshot!.personalSummary!.tagCounts, {'new': 1});
    expect(before.personalSummary!.tagCounts, {'old': 1});
  });

  for (final asynchronous in [false, true]) {
    test(
        'personal read failure is isolated and retryable (async=$asynchronous)',
        () async {
      final stats = PlaybackStatistics.inMemory();
      final audio = _audio('one');
      var fail = true;
      final service = StatisticsDisplayService(
          statistics: stats,
          readLibrary: () => [audio],
          readPersonal: () {
            if (fail) {
              if (asynchronous) {
                return Future<Map<String, PersonalTrack>>.error(
                    StateError('personal fixture failure'));
              }
              throw StateError('personal fixture failure');
            }
            return {audio.stableTrackId: const PersonalTrack(rating: 5)};
          });
      addTearDown(stats.dispose);
      addTearDown(service.dispose);
      await service.refresh();
      expect(service.failure, isNull);
      expect(service.snapshot!.library.totalTracks, 1);
      expect(service.snapshot!.personalSummary, isNull);
      expect(service.snapshot!.personalWarning, isA<StateError>());
      fail = false;
      await service.refresh();
      expect(service.snapshot!.personalWarning, isNull);
      expect(service.snapshot!.personalSummary!.ratedTracks, 1);
    });
  }

  test('disposal retires a late personal result without publishing', () async {
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    final gate = Completer<Map<String, PersonalTrack>>();
    final service = StatisticsDisplayService(
        statistics: stats,
        readLibrary: () => [_audio('one')],
        readPersonal: () => gate.future);
    var notifications = 0;
    service.addListener(() => notifications++);
    final pending = service.refresh();
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    final before = notifications;
    gate.complete({});
    await pending;
    expect(service.snapshot, isNull);
    expect(notifications, before);
  });
}
