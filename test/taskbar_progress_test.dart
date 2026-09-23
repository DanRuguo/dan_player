import 'dart:async';

import 'package:dan_player/taskbar_progress.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('power modes cover playback progress and recover legacy snapshots', () {
    final original = PerformanceSnapshot.capture(
        const RenderingPreferences(),
        const BackgroundPreferences(),
        const PlayerExperiencePreferences(taskbarPlaybackProgress: false),
        false);
    expect(original.forMode(PerformanceMode.economy).taskbarPlaybackProgress,
        isFalse);
    expect(
        original.forMode(PerformanceMode.performance).taskbarPlaybackProgress,
        isTrue);
    expect(
        PerformanceSnapshot.fromMap(original.toMap())!.taskbarPlaybackProgress,
        isFalse);
    final legacy = original.toMap()..remove('taskbarPlaybackProgress');
    expect(
        PerformanceSnapshot.fromMap(legacy)!.taskbarPlaybackProgress, isTrue);
    expect(original.forMode(PerformanceMode.custom).taskbarPlaybackProgress,
        isFalse);
  });
  test(
      'newest operation keeps ownership and late callbacks cannot resurrect it',
      () {
    final tasks = TaskbarProgress();
    final first = tasks.begin()..update(.2);
    final second = tasks.begin();
    expect(tasks.value, TaskbarProgressValue.indeterminate);
    first.update(.9);
    expect(tasks.value, TaskbarProgressValue.indeterminate);
    second.update(.5);
    expect(tasks.value!.completed, 500);
    second.dispose();
    expect(tasks.value!.completed, 900);
    second.update(.8);
    second.dispose();
    expect(tasks.value!.completed, 900);
    first.dispose();
    expect(tasks.value, isNull);
    tasks.dispose();
    first.update(1);
  });

  test('unknown totals and malformed fractions never invent progress', () {
    final tasks = TaskbarProgress();
    final task = tasks.begin();
    for (final value in [null, double.nan, double.infinity]) {
      task.update(value);
      expect(tasks.value, TaskbarProgressValue.indeterminate);
    }
    task.update(-1);
    expect(tasks.value!.completed, 0);
    task.update(7);
    expect(tasks.value!.completed, 1000);
    task.dispose();
    tasks.dispose();
  });

  test('progress bursts coalesce, remain current and leave no idle polling',
      () {
    fakeAsync((clock) {
      final tasks = TaskbarProgress();
      final calls = <Map<String, Object>>[];
      final publisher = TaskbarProgressPublisher(
          operations: tasks,
          invoke: (_, value) async {
            calls.add(value);
            return null;
          });
      for (var i = 0; i < 300; i++) {
        publisher.setPlayback(TaskbarProgressValue.fraction(i / 300));
        clock.elapse(const Duration(milliseconds: 33));
      }
      clock.elapse(const Duration(milliseconds: 300));
      expect(calls.length, lessThanOrEqualTo(42));
      expect(calls.last['completed'], 997);
      final before = calls.length;
      clock.elapse(const Duration(hours: 1));
      expect(calls.length, before);
      expect(clock.pendingTimers, isEmpty);
      unawaited(publisher.dispose());
      clock.elapse(Duration.zero);
      expect(calls.last['state'], 'none');
      tasks.dispose();
    });
  });

  test('operations override playback; clearing restores the latest paused seek',
      () {
    fakeAsync((clock) {
      final tasks = TaskbarProgress();
      final calls = <Map<String, Object>>[];
      final publisher = TaskbarProgressPublisher(
          operations: tasks,
          invoke: (_, value) async {
            calls.add(value);
            return null;
          });
      publisher.setPlayback(TaskbarProgressValue.fraction(.2));
      clock.elapse(Duration.zero);
      final task = tasks.begin();
      clock.elapse(Duration.zero);
      expect(calls.last, {'state': 'indeterminate'});
      publisher.setPlayback(TaskbarProgressValue.fraction(.7, paused: true));
      clock.elapse(const Duration(seconds: 1));
      expect(calls.last['state'], 'indeterminate');
      task.update(.5);
      clock.elapse(Duration.zero);
      expect(calls.last['completed'], 500);
      task.dispose();
      clock.elapse(Duration.zero);
      expect(calls.last, {'state': 'paused', 'completed': 700, 'total': 1000});
      publisher.setPlayback(TaskbarProgressValue.none);
      clock.elapse(Duration.zero);
      expect(calls.last, {'state': 'none'});
      unawaited(publisher.dispose());
      clock.elapse(Duration.zero);
      tasks.dispose();
    });
  });

  test(
      'slow native call has only one latest pending value, and shutdown clears',
      () {
    fakeAsync((clock) {
      final tasks = TaskbarProgress();
      final held = Completer<Object?>();
      final calls = <Map<String, Object>>[];
      final publisher = TaskbarProgressPublisher(
          operations: tasks,
          invoke: (_, value) {
            calls.add(value);
            return calls.length == 1 ? held.future : Future.value();
          });
      final task = tasks.begin();
      clock.elapse(Duration.zero);
      for (var i = 0; i <= 10000; i++) {
        task.update(i / 10000);
      }
      expect(calls.length, 1);
      held.complete(null);
      clock.elapse(Duration.zero);
      expect(calls.length, 2);
      expect(calls.last['completed'], 1000);
      unawaited(publisher.dispose());
      clock.elapse(Duration.zero);
      expect(calls.last['state'], 'none');
      task.update(.1);
      clock.elapse(const Duration(seconds: 1));
      expect(calls.length, 3);
      task.dispose();
      tasks.dispose();
    });
  });

  test('failed native channel does not retry on every position report', () {
    fakeAsync((clock) {
      final tasks = TaskbarProgress();
      var calls = 0;
      var fail = true;
      final publisher = TaskbarProgressPublisher(
          operations: tasks,
          invoke: (_, value) async {
            calls++;
            if (fail) throw StateError('offline');
            return null;
          });
      for (var i = 0; i < 100; i++) {
        publisher.setPlayback(TaskbarProgressValue.fraction(i / 100));
        clock.elapse(const Duration(milliseconds: 100));
      }
      expect(calls, 1);
      expect(clock.pendingTimers, isEmpty);
      fail = false;
      publisher.retry();
      clock.elapse(Duration.zero);
      expect(calls, 2);
      unawaited(publisher.dispose());
      clock.elapse(Duration.zero);
      expect(calls, 3);
      tasks.dispose();
    });
  });
}
