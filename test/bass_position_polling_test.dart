import 'dart:async';

import 'package:dan_player/src/bass/bass_diagnostics.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source cancellation cannot restart a poll cancelled by pause', () {
    fakeAsync((clock) {
      var samples = 0;
      var created = 0;
      Timer create() {
        created++;
        return Timer.periodic(
            const Duration(milliseconds: 33), (_) => samples++);
      }

      final pausedPoll = create();
      clock.elapse(const Duration(milliseconds: 99));
      expect(samples, 3);
      pausedPoll.cancel();
      final afterSourceCommand =
          rearmBassPositionUpdater(pausedPoll, freed: false, create: create);
      clock.elapse(const Duration(seconds: 5));
      expect(afterSourceCommand, isNull);
      expect(created, 1);
      expect(samples, 3);
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('new source stamp preserves exactly one poll for retained playback', () {
    fakeAsync((clock) {
      var oldSamples = 0, currentSamples = 0;
      final old =
          Timer.periodic(const Duration(milliseconds: 33), (_) => oldSamples++);
      clock.elapse(const Duration(milliseconds: 99));
      final current = rearmBassPositionUpdater(old,
          freed: false,
          create: () => Timer.periodic(
              const Duration(milliseconds: 33), (_) => currentSamples++));
      clock.elapse(const Duration(milliseconds: 99));
      expect(oldSamples, 3);
      expect(currentSamples, 3);
      expect(clock.periodicTimerCount, 1);
      expect(
          rearmBassPositionUpdater(current,
              freed: true, create: () => fail('shutdown must not poll')),
          isNull);
      clock.elapse(const Duration(seconds: 5));
      expect(currentSamples, 3);
      expect(clock.periodicTimerCount, 0);
    });
  });
}
