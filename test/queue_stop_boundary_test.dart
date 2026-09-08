import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:dan_player/play_service/playback_modes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('frozen round follows its exact duplicate through edits and shuffle',
      () {
    final first = QueueOccurrence('same');
    final other = QueueOccurrence('other');
    final last = QueueOccurrence('same');
    var queue = [first, other, last];
    final boundary = QueueStopBoundary()..arm(queue.last.id);
    addTearDown(boundary.dispose);
    queue =
        QueueEdit.insert(queue, 0, [QueueOccurrence('appended')], next: false)
            .items;
    queue = QueueEdit.moveNext(queue, 0, 2)!.items;
    expect(queue[1].id, last.id);
    boundary.retain(queue.map((entry) => entry.id));
    final shuffled = ShuffleQueueCycle(queue, startIndex: 0);
    queue = shuffled.items;
    boundary.retain(queue.map((entry) => entry.id));
    expect(boundary.target, last.id);
    boundary.loading(first.id, 1);
    expect(boundary.complete(first.id, 1), isFalse);
    boundary.loading(last.id, 2);
    expect(boundary.complete(last.id, 2), isTrue);
    expect(boundary.canAdvanceAutomatically, isFalse,
        reason:
            'The one-shot stop wins before list-repeat or a duplicate completion');
    expect(boundary.complete(last.id, 2), isFalse);
    expect(boundary.active, isFalse);
    boundary.resumeAdvance();
    expect(boundary.canAdvanceAutomatically, isTrue);
  });

  test(
      'removal, source replacement and failure cancel explicitly without transfer',
      () {
    final boundary = QueueStopBoundary()..arm(2);
    addTearDown(boundary.dispose);
    boundary.retain([1, 3]);
    expect(boundary.lastCancellation, QueueStopCancelReason.removed);
    boundary.arm(2);
    boundary.cancel(QueueStopCancelReason.sourceReplaced);
    expect(boundary.lastCancellation, QueueStopCancelReason.sourceReplaced);
    boundary.arm(2);
    boundary.loading(2, 3);
    boundary.failed(2, 2);
    expect(boundary.active, isTrue);
    boundary.failed(2, 3);
    expect(boundary.lastCancellation, QueueStopCancelReason.targetFailed);
    expect(boundary.complete(2, 3), isFalse);
  });

  test('manual jumps cancel passed boundaries but adjacent wrap does not guess',
      () {
    final boundary = QueueStopBoundary()..arm(2);
    addTearDown(boundary.dispose);
    boundary.manualJump([1, 2, 3], 0, 1);
    expect(boundary.active, isTrue, reason: 'Selecting the target is allowed');
    boundary.manualJump([1, 2, 3], 1, 1);
    expect(boundary.active, isTrue,
        reason: 'Restarting the same occurrence is allowed');
    boundary.manualJump([1, 2, 3], 1, 2, adjacent: true);
    expect(boundary.lastCancellation, QueueStopCancelReason.manuallyPassed);
    boundary.arm(2);
    boundary.manualJump([1, 2, 3], 2, 0, adjacent: true);
    expect(boundary.active, isTrue);
    boundary.manualJump([1, 2, 3], 0, 2);
    expect(boundary.lastCancellation, QueueStopCancelReason.manuallyPassed);
    boundary.arm(2);
    boundary.manualJump([1, 2, 3], 2, 0);
    expect(boundary.lastCancellation, QueueStopCancelReason.manuallyPassed);
  });

  test(
      'A-B-A stale completion and sleep races cannot consume or pass a new boundary',
      () {
    final boundary = QueueStopBoundary()
      ..arm(1)
      ..loading(1, 10);
    addTearDown(boundary.dispose);
    boundary.loading(2, 11);
    boundary.loading(1, 12);
    expect(boundary.complete(1, 10), isFalse);
    expect(boundary.target, 1);
    boundary.sleepExpired();
    expect(boundary.lastCancellation, QueueStopCancelReason.sleepTimer);
    expect(boundary.complete(1, 12), isFalse);
    expect(boundary.canAdvanceAutomatically, isFalse,
        reason:
            'A completion already queued at the sleep deadline must not open another source');
    boundary.loading(1, 13); // A new explicit selection after the timer.
    expect(boundary.canAdvanceAutomatically, isTrue);
    boundary.arm(1);
    expect(boundary.complete(1, 12), isFalse);
    expect(boundary.complete(1, 13), isTrue);
  });
}
