import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/smart_condition.dart';
import 'package:dan_player/library/smart_playlist.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

Audio song(String path,
        {String title = 'Night Sonata',
        String artist = 'Alice',
        String album = 'Piano',
        int duration = 180,
        int? bitrate = 320,
        int? sampleRate = 48000}) =>
    Audio.fromMap({
      'path': path,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'bitrate': bitrate,
      'sample_rate': sampleRate,
    });

RuleTruth match(SmartField field, String value, Audio audio,
        {bool exclude = false, PersonalTrack? personal, int? count}) =>
    SmartCondition.term(field, value, exclude: exclude).evaluate(
        audio.stableTrackId, personal, {},
        audio: audio, playCount: count);

void main() {
  test(
      'version two upgrades to four; future schema never falls back to an older backup',
      () async {
    final root = await Directory.systemTemp.createTemp('dan-smart-v3-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/smart_playlists.json');
    const legacy = SmartPlaylist(id: 'old', name: 'Old');
    await file.writeAsString(jsonEncode({
      'version': 2,
      'playlists': [legacy.toJson()]
    }));
    final store = SmartPlaylistStore(file);
    expect((await store.list()).single.toJson(), legacy.toJson());
    const expanded = SmartPlaylist(
        id: 'new',
        name: 'New',
        condition: SmartCondition.term(SmartField.bitrateAtLeast, '320'));
    await store.upsert(expanded);
    expect(jsonDecode(await file.readAsString())['version'], 4);
    expect((await SmartPlaylistStore(file).list()).last.toJson(),
        expanded.toJson());
    await file.writeAsString(jsonEncode({'version': 5, 'playlists': []}));
    await expectLater(
        SmartPlaylistStore(file).list(), throwsA(isA<UnsupportedError>()));
    await expectLater(SmartPlaylistStore(file).upsert(legacy),
        throwsA(isA<UnsupportedError>()));
    expect(jsonDecode(await file.readAsString())['version'], 5);
  });
  test('all thirteen new fields round trip; legacy rules stay unchanged', () {
    final values = <SmartField, String>{
      SmartField.titleContains: 'night',
      SmartField.artistContains: 'alice',
      SmartField.albumContains: 'piano',
      SmartField.folderWithin: r'C:\Music',
      SmartField.formatIs: '.FLAC',
      SmartField.durationAtLeast: '60',
      SmartField.durationAtMost: '300',
      SmartField.ratingAtMost: '3',
      SmartField.unrated: 'true',
      SmartField.playCountAtLeast: '1',
      SmartField.playCountAtMost: '3',
      SmartField.bitrateAtLeast: '320',
      SmartField.sampleRateAtLeast: '48000',
    };
    for (final entry in values.entries) {
      final condition =
          SmartCondition.term(entry.key, entry.value, exclude: true);
      expect(
          SmartCondition.fromJson(jsonDecode(jsonEncode(condition.toJson())))
              .toJson(),
          condition.toJson());
    }
    const legacy = SmartPlaylist(
        id: 'old',
        name: 'Old',
        condition: SmartCondition.term(SmartField.personalTag, 'night'));
    expect(SmartPlaylist.fromJson(legacy.toJson()).toJson(), legacy.toJson());
    final metadata = SmartCondition.group(values.entries
        .where((entry) => ![
              SmartField.ratingAtMost,
              SmartField.unrated,
              SmartField.playCountAtLeast,
              SmartField.playCountAtMost
            ].contains(entry.key))
        .map((entry) => SmartCondition.term(entry.key, entry.value))
        .toList());
    expect(metadata.usesPersonalData, isFalse);
    expect(metadata.usesPlaybackHistory, isFalse);
    expect(
        const SmartCondition.term(SmartField.unrated, 'true').usesPersonalData,
        isTrue);
  });

  test(
      'ANY metadata branches combine with ALL and exclusions without file reads',
      () async {
    final a = song(r'C:\Music\a.flac');
    final b = song(r'C:\Music\b.mp3', title: 'Morning', artist: 'Bob');
    final c = song(r'C:\Music\c.flac',
        title: 'Morning', artist: 'Bob', album: 'Live');
    final d = song(r'C:\Music\d.flac', title: 'Morning', artist: 'Carl');
    const rule = SmartPlaylist(
        id: 'composed',
        name: 'Night or Bob',
        condition: SmartCondition.group([
          SmartCondition.group([
            SmartCondition.term(SmartField.titleContains, 'NIGHT'),
            SmartCondition.term(SmartField.artistContains, 'bob'),
          ], any: true),
          SmartCondition.term(SmartField.albumContains, 'live', exclude: true),
          SmartCondition.term(SmartField.formatIs, 'flac'),
        ]));
    expect(await rule.evaluate([d, c, b, a]), [same(a)]);
    expect(rule.usesPlaybackHistory, isFalse);
  });

  test('folder boundaries are case insensitive and include only that subtree',
      () {
    for (final path in [r'C:\Music\a.flac', r'c:\MUSIC\Piano\a.flac']) {
      expect(match(SmartField.folderWithin, 'C:/Music/', song(path)),
          RuleTruth.yes);
    }
    for (final path in [
      r'C:\Music2\a.flac',
      r'C:\Other\Music\a.flac',
      r'D:\Music\a.flac'
    ]) {
      expect(match(SmartField.folderWithin, r'C:\Music', song(path)),
          RuleTruth.no);
    }
    expect(
        match(SmartField.folderWithin, r'\\server\music',
            song(r'\\SERVER\Music\Piano\a.flac')),
        RuleTruth.yes);
  });

  test(
      'CUE rules use source folder and format but retain slice duration and identity',
      () async {
    const reference = CueTrackReference(
        cuePath: r'C:\Music\album.cue',
        sourcePath: r'C:\Music\album.FLAC',
        number: 2,
        startFrame: 0,
        endFrame: 750);
    final cue = Audio.fromMap({
      'path': reference.identity,
      'duration': 10,
      'title': 'Slice',
      'cue_track': reference.toMap()
    });
    const rule = SmartPlaylist(
        id: 'cue',
        name: 'Slice',
        condition: SmartCondition.group([
          SmartCondition.term(SmartField.folderWithin, r'C:\Music'),
          SmartCondition.term(SmartField.formatIs, '.flac'),
          SmartCondition.term(SmartField.durationAtMost, '10'),
        ]));
    expect(await rule.evaluate([cue]), [same(cue)]);
    expect(cue.path, reference.identity);
    final online = Audio.online(
        provider: 'qq',
        id: '123',
        title: 'Slice',
        artist: 'Alice',
        album: 'Piano',
        duration: 10);
    expect(await rule.evaluate([online]), isEmpty);
  });

  test(
      'duration and quality thresholds include boundaries; absent data stays unknown even excluded',
      () {
    final known = song(r'C:\Music\a.flac');
    final thresholds = {
      SmartField.durationAtLeast: '180',
      SmartField.durationAtMost: '180',
      SmartField.bitrateAtLeast: '320',
      SmartField.sampleRateAtLeast: '48000'
    };
    for (final entry in thresholds.entries) {
      expect(match(entry.key, entry.value, known), RuleTruth.yes);
      expect(
          match(
              entry.key,
              entry.value,
              song(r'C:\Music\unknown.flac',
                  duration: 0, bitrate: null, sampleRate: null),
              exclude: true),
          RuleTruth.unknown);
    }
    expect(
        match(SmartField.formatIs, 'flac', song(r'C:\Music\no-extension'),
            exclude: true),
        RuleTruth.unknown);
    expect(
        match(SmartField.albumContains, 'live',
            song(r'C:\Music\a.flac', album: ''),
            exclude: true),
        RuleTruth.unknown);
    expect(match(SmartField.durationAtMost, '179', known), RuleTruth.no);
    expect(match(SmartField.bitrateAtLeast, '321', known), RuleTruth.no);
    expect(match(SmartField.sampleRateAtLeast, '48001', known), RuleTruth.no);
  });

  test(
      'rating ceiling leaves missing ratings unknown; unrated explicitly selects them',
      () {
    final audio = song(r'C:\Music\a.flac');
    expect(
        match(SmartField.ratingAtMost, '3', audio,
            personal: const PersonalTrack(rating: 3)),
        RuleTruth.yes);
    expect(
        match(SmartField.ratingAtMost, '3', audio,
            personal: const PersonalTrack(rating: 4)),
        RuleTruth.no);
    expect(match(SmartField.ratingAtMost, '3', audio, exclude: true),
        RuleTruth.unknown);
    expect(match(SmartField.unrated, 'true', audio), RuleTruth.yes);
    expect(
        match(SmartField.unrated, 'true', audio,
            personal: const PersonalTrack(rating: 1), exclude: true),
        RuleTruth.yes);
  });

  test(
      'play count bounds use immutable separate histories and unknown legacy candidates',
      () async {
    final a = song(r'C:\Music\a.flac'), b = song(r'C:\Music\b.flac');
    final stats = PlaybackStatistics.inMemory();
    addTearDown(stats.dispose);
    stats.tracks[stats.identityFor(a)] = TrackPlaybackStatistics(
        id: stats.identityFor(a),
        title: a.title,
        artist: a.artist,
        album: a.album,
        online: false,
        playCount: 3);
    const rule = SmartPlaylist(
        id: 'plays',
        name: 'One to three',
        condition: SmartCondition.group([
          SmartCondition.term(SmartField.playCountAtLeast, '1'),
          SmartCondition.term(SmartField.playCountAtMost, '3'),
        ]));
    expect(rule.usesPlaybackHistory, isTrue);
    final pending = rule.evaluate([a, b], statistics: stats);
    stats.tracks.clear();
    expect(await pending, [same(a)]);
    expect(await rule.evaluate([a, b], statistics: stats), isEmpty);
    final ambiguous = PlaybackStatistics.inMemory(initialData: {
      'version': 1,
      'tracks': [
        {'id': PlaybackStatistics.legacyIdentityFor(a), 'playCount': 5}
      ]
    });
    addTearDown(ambiguous.dispose);
    ambiguous.migrateLegacyIdentities([a, b]);
    expect(
        await const SmartPlaylist(
                id: 'zero',
                name: 'Zero',
                condition: SmartCondition.term(SmartField.playCountAtMost, '0'))
            .evaluate([a, b], statistics: ambiguous),
        isEmpty);
    expect(
        await const SmartPlaylist(
                id: 'exclude',
                name: 'Not popular',
                condition: SmartCondition.term(SmartField.playCountAtLeast, '3',
                    exclude: true))
            .evaluate([a, b], statistics: ambiguous),
        isEmpty);
  });

  test('invalid numeric, format and relative folder rules cannot be saved', () {
    for (final condition in [
      const SmartCondition.term(SmartField.durationAtMost, '86401'),
      const SmartCondition.term(SmartField.durationAtLeast, '-1'),
      const SmartCondition.term(SmartField.playCountAtLeast, '1.5'),
      const SmartCondition.term(SmartField.playCountAtMost, '1000000001'),
      const SmartCondition.term(SmartField.bitrateAtLeast, 'many'),
      const SmartCondition.term(SmartField.sampleRateAtLeast, '10000001'),
      const SmartCondition.term(SmartField.ratingAtMost, '0'),
      const SmartCondition.term(SmartField.unrated, 'false'),
      const SmartCondition.term(SmartField.folderWithin, 'Music'),
      const SmartCondition.term(SmartField.formatIs, 'flac,mp3'),
    ]) {
      expect(
          SmartPlaylist(id: 'invalid', name: 'Invalid', condition: condition)
              .validate(),
          isNotNull);
    }
  });
}
