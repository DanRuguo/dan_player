import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:dan_player/lyric/lyric_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Process implements TrimPreviewProcess {
  _Process({this.delayedExit = false});
  final bool delayedExit;
  final done = Completer<int>();
  int kills = 0;
  @override
  Future<int> get exitCode => done.future;
  @override
  void kill() {
    kills++;
    if (!delayedExit && !done.isCompleted) done.complete(0);
  }
}

class _Fixture {
  _Fixture() {
    final temporary = Directory.systemTemp.absolute.path;
    if (!temporary.replaceAll('\\', '/').contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    preview = LyricAudioPreview(
        Audio('Synthetic', 'Fixture', '', 0, 100, null, null,
            p.join(temporary, 'preview-seek.wav'), 0, 0, null),
        mainPlayback: () => null,
        launch: (_, start, duration, clock) async {
          ranges.add((start, start + duration));
          clocks.add(clock);
          final process = _Process(delayedExit: processes.isEmpty);
          processes.add(process);
          return process;
        });
  }

  late final LyricAudioPreview preview;
  final processes = <_Process>[];
  final ranges = <(double, double)>[];
  final clocks = <void Function(double)>[];

  Future<void> close() async {
    for (final process in processes) {
      if (!process.done.isCompleted) process.done.complete(0);
    }
    await preview.close();
    preview.dispose();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'paused seek reaping an old decoder cannot replace a newer playing range',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.preview.play(1, 3);
    final seek = fixture.preview.seekPaused(2);
    await _flush();
    expect(fixture.processes.single.kills, 1);
    final replay = fixture.preview.play(4, 6);
    await _flush();
    fixture.processes.first.done.complete(0);
    await Future.wait([seek, replay]);
    expect(fixture.ranges, [(1.0, 3.0), (4.0, 6.0)]);
    expect(fixture.preview.position, 4);
    fixture.clocks.last(4.5);
    expect(fixture.preview.position, 4.5);
    fixture.processes.last.done.complete(0);
    await _flush();
    expect(fixture.preview.position, 6,
        reason: 'The older seek must not replace the new completion endpoint');
  });

  test('latest paused seek wins while two requests await the same decoder exit',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.preview.play(1, 9);
    final earlier = fixture.preview.seekPaused(2);
    await _flush();
    final latest = fixture.preview.seekPaused(5);
    fixture.processes.first.done.complete(0);
    await Future.wait([earlier, latest]);
    expect(fixture.preview.position, 5);
    expect(fixture.preview.playing, isFalse);
    expect(fixture.processes.length, 1);
  });

  test('close revokes a paused seek still waiting for its decoder to exit',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.preview.play(1, 3);
    final positions = <double>[];
    final sub = fixture.preview.positionStream.listen(positions.add);
    addTearDown(sub.cancel);
    final seek = fixture.preview.seekPaused(2);
    await _flush();
    final close = fixture.preview.close();
    fixture.processes.first.done.complete(0);
    await Future.wait([seek, close]);
    expect(fixture.preview.position, 1);
    expect(positions, isEmpty,
        reason: 'Closing cannot publish a revoked paused-seek result');
    await fixture.preview.seekPaused(8);
    expect(fixture.preview.position, 1);
  });
}
