import 'package:dan_player/play_service/sleep_timer.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'finish-current sleep boundary is cancelable and remains on exact occurrence',
      () {
    final boundary = QueueStopBoundary()
      ..loading(12, 51)
      ..arm(99);
    addTearDown(boundary.dispose);
    boundary.sleepExpired();
    boundary.arm(12);
    boundary.resumeAdvance();
    expect(boundary.complete(12, 50), isFalse,
        reason: 'A previous open of the same CUE occurrence cannot finish it.');
    expect(boundary.complete(13, 51), isFalse,
        reason: 'Another occurrence/segment of the same file is independent.');
    boundary.cancel(QueueStopCancelReason.userCancelled);
    expect(boundary.canAdvanceAutomatically, isTrue);
    boundary.arm(12);
    boundary.manualJump([12, 13], 0, 1, adjacent: true);
    boundary.loading(13, 52);
    expect(boundary.target, isNull);
    expect(boundary.complete(12, 51), isFalse);
    expect(boundary.canAdvanceAutomatically, isTrue);
    boundary.arm(13);
    expect(boundary.complete(13, 52), isTrue);
    expect(boundary.canAdvanceAutomatically, isFalse);
  });
  test('paused timer has no ticker, resumes remainder and expires only once',
      () {
    fakeAsync((time) {
      final expired = <bool>[];
      final start = DateTime(2026, 9, 27, 23, 59);
      final controller = SleepTimerController(
          onElapsed: expired.add, now: () => start.add(time.elapsed));
      controller.start(const Duration(minutes: 3));
      time.elapse(const Duration(seconds: 27));
      controller.togglePaused();
      expect(
          controller.remaining.value, const Duration(minutes: 2, seconds: 33));
      expect(controller.paused.value, isTrue);
      expect(time.periodicTimerCount, 0);
      time.elapse(const Duration(hours: 2));
      expect(
          controller.remaining.value, const Duration(minutes: 2, seconds: 33));
      controller.adjust(const Duration(minutes: 5));
      expect(controller.paused.value, isTrue);
      expect(time.periodicTimerCount, 0);
      controller.finishCurrent.value = true;
      controller.togglePaused();
      time.elapse(const Duration(minutes: 7, seconds: 33));
      expect(expired, [true]);
      expect(controller.remaining.value, isNull);
      expect(controller.paused.value, isFalse);
      expect(time.periodicTimerCount, 0);
      time.elapse(const Duration(minutes: 10));
      expect(expired, [true]);
      controller.dispose();
    });
  });

  test('restart and cancel cannot deliver an old expiry', () {
    fakeAsync((time) {
      final expired = <bool>[];
      final base = DateTime(2026);
      final controller = SleepTimerController(
          onElapsed: expired.add, now: () => base.add(time.elapsed));
      controller.start(const Duration(seconds: 2));
      time.elapse(const Duration(seconds: 1));
      controller.start(const Duration(seconds: 5));
      time.elapse(const Duration(seconds: 2));
      expect(expired, isEmpty);
      expect(time.periodicTimerCount, 1);
      controller.cancel();
      time.elapse(const Duration(seconds: 10));
      expect(expired, isEmpty);
      expect(time.periodicTimerCount, 0);
      controller.start(const Duration(seconds: 1));
      time.elapse(const Duration(seconds: 1));
      expect(expired, [false]);
      controller.dispose();
    });
  });

  test(
      'clock jump after machine suspend consumes countdown, pause at expiry stops',
      () {
    fakeAsync((time) {
      var now = DateTime(2026);
      var expired = 0;
      final controller =
          SleepTimerController(onElapsed: (_) => expired++, now: () => now);
      controller.start(const Duration(minutes: 10));
      now = now.add(const Duration(hours: 1));
      controller.togglePaused();
      expect(expired, 1);
      expect(controller.paused.value, isFalse);
      expect(controller.remaining.value, isNull);
      expect(time.periodicTimerCount, 0);
      controller.dispose();
    });
  });

  test(
      'range clamps, shrinking keeps positive remainder, dispose releases ticker',
      () {
    fakeAsync((time) {
      final base = DateTime(2026);
      final controller = SleepTimerController(
          onElapsed: (_) {}, now: () => base.add(time.elapsed));
      controller.start(const Duration(days: 999));
      expect(controller.remaining.value, const Duration(hours: 24));
      controller.adjust(const Duration(days: 999));
      expect(controller.remaining.value, const Duration(hours: 24));
      controller.adjust(const Duration(days: -999));
      expect(controller.remaining.value, const Duration(seconds: 1));
      controller.dispose();
      expect(time.periodicTimerCount, 0);
      controller.start(const Duration(minutes: 10));
      expect(time.periodicTimerCount, 0);
    });
  });

  test('display rounds up fractional seconds and handles hours', () {
    expect(formatSleepRemaining(const Duration(milliseconds: 59999)), '01:00');
    expect(formatSleepRemaining(const Duration(milliseconds: 1)), '00:01');
    expect(formatSleepRemaining(const Duration(hours: 24)), '24:00:00');
    expect(formatSleepRemaining(const Duration(seconds: -1)), '00:00');
  });
}
