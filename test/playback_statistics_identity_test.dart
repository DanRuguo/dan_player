import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _track(String path, {String title = 'Same', int duration = 180}) => Audio(
    title, 'Artist', 'Album', 1, duration, 1000, 44100, path, 0, 0, 'Test');

Map<String, Object?> _legacy(String id,
        {int count = 4, int milliseconds = 12345}) =>
    {
      'id': id,
      'title': 'Same',
      'artist': 'Artist',
      'album': 'Album',
      'online': false,
      'playCount': count,
      'completedCount': 2,
      'skippedCount': 1,
      'listenMilliseconds': milliseconds,
      'lastPlayedAt': 500,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unique legacy bucket migrates once with exact totals and clock buckets',
      () {
    final audio = _track(r'C:\statistics-identity\unique.flac');
    final oldId = PlaybackStatistics.legacyIdentityFor(audio);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [_legacy(oldId)],
      'days': {'2026-09-06': 12345},
      'hours': [12345],
    });
    addTearDown(stats.dispose);
    expect(stats.migrateLegacyIdentities([audio]), 1);
    expect(stats.tracks.containsKey(oldId), isFalse);
    final migrated = stats.tracks[audio.trackId]!;
    expect(migrated.legacyIds, [oldId]);
    expect(stats.totalPlayCount, 4);
    expect(stats.totalCompletedCount, 2);
    expect(stats.totalSkippedCount, 1);
    expect(stats.totalListenMilliseconds, 12345);
    expect(stats.dailyMilliseconds, {'2026-09-06': 12345});
    expect(stats.hourlyMilliseconds.first, 12345);
    final reloaded = PlaybackStatistics.inMemory(initialData: stats.snapshot());
    addTearDown(reloaded.dispose);
    expect(reloaded.migrateLegacyIdentities([audio]), 0);
    expect(reloaded.totalListenMilliseconds, 12345);
    expect(reloaded.totalPlayCount, 4);
  });

  test(
      'ambiguous history stays single unassigned bucket; new plays are independent',
      () {
    final a = _track(r'C:\statistics-identity\a.flac');
    final b = _track(r'C:\statistics-identity\b.flac');
    final oldId = PlaybackStatistics.legacyIdentityFor(a);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [_legacy(oldId)],
    });
    addTearDown(stats.dispose);
    expect(stats.migrateLegacyIdentities([a, a, b]), 0);
    expect(stats.legacyUnassignedCount, 1);
    expect(
        stats.tracks[oldId]!.candidateTrackIds.toSet(), {a.trackId, b.trackId});
    expect(stats.totalPlayCount, 4);
    stats.start(a);
    stats.finish(markCompleted: false, recordOutcome: false);
    stats.start(b);
    stats.finish(markCompleted: false, recordOutcome: false);
    expect(stats.tracks[a.trackId]!.playCount, 1);
    expect(stats.tracks[b.trackId]!.playCount, 1);
    expect(stats.tracks[oldId]!.playCount, 4);
    expect(stats.totalPlayCount, 6);
    // Removing one candidate later cannot manufacture historical evidence.
    expect(stats.migrateLegacyIdentities([a]), 0);
    expect(stats.tracks[oldId]!.playCount, 4);
  });

  test('unmatched old history is retained and online keys remain unchanged',
      () {
    final absent = _track(r'C:\statistics-identity\missing.flac');
    final oldId = PlaybackStatistics.legacyIdentityFor(absent);
    final online = Audio.online(
        provider: 'custom:instance-a',
        id: '42',
        title: 'Online',
        artist: 'Artist',
        album: 'Album',
        duration: 180);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [
        _legacy(oldId),
        {..._legacy('online:custom:instance-a:42'), 'online': true}
      ],
    });
    addTearDown(stats.dispose);
    stats.migrateLegacyIdentities([]);
    expect(stats.tracks[oldId]!.legacyUnassigned, isTrue);
    expect(stats.tracks[oldId]!.candidateTrackIds, isEmpty);
    expect(stats.identityFor(online), 'online:custom:instance-a:42');
    expect(stats.tracks, hasLength(2));
    expect(stats.totalPlayCount, 8);
  });

  test('metadata and duration updates continue the same stable statistics', () {
    final audio = _track(r'C:\statistics-identity\edit.flac');
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    stats.start(audio);
    stats.finish(markCompleted: false, recordOutcome: false);
    final id = stats.identityFor(audio);
    audio.applyEditedMetadata(
        newPath: r'D:\statistics-identity\edit.flac',
        newTitle: 'Renamed',
        newArtist: 'New',
        newAlbum: 'New',
        newModified: 1);
    audio.duration = 181;
    stats.start(audio);
    expect(stats.identityFor(audio), id);
    expect(stats.tracks, hasLength(1));
    expect(stats.totalPlayCount, 2);
  });

  test(
      'existing stable bucket merges unique old bucket without changing totals',
      () {
    final audio = _track(r'C:\statistics-identity\mixed.flac');
    final oldId = PlaybackStatistics.legacyIdentityFor(audio);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [
        _legacy(oldId),
        _legacy(audio.trackId, count: 1, milliseconds: 100)
      ],
    });
    addTearDown(stats.dispose);
    stats.migrateLegacyIdentities([audio]);
    expect(stats.totalPlayCount, 5);
    expect(stats.totalListenMilliseconds, 12445);
    expect(stats.tracks, hasLength(1));
  });

  test(
      'duplicate or corrupt history is rejected instead of silently discarding totals',
      () {
    expect(
        () => PlaybackStatistics.inMemory(initialData: {
              'version': 1,
              'tracks': [_legacy('local:a'), _legacy('local:a')],
            }),
        throwsFormatException);
    expect(
        () => PlaybackStatistics.inMemory(initialData: {
              'version': 99,
              'tracks': [],
            }),
        throwsFormatException);
  });
}
