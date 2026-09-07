import 'dart:io';

import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local BASS file open stays off the Flutter UI isolate', () {
    final source = File('lib/src/bass/bass_player.dart').readAsStringSync();
    final setSourceStart = source.indexOf('Future<bool> _setSource(');
    final errorMapperStart = source.indexOf(
      'static PlaybackProblem _sourceOpenException',
      setSourceStart,
    );

    expect(setSourceStart, greaterThanOrEqualTo(0));
    expect(errorMapperStart, greaterThan(setSourceStart));
    final setSource = source.substring(setSourceStart, errorMapperStart);

    expect(setSource, contains('await _openBassFileInBackground('));
    expect(setSource, isNot(contains('BASS_StreamCreateFile')));
    expect(source, contains("debugName: 'bass-file-open'"));
  });

  test('shutdown waits until background file handles are reclaimed', () {
    final source = File('lib/src/bass/bass_player.dart').readAsStringSync();

    expect(source, contains('_pendingFileOpens.add(pendingFile)'));
    expect(source, contains('_pendingFileOpens.remove(pendingFile)'));
    expect(
      source,
      contains(
        'for (final request in _pendingFileOpens) request.finished.future',
      ),
    );
  });

  test('file-open gate bounds workers and drops stale queued requests',
      () async {
    final gate = BassFileOpenGate(limit: 2);
    var generation = 1;
    expect(await gate.acquire(() => generation == 1), isTrue);
    expect(await gate.acquire(() => generation == 1), isTrue);

    var thirdCompleted = false;
    final staleThird = gate.acquire(() => generation == 1).then((value) {
      thirdCompleted = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);
    expect(thirdCompleted, isFalse);

    generation = 2;
    var latestCompleted = false;
    final latest = gate.acquire(() => generation == 2).then((value) {
      latestCompleted = true;
      return value;
    });
    expect(await staleThird, isFalse);
    expect(latestCompleted, isFalse);

    gate.release();
    expect(await latest, isTrue);
    gate.release();
    gate.release();
  });

  test('shutdown wakes queued file opens without starting them', () async {
    final gate = BassFileOpenGate(limit: 1);
    var running = true;
    expect(await gate.acquire(() => running), isTrue);
    final queued = gate.acquire(() => running);
    running = false;
    gate.cancelWaiters();
    expect(await queued, isFalse);
    gate.release();
  });

  test('local playback shares pending-path cancellation and deletion wait', () {
    final playback =
        File('lib/play_service/playback_service.dart').readAsStringSync();

    expect(
      RegExp(r'resolvingAudioPath\.value = target\.path;')
          .allMatches(playback)
          .length,
      2,
    );
    expect(playback, contains('final wasPending = _sameAudioPath('));
    expect(playback, contains('if (wasCurrent || wasPending)'));
    expect(
        playback, contains('await _player.waitForPendingFileOpen(audioPath)'));
    expect(playback, contains('_sameAudioPath(_deletingAudioPath'));
  });
}
