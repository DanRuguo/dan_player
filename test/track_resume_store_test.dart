import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const all = TrackResumePreferences(mode: TrackResumeMode.allLocal);
const long = TrackResumePreferences(mode: TrackResumeMode.longAudio);
const song = r'J:\Music\book.flac';

void main() {
  late Directory sandbox;
  late File file;
  late DateTime now;
  late TrackResumeStore store;
  setUp(() async {
    final root = await Directory(
            p.absolute('..', 'tool', 'qa-local', '2605-track-resume'))
        .create(recursive: true);
    sandbox = await root.createTemp('store-');
    file = File(p.join(sandbox.path, 'track_resume.json'));
    now = DateTime.utc(2026, 9, 6);
    store = TrackResumeStore(file, clock: () => now);
  });
  tearDown(() async {
    await store.flush();
    await sandbox.delete(recursive: true);
  });

  Future<bool> remember(double position,
          {String track = song,
          bool force = false,
          bool completed = false,
          bool segmentLoopActive = false}) =>
      store.remember(
          track: track,
          position: position,
          duration: 3600,
          preferences: all,
          force: force,
          completed: completed,
          segmentLoopActive: segmentLoopActive);
  Future<double?> position({String track = song, double duration = 3600}) =>
      store.resumePosition(track: track, duration: duration, preferences: all);

  test('old preferences and malformed numeric types are safe and opt-in', () {
    for (final raw in [
      null,
      1,
      [],
      {},
      {'mode': 'future'}
    ]) {
      expect(TrackResumePreferences.fromJson(raw).mode, TrackResumeMode.off);
    }
    for (final raw in [20.0, '20', -1, 25, null]) {
      expect(TrackResumePreferences.fromJson({'minimumMinutes': raw}),
          const TrackResumePreferences());
    }
    final prefs = long.copyWith(minimumMinutes: 30);
    expect(TrackResumePreferences.fromJson(prefs.toJson()), prefs);
    expect(long.accepts(local: true, duration: 1199), isFalse);
    expect(long.accepts(local: true, duration: 1200), isTrue);
    expect(all.accepts(local: false, duration: 1200), isFalse);
    expect(all.accepts(local: true, duration: double.infinity), isFalse);
  });

  test('off and online never create storage; default excludes short music',
      () async {
    for (final prefs in [const TrackResumePreferences(), long]) {
      expect(
          await store.remember(
              track: song,
              position: 50,
              duration: 180,
              preferences: prefs,
              force: true),
          isFalse);
    }
    expect(await remember(60, track: 'https://example.org/song'), isFalse);
    expect(await file.exists(), isFalse);
  });

  test(
      'case-normalized local identity and CUE positions survive restart separately',
      () async {
    await remember(120, force: true);
    await remember(45, track: 'cue://track/album-02', force: true);
    final reopened = TrackResumeStore(file);
    expect(
        await reopened.resumePosition(
            track: r'j:/music/BOOK.flac', duration: 3600, preferences: all),
        120);
    expect(
        await reopened.resumePosition(
            track: 'cue://track/album-02', duration: 3600, preferences: all),
        45);
    expect(
        await reopened.resumePosition(
            track: 'cue://track/album-01', duration: 3600, preferences: all),
        isNull);
  });

  test('automatic advance, explicit seek and changed duration never resume',
      () async {
    await remember(120, force: true);
    expect(
        await store.resumePosition(
            track: song, duration: 3600, preferences: all, userSelected: false),
        isNull);
    expect(
        await store.resumePosition(
            track: song,
            duration: 3600,
            preferences: all,
            hasExplicitPosition: true),
        isNull);
    expect(await position(duration: 1000), isNull);
    expect(await position(duration: 3604), 120);
  });

  test('CUE stable identity rejects legacy or changed same-duration boundaries',
      () async {
    const cue = 'cue://track/album-02';
    const original = 'local:11111111-1111-4111-8111-111111111111';
    const changed = 'local:22222222-2222-4222-8222-222222222222';
    await remember(45, track: cue, force: true);
    expect(
        await store.resumePosition(
            track: cue,
            stableTrackId: original,
            duration: 3600,
            preferences: all),
        isNull);
    await store.remember(
        track: cue,
        stableTrackId: original,
        position: 60,
        duration: 3600,
        preferences: all,
        force: true);
    final reopened = TrackResumeStore(file);
    expect(
        await reopened.resumePosition(
            track: cue,
            stableTrackId: original,
            duration: 3600,
            preferences: all),
        60);
    expect(
        await reopened.resumePosition(
            track: cue,
            stableTrackId: changed,
            duration: 3600,
            preferences: all),
        isNull);
    await reopened.relocatePath(cue, 'cue://track/moved-album-02');
    expect(
        await TrackResumeStore(file).resumePosition(
            track: 'cue://track/moved-album-02',
            stableTrackId: original,
            duration: 3600,
            preferences: all),
        60);
  });

  test('old instance completion cannot clear another recording at same path',
      () async {
    const original = 'local:11111111-1111-4111-8111-111111111111';
    const replacement = 'local:22222222-2222-4222-8222-222222222222';
    await store.remember(
        track: song,
        stableTrackId: replacement,
        position: 70,
        duration: 3600,
        preferences: all,
        force: true);
    await store.remember(
        track: song,
        stableTrackId: original,
        position: 3600,
        duration: 3600,
        preferences: all,
        completed: true);
    expect(
        await store.resumePosition(
            track: song,
            stableTrackId: replacement,
            duration: 3600,
            preferences: all),
        70);
    expect(
        await store.resumePosition(
            track: song,
            stableTrackId: original,
            duration: 3600,
            preferences: all),
        isNull);
  });

  test('ten-second coalescing, forced pause/seek and clock rollback', () async {
    expect(await remember(30), isTrue);
    now = now.add(const Duration(seconds: 3));
    expect(await remember(33), isFalse);
    expect(await remember(55, force: true), isTrue);
    expect(await position(), 55);
    now = now.add(const Duration(seconds: 10));
    expect(await remember(65), isTrue);
    now = now.subtract(const Duration(days: 1));
    expect(await remember(75), isTrue);
  });

  test('A-B cannot overwrite memory; completion/end margin/reset clear it',
      () async {
    await remember(120, force: true);
    expect(await remember(340, force: true, segmentLoopActive: true), isFalse);
    expect(await position(), 120);
    await remember(3590, force: true);
    expect(await position(), isNull);
    await remember(120, force: true);
    await remember(0, force: true);
    expect(await position(), isNull);
    await remember(120, force: true);
    await remember(3600, completed: true);
    expect(await position(), isNull);
  });

  test(
      'corrupt main recovers backup and saves without replacing good backup with corruption',
      () async {
    await remember(120, force: true);
    await remember(130, force: true);
    await file.writeAsString('{broken');
    store = TrackResumeStore(file, clock: () => now);
    expect(await position(), 120);
    await remember(150, force: true);
    expect(jsonDecode(await file.readAsString())['positions'][0]['positionMs'],
        150000);
    expect(
        jsonDecode(await File('${file.path}.bak').readAsString())['positions']
            [0]['positionMs'],
        120000);
  });

  test(
      'oversized/malformed stores fail safely; explicit clear recovers and preserves manual bookmarks',
      () async {
    await file.writeAsString('x' * (TrackResumeStore.maxFileBytes + 1));
    await expectLater(position(), throwsFormatException);
    final bookmarks = File(p.join(sandbox.path, 'playback_bookmarks.json'));
    await bookmarks.writeAsString('manual');
    await store.clear();
    expect(await position(), isNull);
    expect(await bookmarks.readAsString(), 'manual');
    await remember(120, force: true);
    expect(await position(), 120);
  });

  test('failed writes do not poison the serialized queue or throttle retries',
      () async {
    final tmp = await Directory('${file.path}.tmp').create();
    await expectLater(remember(120), throwsA(isA<FileSystemException>()));
    await tmp.delete();
    expect(await remember(125), isTrue);
    expect(await position(), 125);
  });

  test('entry and byte limits keep the newest valid records', () async {
    final records = [
      for (var i = 0; i < 1000; i++)
        {
          'track': 'J:/Music/$i.flac',
          'positionMs': 100000,
          'durationMs': 3600000,
          'updatedMs': i,
        }
    ];
    await file.writeAsString(jsonEncode({'version': 1, 'positions': records}));
    await remember(200, force: true);
    var decoded = jsonDecode(await file.readAsString()) as Map;
    expect(decoded['positions'], hasLength(1000));
    expect(await position(track: 'J:/Music/0.flac'), isNull);
    expect(await position(), 200);

    // Seed just below the byte limit, then add a long UTF-8 identity. Entries
    // are evicted as needed without ever writing a file the reader rejects.
    final longRecords = [
      for (var i = 0; i < 250; i++)
        {
          'track': 'J:/Music/${'音' * 1250}$i.flac',
          'positionMs': 100000,
          'durationMs': 3600000,
          'updatedMs': i,
        }
    ];
    await file
        .writeAsString(jsonEncode({'version': 1, 'positions': longRecords}));
    store = TrackResumeStore(file, clock: () => now);
    for (var i = 0; i < 30; i++) {
      now = now.add(const Duration(seconds: 1));
      await remember(150, track: 'J:/Music/${'新' * 1250}$i.flac', force: true);
    }
    expect(
        await file.length(), lessThanOrEqualTo(TrackResumeStore.maxFileBytes));
    decoded = jsonDecode(await file.readAsString()) as Map;
    expect((decoded['positions'] as List).length, lessThan(280));
    expect(await position(track: 'J:/Music/${'新' * 1250}29.flac'), 150);
  });
}
