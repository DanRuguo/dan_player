import 'package:dan_player/play_service/guarded_playback_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slow local open cannot seek the retained old decoder', () {
    final calls = <String>[];
    final applied = guardedManualPlaybackSeek(
      queueEditable: false,
      buffering: false,
      hasSource: true,
      hasTrack: true,
      duration: () {
        calls.add('duration');
        return 120;
      },
      target: 45,
      seekAndRead: (_) {
        calls.add('native seek');
        return 45;
      },
      commit: (_) => calls.add('practice and resume'),
    );
    expect(applied, isFalse);
    expect(calls, isEmpty);
  });

  test('online buffering or missing decoder never commits seek intent', () {
    for (final (buffering, hasSource) in [(true, true), (false, false)]) {
      var nativeSeeks = 0;
      var committed = 0;
      final applied = guardedManualPlaybackSeek(
        queueEditable: true,
        buffering: buffering,
        hasSource: hasSource,
        hasTrack: true,
        duration: () => 120,
        target: 45,
        seekAndRead: (_) {
          nativeSeeks++;
          return 45;
        },
        commit: (_) => committed++,
      );
      expect(applied, isFalse);
      expect(nativeSeeks, 0);
      expect(committed, 0);
    }
  });

  test('failed native seek leaves practice and resume intent intact', () {
    var committed = false;
    expect(
      () => guardedManualPlaybackSeek(
        queueEditable: true,
        buffering: false,
        hasSource: true,
        hasTrack: true,
        duration: () => 120,
        target: 45,
        seekAndRead: (_) => throw StateError('native seek rejected'),
        commit: (_) => committed = true,
      ),
      throwsStateError,
    );
    expect(committed, isFalse);
  });

  test('successful seek commits the native position, not the requested one',
      () {
    double? stored;
    expect(
      guardedManualPlaybackSeek(
        queueEditable: true,
        buffering: false,
        hasSource: true,
        hasTrack: true,
        duration: () => 120,
        target: 45.125,
        seekAndRead: (_) => 45.1,
        commit: (actual) => stored = actual,
      ),
      isTrue,
    );
    expect(stored, 45.1);
  });
}
