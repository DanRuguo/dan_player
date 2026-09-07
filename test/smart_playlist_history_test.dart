import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String title, {String? path, String artist = 'Artist'}) =>
    Audio.fromMap({
      'path': path ?? 'C:\\Music\\$title.flac',
      'title': title,
      'artist': artist,
      'album': 'Album',
      'duration': 180,
    });

void put(PlaybackStatistics stats, Audio audio, int count, DateTime? last) {
  final id = stats.identityFor(audio);
  stats.tracks[id] = TrackPlaybackStatistics(
      id: id,
      title: audio.title,
      artist: audio.artist,
      album: audio.album,
      online: false,
      playCount: count,
      lastPlayedAt: last?.millisecondsSinceEpoch ?? 0);
}

void main() {
  final now = DateTime.utc(2026, 9, 6, 12);
  test('local CUE input keeps its virtual identity and history eligibility',
      () async {
    const reference = CueTrackReference(
        cuePath: r'C:\Music\album.cue',
        sourcePath: r'C:\Music\album.wav',
        number: 1,
        startFrame: 0,
        endFrame: 1125);
    final cue = Audio.fromMap({
      'path': reference.identity,
      'title': 'First movement',
      'artist': 'Artist',
      'duration': 15,
      'cue_track': reference.toMap()
    });
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    put(stats, cue, 2, now);
    final result = await const SmartPlaylist(
            id: 'cue', name: 'Cue', history: SmartPlaylistHistory.played)
        .evaluate([cue], statistics: stats, now: now);
    expect(result.single.path, reference.identity);
    expect(result.single.isCueTrack, isTrue);
  });
  test(
      'old JSON remains unrestricted; new fields round trip and reject invalid conditions',
      () async {
    final legacy = const SmartPlaylist(id: 'a', name: 'Old').toJson()
      ..remove('history')
      ..remove('historyDays')
      ..remove('maxResults');
    final old = SmartPlaylist.fromJson(legacy);
    expect(old.history, SmartPlaylistHistory.any);
    expect(old.usesPlaybackHistory, isFalse);
    expect(old.maxResults, isNull);
    const recent = SmartPlaylist(
        id: 'new',
        name: 'Recent',
        history: SmartPlaylistHistory.recent,
        historyDays: 7,
        sort: SmartPlaylistSort.recentlyPlayed,
        maxResults: 20);
    final restored =
        SmartPlaylist.fromJson(jsonDecode(jsonEncode(recent.toJson())));
    expect(restored.toJson(), recent.toJson());
    for (final invalid in [
      {...recent.toJson(), 'history': 'bad'},
      {...recent.toJson(), 'historyDays': 0},
      {...recent.toJson(), 'historyDays': '7'},
      {...recent.toJson(), 'maxResults': 0},
      {...recent.toJson(), 'maxResults': 10001},
      {...recent.toJson(), 'maxResults': '20'},
    ]) {
      expect(() => SmartPlaylist.fromJson(invalid), throwsFormatException);
    }
    final root =
        Directory('${Directory.current.parent.path}/tool/qa-local/2605-smart');
    await root.create(recursive: true);
    final folder = await root.createTemp('rules-');
    final file = File('${folder.path}/smart_playlists.json');
    await SmartPlaylistStore(file).upsert(recent);
    expect((await SmartPlaylistStore(file).list()).single.toJson(),
        recent.toJson());
  });

  test(
      'played, never played and rolling day windows combine with metadata and handle empty history',
      () async {
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(stats.dispose);
    final never = song('Never');
    final recent = song('Recent');
    final boundary = song('Boundary');
    final old = song('Old');
    final future = song('Future');
    put(stats, recent, 2, now.subtract(const Duration(hours: 2)));
    put(stats, boundary, 1, now.subtract(const Duration(days: 7)));
    put(stats, old, 1, now.subtract(const Duration(days: 7, milliseconds: 1)));
    put(stats, future, 1, now.add(const Duration(days: 1)));
    final library = [never, recent, boundary, old, future];
    Future<List<Audio>> match(SmartPlaylistHistory history) =>
        SmartPlaylist(id: 'x', name: 'Rule', history: history, historyDays: 7)
            .evaluate(library, statistics: stats, now: now);
    expect(await match(SmartPlaylistHistory.unplayed), [same(never)]);
    expect((await match(SmartPlaylistHistory.played)).toSet(),
        {recent, boundary, old, future});
    expect(
        (await match(SmartPlaylistHistory.recent)).toSet(), {recent, boundary});
    expect((await match(SmartPlaylistHistory.notRecent)).toSet(),
        {never, old, future});
    expect(
        await const SmartPlaylist(
                id: 'x',
                name: 'Rule',
                query: 'recent',
                history: SmartPlaylistHistory.played)
            .evaluate(library, statistics: stats, now: now),
        [same(recent)]);
    await stats.initialize();
    expect(await match(SmartPlaylistHistory.played), isEmpty);
    expect(
        (await match(SmartPlaylistHistory.unplayed)).toSet(), library.toSet());
  });

  test(
      'limits follow sorting and different file instances keep separate history',
      () async {
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(stats.dispose);
    final a = song('A'), b = song('B'), c = song('C'), d = song('D');
    final duplicate = song('B', path: r'C:\Other\B.flac');
    put(stats, a, 1, now.subtract(const Duration(hours: 1)));
    put(stats, b, 10, now.subtract(const Duration(days: 1)));
    put(stats, c, 3, now);
    Future<List<Audio>> sorted(SmartPlaylistSort sort, {int? limit}) =>
        SmartPlaylist(id: 'x', name: 'Sorted', sort: sort, maxResults: limit)
            .evaluate([d, a, c, duplicate, b], statistics: stats, now: now);
    expect(await sorted(SmartPlaylistSort.mostPlayed, limit: 2),
        [same(b), same(c)]);
    expect(await sorted(SmartPlaylistSort.leastPlayed, limit: 2),
        [same(d), same(duplicate)]);
    expect(await sorted(SmartPlaylistSort.recentlyPlayed, limit: 2),
        [same(c), same(a)]);
    expect(
        await const SmartPlaylist(
                id: 'x',
                name: 'Artist',
                artist: 'missing',
                maxResults: 2,
                sort: SmartPlaylistSort.mostPlayed)
            .evaluate([a, b], statistics: stats),
        isEmpty);
  });

  test(
      'an evaluation snapshots history before yielding; clearing during work does not mix results',
      () async {
    final stats = PlaybackStatistics.inMemory(clock: () => now);
    addTearDown(stats.dispose);
    final a = song('A');
    put(stats, a, 1, now);
    const rule = SmartPlaylist(
        id: 'x', name: 'Played', history: SmartPlaylistHistory.played);
    final pending = rule.evaluate([a], statistics: stats, now: now);
    stats.tracks.clear();
    expect(await pending, [same(a)]);
    expect(await rule.evaluate([a], statistics: stats, now: now), isEmpty);
    var cancelled = false;
    final cancelledWork =
        rule.evaluate([a], statistics: stats, shouldCancel: () => cancelled);
    cancelled = true;
    expect(await cancelledWork, isEmpty);
  });

  test(
      'unassigned old candidates are unknown rather than never or least played',
      () async {
    final a = song('Shared', path: r'C:\UnknownHistory\a.flac');
    final b = song('Shared', path: r'C:\UnknownHistory\b.flac');
    final fresh = song('Fresh', path: r'C:\UnknownHistory\fresh.flac');
    final oldId = PlaybackStatistics.legacyIdentityFor(a);
    final stats = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [
        {
          'id': oldId,
          'playCount': 12,
          'listenMilliseconds': 5000,
          'lastPlayedAt': now.millisecondsSinceEpoch
        }
      ],
    });
    addTearDown(stats.dispose);
    stats.migrateLegacyIdentities([a, b, fresh]);
    final library = [a, b, fresh];
    for (final history in [
      SmartPlaylistHistory.unplayed,
      SmartPlaylistHistory.notRecent
    ]) {
      final rule =
          SmartPlaylist(id: 'unknown', name: 'Unknown', history: history);
      expect(await rule.evaluate(library, statistics: stats, now: now),
          [same(fresh)]);
    }
    expect(
        await const SmartPlaylist(
                id: 'least', name: 'Least', sort: SmartPlaylistSort.leastPlayed)
            .evaluate(library, statistics: stats),
        [same(fresh)]);
    put(stats, a, 1, now);
    expect(
        await const SmartPlaylist(
                id: 'recent',
                name: 'Recent',
                history: SmartPlaylistHistory.recent)
            .evaluate(library, statistics: stats, now: now),
        [same(a)]);
    // The immutable candidate snapshot must survive a concurrent history reset.
    const never = SmartPlaylist(
        id: 'never', name: 'Never', history: SmartPlaylistHistory.unplayed);
    final pending = never.evaluate(library, statistics: stats, now: now);
    stats.tracks.clear();
    expect(await pending, [same(fresh)]);
  });
}
