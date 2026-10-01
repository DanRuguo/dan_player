import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_stop_boundary.dart';
import 'package:dan_player/play_service/queue_stop_count_selection.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('count includes the current occurrence and cannot wrap or exceed suffix',
      () {
    final queue = Object();
    final choice = QueueStopCountSelection.capture(
        queueIdentity: queue,
        sourceSession: 7,
        currentIndex: 3,
        queueLength: 7)!;
    expect(choice.remainingCount, 4);
    expect(choice.targetIndex(1), 3);
    expect(choice.targetIndex(3), 5);
    expect(choice.targetIndex(4), 6);
    expect(choice.targetIndex(0), isNull);
    expect(choice.targetIndex(-1), isNull);
    expect(choice.targetIndex(5), isNull);
  });

  test('missing current occurrence and empty queue have no count choice', () {
    for (final (current, length) in [(-1, 3), (0, 0), (3, 3), (0, -1)]) {
      expect(
          QueueStopCountSelection.capture(
              queueIdentity: Object(),
              sourceSession: 7,
              currentIndex: current,
              queueLength: length),
          isNull);
    }
  });

  test('queue replacement, current movement and source ABA invalidate a choice',
      () {
    final queue = Object();
    final choice = QueueStopCountSelection.capture(
        queueIdentity: queue,
        sourceSession: 7,
        currentIndex: 1,
        queueLength: 4)!;
    bool matches(
            {Object? identity,
            int session = 7,
            int current = 1,
            int length = 4}) =>
        choice.isCurrent(
            queueIdentity: identity ?? queue,
            sourceSession: session,
            currentIndex: current,
            queueLength: length);
    expect(matches(), isTrue);
    expect(matches(identity: Object()), isFalse);
    expect(matches(current: 2), isFalse);
    expect(matches(length: 5), isFalse);
    expect(matches(session: 9), isFalse,
        reason: 'A -> B -> A is still a new source session.');
  });

  test('confirmed count freezes the exact duplicate through later queue edits',
      () {
    final first = QueueOccurrence('same');
    final other = QueueOccurrence('other');
    final duplicate = QueueOccurrence('same');
    var entries = [first, other, duplicate];
    final choice = QueueStopCountSelection.capture(
        queueIdentity: entries,
        sourceSession: 7,
        currentIndex: 0,
        queueLength: entries.length)!;
    final boundary = QueueStopBoundary()
      ..arm(entries[choice.targetIndex(3)!].id);
    addTearDown(boundary.dispose);
    entries =
        QueueEdit.insert(entries, 0, [QueueOccurrence('inserted')], next: true)
            .items;
    entries = QueueEdit.moveNext(entries, 0, 3)!.items;
    boundary.retain(entries.map((entry) => entry.id));
    expect(boundary.target, duplicate.id);
    expect(entries[1], same(duplicate),
        reason:
            'The stop target can now be the next song, rather than song 3.');
    boundary.loading(first.id, 7);
    expect(boundary.complete(first.id, 7), isFalse);
    boundary.loading(duplicate.id, 8);
    expect(boundary.complete(duplicate.id, 8), isTrue);
    expect(boundary.canAdvanceAutomatically, isFalse);
  });
}
