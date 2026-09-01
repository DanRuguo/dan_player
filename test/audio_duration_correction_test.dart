import 'dart:async';

import 'package:dan_player/library/audio_duration_correction.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _audio(
  String name, {
  int duration = 0,
  int durationVersion = 0,
  int modified = 10,
  String? modifiedNanos = '10000000001',
  int? size = 2048,
}) =>
    Audio(
      name,
      'Fixture',
      'Synthetic',
      0,
      duration,
      null,
      null,
      'D:/synthetic-duration/$name.mp3',
      modified,
      1,
      'Fixture',
      durationVersion: durationVersion,
      modifiedNanos: modifiedNanos,
      fileSizeBytes: size,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native duration validation rejects unknown and impossible values', () {
    expect(verifiedPlaybackDuration(double.nan), isNull);
    expect(verifiedPlaybackDuration(double.infinity), isNull);
    expect(verifiedPlaybackDuration(-1), isNull);
    expect(verifiedPlaybackDuration(0.9), isNull);
    expect(verifiedPlaybackDuration(0x80000000.toDouble()), isNull);
    expect(verifiedPlaybackDuration(125.9), 125);
  });

  test('legacy JSON stays pending while verified JSON preserves its marker',
      () {
    final legacy = Audio.fromMap({
      'path': 'D:/synthetic-duration/legacy.mp3',
      'title': 'Legacy',
      'artist': 'Fixture',
      'album': 'Synthetic',
      'duration': 42,
    });
    expect(legacy.durationVersion, 0);
    expect(legacy.toMap()['duration_version'], 0);

    final verified = Audio.fromMap({
      ...legacy.toMap(),
      'duration_version': 1,
    });
    expect(verified.durationVersion, 1);
    expect(verified.toMap()['duration_version'], 1);
  });

  test('opened native stream corrects conflicting scanner duration once',
      () async {
    final audio = _audio('conflict', duration: 899, durationVersion: 1);
    final byPath = {audio.path: audio};
    var saves = 0;
    var publishes = 0;
    final errors = <Object>[];
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (path) => byPath[path],
      persist: () async => saves++,
      publish: () => publishes++,
      onError: (error, _) => errors.add(error),
    );

    coordinator.observe(audio, 125.9);
    await coordinator.settled;

    expect(audio.duration, 125);
    expect(audio.durationVersion, 1);
    expect(saves, 1);
    expect(publishes, 1);
    expect(errors, isEmpty);

    coordinator.observe(audio, 125.1);
    await coordinator.settled;
    expect(saves, 1, reason: 'verified values must not rewrite the index');
  });

  test('one-second rounding difference only records completed backfill',
      () async {
    final audio = _audio('rounding', duration: 126);
    var saves = 0;
    var publishes = 0;
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (_) => audio,
      persist: () async => saves++,
      publish: () => publishes++,
    );

    coordinator.observe(audio, 125.9);
    await coordinator.settled;

    expect(audio.duration, 126);
    expect(audio.durationVersion, 1);
    expect(saves, 1);
    expect(publishes, 0,
        reason: 'a marker-only backfill has no visible duration change');
  });

  test('multiple loaded songs are coalesced into one atomic index save',
      () async {
    final first = _audio('first');
    final second = _audio('second', duration: 999);
    final byPath = {first.path: first, second.path: second};
    var saves = 0;
    var publishes = 0;
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (path) => byPath[path],
      persist: () async => saves++,
      publish: () => publishes++,
    );

    coordinator.observe(first, 60.8);
    coordinator.observe(second, 180.2);
    await coordinator.settled;

    expect([first.duration, second.duration], [60, 180]);
    expect(saves, 1);
    expect(publishes, 1);
  });

  test('production-style debounce does not block caller and batches changes',
      () async {
    final first = _audio('debounced-first');
    final second = _audio('debounced-second');
    final byPath = {first.path: first, second.path: second};
    final release = Completer<void>();
    var saves = 0;
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (path) => byPath[path],
      persist: () async => saves++,
      publish: () {},
      debounce: const Duration(milliseconds: 250),
      delay: (_) => release.future,
    );

    coordinator.observe(first, 30);
    coordinator.observe(second, 40);
    await Future<void>.delayed(Duration.zero);
    expect(saves, 0);
    expect(first.duration, 0,
        reason: 'observe must not synchronously mutate or write the library');

    release.complete();
    await coordinator.settled;
    expect([first.duration, second.duration], [30, 40]);
    expect(saves, 1);
  });

  test('failed atomic save rolls memory back and remains retryable', () async {
    final audio = _audio('rollback', duration: 0);
    var fail = true;
    var saves = 0;
    var publishes = 0;
    final errors = <Object>[];
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (_) => audio,
      persist: () async {
        saves++;
        if (fail) throw StateError('synthetic persistence failure');
      },
      publish: () => publishes++,
      onError: (error, _) => errors.add(error),
    );

    coordinator.observe(audio, 90);
    await coordinator.settled;
    expect(audio.duration, 0);
    expect(audio.durationVersion, 0);
    expect(publishes, 0);
    expect(errors, hasLength(1));

    fail = false;
    coordinator.observe(audio, 90);
    await coordinator.settled;
    expect(audio.duration, 90);
    expect(audio.durationVersion, 1);
    expect(saves, 2);
    expect(publishes, 1);
  });

  test('changed file fingerprint drops late engine result without a write',
      () async {
    final opened = _audio('changed', duration: 0);
    var current = opened;
    var saves = 0;
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (_) => current,
      persist: () async => saves++,
      publish: () {},
    );

    coordinator.observe(opened, 100);
    current = _audio(
      'changed',
      duration: 30,
      modified: opened.modified + 1,
      modifiedNanos: '20000000002',
    );
    await coordinator.settled;

    expect(current.duration, 30);
    expect(current.durationVersion, 0);
    expect(saves, 0);
  });

  test('busy library retries off the playback path then persists', () async {
    final gate = LibraryMutationGate();
    final release = Completer<void>();
    final occupied = gate.run(() => release.future);
    final audio = _audio('busy');
    var delays = 0;
    var saves = 0;
    final errors = <Object>[];
    final coordinator = AudioDurationCorrectionCoordinator(
      gate: gate,
      lookup: (_) => audio,
      persist: () async => saves++,
      publish: () {},
      delay: (_) async {
        delays++;
        release.complete();
        await occupied;
      },
      onError: (error, _) => errors.add(error),
    );

    coordinator.observe(audio, 75);
    await coordinator.settled;

    expect(delays, 1);
    expect(saves, 1);
    expect(audio.duration, 75);
    expect(errors, isEmpty);
    expect(gate.isBusy, isFalse);
  });

  test('online durations never enter the local index correction queue',
      () async {
    final online = Audio.online(
      provider: 'fixture',
      id: 'remote',
      title: 'Remote',
      artist: 'Fixture',
      album: 'Synthetic',
      duration: 20,
    );
    var saves = 0;
    final coordinator = AudioDurationCorrectionCoordinator(
      lookup: (_) => online,
      persist: () async => saves++,
      publish: () {},
    );

    coordinator.observe(online, 200);
    await coordinator.settled;

    expect(online.duration, 20);
    expect(saves, 0);
  });
}
