import 'dart:async';

import 'package:dan_player/src/bass/bass_player.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stalled seek keeps recovery position and completion observation', () {
    fakeAsync((clock) {
      var state = PlayerState.stalled;
      var position = 0.0;
      var completions = 0;
      final positions = <double>[];
      Timer create() =>
          Timer.periodic(const Duration(milliseconds: 33), (poll) {
            positions.add(position);
            if (state == PlayerState.stopped) {
              completions++;
              poll.cancel();
            }
          });

      final old = create();
      final afterSeek = rearmBassPositionUpdaterAfterSeek(
        old,
        stateBeforeSeek: state,
        create: create,
      );
      expect(old.isActive, isFalse);
      expect(afterSeek?.isActive, isTrue);
      expect(clock.periodicTimerCount, 1);

      // Buffer refill resumes BASS itself; no user play command restarts a
      // timer. The retained poll must observe its position and later EOF.
      state = PlayerState.playing;
      position = .25;
      clock.elapse(const Duration(milliseconds: 33));
      expect(positions, [.25]);
      state = PlayerState.stopped;
      position = .5;
      clock.elapse(const Duration(milliseconds: 99));
      expect(positions, [.25, .5]);
      expect(completions, 1);
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('repeated stalled seeks replace the poll without accumulating timers',
      () {
    fakeAsync((clock) {
      var created = 0;
      final observed = <int>[];
      Timer create() {
        final generation = ++created;
        return Timer.periodic(const Duration(milliseconds: 33), (_) {
          observed.add(generation);
        });
      }

      Timer? poll = create();
      for (var seek = 0; seek < 5; seek++) {
        poll = rearmBassPositionUpdaterAfterSeek(
          poll,
          stateBeforeSeek: PlayerState.stalled,
          create: create,
        );
        expect(clock.periodicTimerCount, 1);
      }
      clock.elapse(const Duration(milliseconds: 99));
      expect(created, 6);
      expect(observed, [6, 6, 6]);
      poll?.cancel();
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('inactive seek states never revive position sampling', () {
    fakeAsync((clock) {
      for (final state in [
        PlayerState.paused,
        PlayerState.pausedDevice,
        PlayerState.stopped,
        PlayerState.completed,
        PlayerState.unknown,
      ]) {
        final previous = Timer.periodic(const Duration(milliseconds: 33), (_) {
          fail('The old seek stamp must not publish.');
        });
        final afterSeek = rearmBassPositionUpdaterAfterSeek(
          previous,
          stateBeforeSeek: state,
          create: () => fail('$state must not resume polling'),
        );
        expect(afterSeek, isNull);
        expect(previous.isActive, isFalse);
        expect(clock.periodicTimerCount, 0);
      }
      clock.elapse(const Duration(seconds: 2));
    });
  });

  test('playing seek rearms a poll even after an output flush cancelled it',
      () {
    fakeAsync((clock) {
      var samples = 0;
      final cancelled =
          Timer.periodic(const Duration(milliseconds: 33), (_) {});
      cancelled.cancel();
      final afterSeek = rearmBassPositionUpdaterAfterSeek(
        cancelled,
        stateBeforeSeek: PlayerState.playing,
        create: () => Timer.periodic(const Duration(milliseconds: 33), (_) {
          samples++;
        }),
      );
      clock.elapse(const Duration(milliseconds: 99));
      expect(samples, 3);
      expect(clock.periodicTimerCount, 1);
      afterSeek?.cancel();
      expect(clock.periodicTimerCount, 0);
    });
  });
}
