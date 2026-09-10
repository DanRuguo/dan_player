import 'dart:convert';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  _Clock(this.value);

  DateTime value;
  DateTime now() => value;
  void advance(Duration duration) => value = value.add(duration);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Clock clock;
  late PlaybackStatistics statistics;
  final audio = Audio.online(
    provider: 'netease',
    id: 'statistics-clock',
    title: 'Clock test',
    artist: 'Test artist',
    album: 'Test album',
    duration: 180,
  );
  final nextAudio = Audio.online(
    provider: 'netease',
    id: 'statistics-next',
    title: 'Next test',
    artist: 'Test artist',
    album: 'Test album',
    duration: 180,
  );

  setUp(() {
    clock = _Clock(DateTime(2026, 8, 27, 14));
    statistics = PlaybackStatistics.inMemory(clock: clock.now);
  });

  tearDown(() => statistics.dispose());

  test('bounded rankings match full rankings, ties and live counter changes',
      () {
    final random = Random(123);
    for (var i = 0; i < 1000; i++) {
      statistics.tracks['$i'] = TrackPlaybackStatistics(
          id: '$i',
          title: 'Song $i',
          artist: 'Artist',
          album: 'Album',
          online: false,
          playCount: random.nextInt(12),
          listenMilliseconds: random.nextInt(12));
    }
    for (final limit in [0, -1, 1, 10, 99, 1000, 1001]) {
      expect(statistics.topPlayCount(limit: limit),
          statistics.topByPlayCount.take(max(0, limit)).toList());
      expect(statistics.topListeningTime(limit: limit),
          statistics.topByListeningTime.take(max(0, limit)).toList());
    }
    final first = statistics.tracks.values.first;
    first.playCount = 2000;
    first.listenMilliseconds = 2000;
    expect(statistics.topPlayCount(limit: 1), [first]);
    expect(statistics.topListeningTime(limit: 1), [first]);
    for (final track in statistics.tracks.values) {
      track.playCount = 1;
      track.listenMilliseconds = 1;
    }
    expect(
        statistics.topPlayCount(), statistics.tracks.values.take(10).toList());
    expect(statistics.topListeningTime(),
        statistics.tracks.values.take(10).toList());
    expect(statistics.topByPlayCount, statistics.tracks.values.toList());
    expect(statistics.topByListeningTime, statistics.tracks.values.toList());
  });

  test('bounded rankings return empty results for empty history', () {
    expect(statistics.topPlayCount(), isEmpty);
    expect(statistics.topListeningTime(), isEmpty);
  });

  void playingAfter(Duration duration) {
    clock.advance(duration);
    statistics.tick(audio, PlayerState.playing);
  }

  void expectBucketsMatchTotal() {
    expect(
      statistics.hourlyMilliseconds.fold(0, (sum, value) => sum + value),
      statistics.totalListenMilliseconds,
    );
    expect(
      statistics.dailyMilliseconds.values.fold(0, (sum, value) => sum + value),
      statistics.totalListenMilliseconds,
    );
  }

  test('actual elapsed samples count once independent of playhead seeks', () {
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 400));
    playingAfter(const Duration(milliseconds: 600));
    // Position changes do not enter this API. Multiple notifications emitted
    // by a forward/backward seek at the same instant must not add time.
    for (var event = 0; event < 20; event++) {
      statistics.tick(audio, PlayerState.playing);
    }
    expect(statistics.totalListenMilliseconds, 1000);
    expect(statistics.totalPlayCount, 1);
    expect(statistics.hourlyMilliseconds[14], 1000);
    expect(statistics.dailyMilliseconds['2026-08-27'], 1000);
    expectBucketsMatchTotal();
  });

  test('a restored paused source creates neither a play nor listening time',
      () {
    statistics.tick(audio, PlayerState.paused);
    clock.advance(const Duration(hours: 8));
    statistics.tick(audio, PlayerState.paused);
    statistics.pause();
    statistics.finish(markCompleted: false);
    expect(statistics.tracks, isEmpty);
    expect(statistics.totalPlayCount, 0);
    expect(statistics.totalListenMilliseconds, 0);
    expect(statistics.mostActiveHours, isEmpty);
  });

  test('pause closes the tail and resume does not count the paused interval',
      () {
    statistics.start(audio);
    clock.advance(const Duration(milliseconds: 600));
    statistics.pause();
    expect(statistics.totalListenMilliseconds, 600);

    clock.advance(const Duration(minutes: 20));
    statistics.pause();
    statistics.tick(audio, PlayerState.paused);
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 400));
    expect(statistics.totalListenMilliseconds, 1000);
    expect(statistics.totalPlayCount, 1);
    expectBucketsMatchTotal();
  });

  test('the playback service tick-then-pause sequence does not double count',
      () {
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 350));
    statistics.pause();
    clock.advance(const Duration(hours: 1));
    statistics.tick(audio, PlayerState.paused);
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 650));
    expect(statistics.totalListenMilliseconds, 1000);
    expect(statistics.totalPlayCount, 1);
  });

  for (final state in PlayerState.values.where(
    (state) => state != PlayerState.playing,
  )) {
    test('${state.name} breaks accounting until a new playing sample', () {
      statistics.start(audio);
      playingAfter(const Duration(milliseconds: 250));
      clock.advance(const Duration(seconds: 30));
      statistics.tick(audio, state);
      clock.advance(const Duration(minutes: 10));
      statistics.tick(audio, PlayerState.playing);
      expect(statistics.totalListenMilliseconds, 250);
      playingAfter(const Duration(milliseconds: 750));
      expect(statistics.totalListenMilliseconds, 1000);
      expect(statistics.totalPlayCount, 1);
      expectBucketsMatchTotal();
    });
  }

  test('a missing source cannot leak time into a later active source', () {
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 100));
    statistics.tick(null, PlayerState.playing);
    clock.advance(const Duration(hours: 5));
    statistics.tick(audio, PlayerState.playing);
    playingAfter(const Duration(milliseconds: 100));
    expect(statistics.totalListenMilliseconds, 200);
  });

  test('finishing a stalled source never adds its buffering interval', () {
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 500));
    statistics.tick(audio, PlayerState.stalled);
    clock.advance(const Duration(minutes: 10));
    statistics.finish(markCompleted: false, recordOutcome: false);
    expect(statistics.totalListenMilliseconds, 500);
    expectBucketsMatchTotal();
  });

  test('repeated start while playing preserves time without another play', () {
    statistics.start(audio);
    clock.advance(const Duration(milliseconds: 450));
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 550));
    expect(statistics.totalListenMilliseconds, 1000);
    expect(statistics.totalPlayCount, 1);
  });

  test('finish closes the final tail once and paused finish adds no time', () {
    statistics.start(audio);
    clock.advance(const Duration(milliseconds: 1200));
    statistics.finish(markCompleted: false, recordOutcome: false);
    expect(statistics.totalListenMilliseconds, 1200);
    clock.advance(const Duration(minutes: 3));
    statistics.finish(markCompleted: false, recordOutcome: false);
    expect(statistics.totalListenMilliseconds, 1200);

    statistics.start(nextAudio);
    clock.advance(const Duration(milliseconds: 800));
    statistics.pause();
    clock.advance(const Duration(minutes: 5));
    statistics.finish(markCompleted: false, recordOutcome: false);
    expect(statistics.totalListenMilliseconds, 2000);
    expect(statistics.totalPlayCount, 2);
    expect(statistics.tracks[statistics.identityFor(audio)]!.listenMilliseconds,
        1200);
    expect(
        statistics
            .tracks[statistics.identityFor(nextAudio)]!.listenMilliseconds,
        800);
  });

  test('changing tracks attributes the unreported tail to the previous track',
      () {
    statistics.start(audio);
    clock.advance(const Duration(milliseconds: 600));
    statistics.start(nextAudio);
    clock.advance(const Duration(milliseconds: 400));
    statistics.tick(nextAudio, PlayerState.playing);
    expect(statistics.tracks[statistics.identityFor(audio)]!.listenMilliseconds,
        600);
    expect(
        statistics
            .tracks[statistics.identityFor(nextAudio)]!.listenMilliseconds,
        400);
    expect(statistics.totalPlayCount, 2);
    expectBucketsMatchTotal();
  });

  test('a sample spanning an hour is split between both real clock buckets',
      () {
    clock.value = DateTime(2026, 8, 27, 9, 59, 59, 500);
    statistics.start(audio);
    playingAfter(const Duration(seconds: 1));
    expect(statistics.hourlyMilliseconds[9], 500);
    expect(statistics.hourlyMilliseconds[10], 500);
    expect(statistics.mostActiveHours, [9, 10]);
    expectBucketsMatchTotal();
  });

  test('midnight and a new year split daily and hourly totals consistently',
      () {
    clock.value = DateTime(2025, 12, 31, 23, 59, 59, 250);
    statistics.start(audio);
    playingAfter(const Duration(milliseconds: 1500));
    expect(statistics.dailyMilliseconds['2025-12-31'], 750);
    expect(statistics.dailyMilliseconds['2026-01-01'], 750);
    expect(statistics.hourlyMilliseconds[23], 750);
    expect(statistics.hourlyMilliseconds[0], 750);
    expectBucketsMatchTotal();
  });

  test('an exact boundary is not counted in the following hour', () {
    clock.value = DateTime(2026, 8, 27, 9, 59, 59);
    statistics.start(audio);
    playingAfter(const Duration(seconds: 1));
    expect(statistics.hourlyMilliseconds[9], 1000);
    expect(statistics.hourlyMilliseconds[10], 0);
    expectBucketsMatchTotal();
  });

  test('UTC test clocks preserve their own boundary rather than local offsets',
      () {
    clock.value = DateTime.utc(2026, 8, 27, 23, 59, 59);
    statistics.start(audio);
    playingAfter(const Duration(seconds: 2));
    expect(statistics.dailyMilliseconds['2026-08-27'], 1000);
    expect(statistics.dailyMilliseconds['2026-08-28'], 1000);
    expectBucketsMatchTotal();
  });

  test('fractional samples and boundary splits do not lose accumulated millis',
      () {
    clock.value = DateTime(2026, 8, 27, 9, 59, 59, 999, 500);
    statistics.start(audio);
    for (var sample = 0; sample < 2000; sample++) {
      playingAfter(const Duration(microseconds: 500));
    }
    expect(statistics.totalListenMilliseconds, 1000);
    expectBucketsMatchTotal();
  });

  test('suspension retains only the latest two-second observed window', () {
    clock.value = DateTime(2026, 8, 26, 23, 55);
    statistics.start(audio);
    playingAfter(const Duration(minutes: 5, seconds: 1));
    expect(statistics.totalListenMilliseconds, 2000);
    expect(statistics.dailyMilliseconds['2026-08-26'], 1000);
    expect(statistics.dailyMilliseconds['2026-08-27'], 1000);
    expect(statistics.hourlyMilliseconds[23], 1000);
    expect(statistics.hourlyMilliseconds[0], 1000);
    playingAfter(const Duration(milliseconds: 500));
    expect(statistics.totalListenMilliseconds, 2500);
    expectBucketsMatchTotal();
  });

  test('backward clock corrections never subtract or add a large interval', () {
    statistics.start(audio);
    playingAfter(const Duration(seconds: 1));
    clock.advance(const Duration(hours: -1));
    statistics.tick(audio, PlayerState.playing);
    expect(statistics.totalListenMilliseconds, 1000);
    playingAfter(const Duration(seconds: 1));
    expect(statistics.totalListenMilliseconds, 2000);
    expectBucketsMatchTotal();
  });

  test('empty and tied peak hours are represented honestly', () {
    expect(statistics.mostActiveHours, isEmpty);
    statistics.hourlyMilliseconds[20] = 1000;
    statistics.hourlyMilliseconds[23] = 1000;
    statistics.hourlyMilliseconds[5] = 500;
    expect(statistics.mostActiveHours, [20, 23]);
    statistics.hourlyMilliseconds[5] = 1001;
    expect(statistics.mostActiveHours, [5]);
  });

  test('legacy v1 all-time counters load unchanged and new plays append', () {
    final id = statistics.identityFor(audio);
    final hours = List<int>.filled(24, 0)..[20] = 65000;
    final snapshot = <String, Object?>{
      'version': 1,
      'tracks': [
        TrackPlaybackStatistics(
          id: id,
          title: audio.title,
          artist: audio.artist,
          album: audio.album,
          online: true,
          playCount: 7,
          completedCount: 3,
          skippedCount: 2,
          listenMilliseconds: 65000,
          lastPlayedAt: 10,
        ).toMap(),
      ],
      'days': {'2025-03-01': 65000},
      'hours': hours,
    };
    final original = jsonEncode(snapshot);
    statistics.dispose();
    statistics = PlaybackStatistics.inMemory(
      clock: clock.now,
      initialData: snapshot,
    );
    expect(statistics.totalPlayCount, 7);
    expect(statistics.totalCompletedCount, 3);
    expect(statistics.totalSkippedCount, 2);
    expect(statistics.totalListenMilliseconds, 65000);
    expect(statistics.mostActiveHours, [20]);
    statistics.start(audio);
    playingAfter(const Duration(seconds: 1));
    expect(statistics.totalPlayCount, 8);
    expect(statistics.totalListenMilliseconds, 66000);
    expect(statistics.hourlyMilliseconds[20], 65000);
    expect(statistics.hourlyMilliseconds[14], 1000);
    expect(statistics.dailyMilliseconds['2025-03-01'], 65000);
    expect(jsonEncode(snapshot), original);
    expectBucketsMatchTotal();
  });

  test('progress notifies on cadence and pause exposes the final fraction', () {
    statistics.start(audio);
    var notifications = 0;
    statistics.addListener(() => notifications++);
    for (var second = 0; second < 4; second++) {
      playingAfter(const Duration(seconds: 1));
    }
    expect(notifications, 0);
    playingAfter(const Duration(seconds: 1));
    expect(notifications, 1);
    clock.advance(const Duration(milliseconds: 250));
    statistics.pause();
    expect(statistics.totalListenMilliseconds, 5250);
    expect(notifications, 2);
  });

  test('the isolated factory never resolves or writes real user data',
      () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    var pathRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      pathRequests++;
      throw StateError('An in-memory recorder must not request a data path');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    statistics.start(audio);
    playingAfter(const Duration(seconds: 1));
    statistics.pause();
    await statistics.flush(finishSession: true);
    await statistics.initialize();
    expect(pathRequests, 0);
  });

  for (final rate in [.5, 2.0]) {
    test('$rate speed keeps actual listening totals and clock buckets', () {
      statistics.start(audio, playbackRate: rate);
      for (var second = 0; second < 20; second++) {
        clock.advance(const Duration(seconds: 1));
        statistics.tick(audio, PlayerState.playing, playbackRate: rate);
      }
      statistics.finish(markCompleted: false);
      expect(statistics.totalListenMilliseconds, 20000);
      expect(statistics.totalPlayCount, 1);
      expect(statistics.totalSkippedCount, rate == .5 ? 1 : 0);
      expectBucketsMatchTotal();
    });
  }

  test('half speed cannot mark half a song complete from wall time alone', () {
    statistics.start(audio, playbackRate: .5);
    for (var second = 0; second < 180; second++) {
      clock.advance(const Duration(seconds: 1));
      statistics.tick(audio, PlayerState.playing, playbackRate: .5);
    }
    statistics.finish(markCompleted: false);
    expect(statistics.totalListenMilliseconds, 180000);
    expect(statistics.totalCompletedCount, 0);
    expect(statistics.totalSkippedCount, 0);
  });

  test('double speed completes by consumed media but records half wall time',
      () {
    statistics.start(audio, playbackRate: 2);
    for (var second = 0; second < 90; second++) {
      clock.advance(const Duration(seconds: 1));
      statistics.tick(audio, PlayerState.playing, playbackRate: 2);
    }
    statistics.finish(markCompleted: false);
    expect(statistics.totalListenMilliseconds, 90000);
    expect(statistics.totalCompletedCount, 1);
    expectBucketsMatchTotal();
  });

  test('a mid-song rate boundary closes old speed before sampling new speed',
      () {
    statistics.start(audio, playbackRate: .5);
    for (var second = 0; second < 20; second++) {
      clock.advance(const Duration(seconds: 1));
      statistics.tick(audio, PlayerState.playing, playbackRate: .5);
    }
    statistics.tick(audio, PlayerState.playing, playbackRate: 2);
    for (var second = 0; second < 10; second++) {
      clock.advance(const Duration(seconds: 1));
      statistics.tick(audio, PlayerState.playing, playbackRate: 2);
    }
    statistics.finish(markCompleted: false);
    // Exactly 30 media seconds; not an early skip. Only 30 real seconds heard.
    expect(statistics.totalListenMilliseconds, 30000);
    expect(statistics.totalSkippedCount, 0);
    expect(statistics.totalCompletedCount, 0);
  });

  test('rate changes while paused never count silence or create a new play',
      () {
    statistics.start(audio, playbackRate: .5);
    clock.advance(const Duration(seconds: 1));
    statistics.pause();
    clock.advance(const Duration(hours: 1));
    statistics.tick(audio, PlayerState.paused, playbackRate: 2);
    statistics.start(audio, playbackRate: 2);
    clock.advance(const Duration(seconds: 1));
    statistics.pause();
    expect(statistics.totalListenMilliseconds, 2000);
    expect(statistics.totalPlayCount, 1);
  });

  test('native completion remains authoritative at every speed', () {
    statistics.start(audio, playbackRate: .5);
    clock.advance(const Duration(seconds: 1));
    statistics.finish(markCompleted: true);
    expect(statistics.totalCompletedCount, 1);
    expect(statistics.totalListenMilliseconds, 1000);
  });
}
