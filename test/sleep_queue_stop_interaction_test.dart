import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/sleep_timer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise the real countdown and occurrence boundary together. Native pause,
/// output reopening and preview intent remain owned by PlaybackService.
void main() {
  for (final cancelTimer in [false, true]) {
    test('cancel ${cancelTimer ? 'timer' : 'target'} preserves the other stop',
        () {
      fakeAsync((time) {
        final boundary = QueueStopBoundary()
          ..loading(12, 51)
          ..arm(12);
        final expired = <bool>[];
        final base = DateTime(2026, 10, 1);
        final timer = SleepTimerController(
            now: () => base.add(time.elapsed),
            onElapsed: (finishCurrent) {
              expired.add(finishCurrent);
              boundary.sleepExpired();
            });
        try {
          timer.start(const Duration(seconds: 10));
          expect(boundary.target, 12);
          if (cancelTimer) {
            timer.cancel();
            expect(boundary.target, 12);
            expect(boundary.complete(12, 51), isTrue);
          } else {
            boundary.cancel(QueueStopCancelReason.userCancelled);
            expect(timer.remaining.value, const Duration(seconds: 10));
          }
          time.elapse(const Duration(seconds: 20));
          expect(expired, cancelTimer ? isEmpty : [false]);
          expect(boundary.target, isNull);
          expect(time.periodicTimerCount, 0);
        } finally {
          timer.dispose();
          boundary.dispose();
        }
      });
    });
  }

  test('timer first consumes the old target and blocks its queued completion',
      () {
    fakeAsync((time) {
      final boundary = QueueStopBoundary()
        ..loading(12, 51)
        ..arm(13);
      final expired = <bool>[];
      final base = DateTime(2026, 10, 1);
      final timer = SleepTimerController(
          now: () => base.add(time.elapsed),
          onElapsed: (finishCurrent) {
            expired.add(finishCurrent);
            boundary.sleepExpired();
          });
      try {
        timer.start(const Duration(seconds: 1));
        time.elapse(const Duration(seconds: 1));
        expect(expired, [false]);
        expect(boundary.lastCancellation, QueueStopCancelReason.sleepTimer);
        expect(boundary.target, isNull);
        expect(boundary.canAdvanceAutomatically, isFalse);
        expect(boundary.complete(12, 51), isFalse);
        boundary.loading(13, 52); // A later explicit selection may play.
        expect(boundary.canAdvanceAutomatically, isTrue);
        expect(boundary.complete(13, 52), isFalse,
            reason: 'The earlier target must not stop later user playback.');
        time.elapse(const Duration(minutes: 1));
        expect(expired, [false]);
      } finally {
        timer.dispose();
        boundary.dispose();
      }
    });
  });

  test('target first leaves the independently configured countdown effective',
      () {
    fakeAsync((time) {
      final boundary = QueueStopBoundary()
        ..loading(12, 51)
        ..arm(12);
      final expired = <bool>[];
      final base = DateTime(2026, 10, 1);
      final timer = SleepTimerController(
          now: () => base.add(time.elapsed),
          onElapsed: (finishCurrent) {
            expired.add(finishCurrent);
            boundary.sleepExpired();
          });
      try {
        timer.start(const Duration(seconds: 10));
        time.elapse(const Duration(seconds: 2));
        expect(boundary.complete(12, 51), isTrue);
        expect(boundary.complete(12, 51), isFalse);
        expect(boundary.canAdvanceAutomatically, isFalse);
        expect(timer.remaining.value, const Duration(seconds: 8));
        expect(time.periodicTimerCount, 1);
        boundary.loading(13, 52); // Explicit playback does not cancel sleep.
        time.elapse(const Duration(seconds: 8));
        expect(expired, [false]);
        expect(boundary.canAdvanceAutomatically, isFalse);
        expect(boundary.target, isNull);
        expect(timer.remaining.value, isNull);
      } finally {
        timer.dispose();
        boundary.dispose();
      }
    });
  });

  for (final timerFirst in [false, true]) {
    test('coincident deadline and target settle once timerFirst=$timerFirst',
        () {
      fakeAsync((time) {
        final boundary = QueueStopBoundary()
          ..loading(12, 51)
          ..arm(12);
        final expired = <bool>[];
        final base = DateTime(2026, 10, 1);
        final timer = SleepTimerController(
            now: () => base.add(time.elapsed),
            onElapsed: (finishCurrent) {
              expired.add(finishCurrent);
              boundary.sleepExpired();
            });
        try {
          timer.start(const Duration(seconds: 1));
          if (timerFirst) time.elapse(const Duration(seconds: 1));
          expect(boundary.complete(12, 51), !timerFirst);
          if (!timerFirst) time.elapse(const Duration(seconds: 1));
          expect(boundary.complete(12, 51), isFalse);
          expect(boundary.active, isFalse);
          expect(boundary.canAdvanceAutomatically, isFalse);
          expect(expired, [false]);
          expect(time.periodicTimerCount, 0);
          time.elapse(const Duration(minutes: 1));
          expect(expired, [false]);
        } finally {
          timer.dispose();
          boundary.dispose();
        }
      });
    });
  }

  test('finish-current expiry replaces a later target with the exact live one',
      () {
    fakeAsync((time) {
      final boundary = QueueStopBoundary()
        ..loading(12, 51)
        ..arm(13);
      final expired = <bool>[];
      final base = DateTime(2026, 10, 1);
      final timer = SleepTimerController(
          now: () => base.add(time.elapsed),
          onElapsed: (finishCurrent) {
            expired.add(finishCurrent);
            boundary.sleepExpired();
            if (finishCurrent) {
              boundary.arm(12);
              boundary.resumeAdvance();
            }
          });
      try {
        timer.finishCurrent.value = true;
        timer.start(const Duration(seconds: 1));
        time.elapse(const Duration(seconds: 1));
        expect(expired, [true]);
        expect(timer.remaining.value, isNull);
        expect(boundary.target, 12);
        expect(boundary.canAdvanceAutomatically, isTrue);
        expect(boundary.complete(12, 50), isFalse);
        expect(boundary.complete(13, 51), isFalse);
        expect(boundary.complete(12, 51), isTrue);
        expect(boundary.canAdvanceAutomatically, isFalse);
        boundary.loading(13, 52);
        expect(boundary.complete(13, 52), isFalse);
        time.elapse(const Duration(minutes: 1));
        expect(expired, [true]);
      } finally {
        timer.dispose();
        boundary.dispose();
      }
    });
  });

  test('target completion does not resume or consume a paused countdown', () {
    fakeAsync((time) {
      final boundary = QueueStopBoundary()
        ..loading(12, 51)
        ..arm(12);
      final expired = <bool>[];
      final base = DateTime(2026, 10, 1);
      final timer = SleepTimerController(
          now: () => base.add(time.elapsed),
          onElapsed: (finishCurrent) {
            expired.add(finishCurrent);
            boundary.sleepExpired();
          });
      try {
        timer.start(const Duration(seconds: 10));
        time.elapse(const Duration(seconds: 2));
        timer.togglePaused();
        expect(boundary.complete(12, 51), isTrue);
        time.elapse(const Duration(hours: 1));
        expect(timer.remaining.value, const Duration(seconds: 8));
        expect(timer.paused.value, isTrue);
        expect(time.periodicTimerCount, 0);
        expect(expired, isEmpty);
        timer.togglePaused();
        time.elapse(const Duration(seconds: 8));
        expect(expired, [false]);
        expect(boundary.target, isNull);
        expect(boundary.canAdvanceAutomatically, isFalse);
      } finally {
        timer.dispose();
        boundary.dispose();
      }
    });
  });
}
