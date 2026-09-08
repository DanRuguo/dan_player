import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'redo shares its budget, preserves occurrence identity and truncates branches',
      () {
    final first = QueueOccurrence('same');
    final active = QueueOccurrence('same');
    final history = QueueEditHistory<QueueOccurrence<String>>(
        maxEntries: 2, maxRetainedItems: 28);
    var state = QueueSnapshot([first, active], [first, active], 1);
    void apply(List<QueueOccurrence<String>> items, int index) {
      final next = QueueSnapshot(items, items, index);
      expect(history.record(state, next), isTrue);
      state = next;
    }

    apply([active], 0);
    final budget = history.retainedItems;
    state = history.undo(state.items, state.backup, state.currentIndex)!;
    expect(history.retainedItems, budget,
        reason: 'Undo and redo share retained snapshots');
    expect(history.redoLength, 1);
    expect(history.canRedo(state.items, state.backup, 0), isFalse,
        reason: 'The other same-song occurrence cannot restore this session');
    state = history.redo(state.items, state.backup, state.currentIndex)!;
    expect(state.items.single.id, active.id);
    state = history.undo(state.items, state.backup, state.currentIndex)!;
    apply([first, active, QueueOccurrence('new')], 1);
    expect(history.redoLength, 0);
    expect(history.redo(state.items, state.backup, state.currentIndex), isNull);
    expect(history.retainedItems, lessThanOrEqualTo(28));
    history.clear(QueueHistoryInvalidation.physicalDeletion);
    expect(history.length + history.redoLength, 0);
    expect(history.invalidation, QueueHistoryInvalidation.physicalDeletion);
  });

  test(
      'metadata mapping updates both undo and redo without resurrecting old paths',
      () {
    final history = QueueEditHistory<String>();
    final a = QueueSnapshot(['a', 'b'], ['a', 'b'], 0);
    final b = QueueSnapshot(['a', 'b', 'c'], ['a', 'b', 'c'], 0);
    final c = QueueSnapshot(['a', 'c'], ['a', 'c'], 0);
    history.record(a, b);
    history.record(b, c);
    history.undo(c.items, c.backup, 0);
    history.mapItems((item) => '$item-renamed');
    var state = history.redo(['a-renamed', 'b-renamed', 'c-renamed'],
        ['a-renamed', 'b-renamed', 'c-renamed'], 0)!;
    expect(state.items, ['a-renamed', 'c-renamed']);
    state = history.undo(state.items, state.backup, 0)!;
    state = history.undo(state.items, state.backup, 0)!;
    expect(state.items, ['a-renamed', 'b-renamed']);
  });
  test(
      'undo restores move, remove and keep edits with an exact duplicate index',
      () {
    final history = QueueEditHistory<String>();
    final original = ['same', 'middle', 'same', 'last'];
    var state = QueueSnapshot(original, original, 2);
    void apply(QueueEdit<String> edit) {
      final next = QueueSnapshot(edit.items, edit.items, edit.currentIndex);
      expect(history.record(state, next), isTrue);
      state = next;
    }

    apply(QueueEdit.moveNext(state.items, state.currentIndex, 0)!);
    expect(state.currentIndex, 1);
    apply(QueueEdit.remove(state.items, state.currentIndex, 0)!);
    expect(state.currentIndex, 0);
    apply(QueueEdit([state.items[state.currentIndex]], 0));
    for (final expected in [
      (['same', 'same', 'last'], 0),
      (['middle', 'same', 'same', 'last'], 1),
      (original, 2),
    ]) {
      state = history.undo(state.items, state.backup, state.currentIndex)!;
      expect(state.items, expected.$1);
      expect(state.backup, expected.$1);
      expect(state.currentIndex, expected.$2);
    }
    expect(history.length, 0);
    expect(original, ['same', 'middle', 'same', 'last']);
    expect(() => state.items.clear(), throwsUnsupportedError);
  });

  test('batch next and append undo restore a separate shuffle backup', () {
    final history = QueueEditHistory<String>();
    final original = QueueSnapshot(['c', 'a', 'b'], ['a', 'b', 'c'], 1);
    final inserted =
        QueueEdit.insert(original.items, 1, ['x', 'y', 'x'], next: true);
    final afterNext =
        QueueSnapshot(inserted.items, [...original.backup, 'x', 'y', 'x'], 1);
    expect(history.record(original, afterNext), isTrue);
    final appended = QueueEdit.insert(afterNext.items, 1, ['a'], next: false);
    final afterAppend =
        QueueSnapshot(appended.items, [...afterNext.backup, 'a'], 1);
    expect(history.record(afterNext, afterAppend), isTrue);
    final undone = history.undo(afterAppend.items, afterAppend.backup, 1)!;
    expect(undone.items, ['c', 'a', 'x', 'y', 'x', 'b']);
    expect(undone.backup, ['a', 'b', 'c', 'x', 'y', 'x']);
    final restored = history.undo(undone.items, undone.backup, 1)!;
    expect(restored.items, original.items);
    expect(restored.backup, original.backup);
  });

  test('no-op and invalid edits do not consume or overwrite valid history', () {
    final history = QueueEditHistory<String>();
    final before = QueueSnapshot(['a', 'b'], ['a', 'b'], 0);
    final after = QueueSnapshot(['a'], ['a'], 0);
    expect(history.record(before, after), isTrue);
    expect(history.record(after, QueueSnapshot(['a'], ['a'], 0)), isFalse);
    expect(history.record(after, QueueSnapshot(['b'], ['b'], 0)), isFalse);
    expect(history.length, 1);
    expect(history.undo(after.items, after.backup, 0)!.items, ['a', 'b']);
  });

  test('undo refuses a different current occurrence or replaced queue', () {
    final history = QueueEditHistory<String>();
    final before = QueueSnapshot(
        ['same', 'middle', 'same'], ['same', 'middle', 'same'], 2);
    final after = QueueSnapshot(['same', 'same'], ['same', 'same'], 1);
    history.record(before, after);
    expect(history.canUndo(after.items, after.backup, 0), isFalse);
    expect(history.undo(after.items, after.backup, 0), isNull);
    expect(history.length, 0);
    history.record(before, after);
    expect(history.undo(['new'], ['new'], 0), isNull);
    history.record(before, after);
    history.clear(); // Source/session changes and physical deletions.
    expect(history.undo(after.items, after.backup, 1), isNull);
  });

  test('history evicts oldest entries and limits retained item references', () {
    final history = QueueEditHistory<String>(maxEntries: 2);
    var state = QueueSnapshot(['a'], ['a'], 0);
    for (final title in ['b', 'c', 'd']) {
      final items = [...state.items, title];
      final next = QueueSnapshot(items, items, 0);
      history.record(state, next);
      state = next;
    }
    expect(history.length, 2);
    state = history.undo(state.items, state.backup, 0)!;
    state = history.undo(state.items, state.backup, 0)!;
    expect(state.items, ['a', 'b']);
    expect(history.undo(state.items, state.backup, 0), isNull);
    final small = QueueEditHistory<String>(maxRetainedItems: 6);
    final first = QueueSnapshot(['a'], ['a'], 0);
    final second = QueueSnapshot(['a', 'b'], ['a', 'b'], 0);
    expect(small.record(first, second), isTrue);
    final third = QueueSnapshot(['a', 'b', 'c'], ['a', 'b', 'c'], 0);
    expect(small.record(second, third), isFalse);
    expect(small.length, 0);
  });

  test(
      'renamed or refreshed references are preserved when restoring removed items',
      () {
    final history = QueueEditHistory<String>();
    history.record(QueueSnapshot(['a', 'b'], ['a', 'b'], 0),
        QueueSnapshot(['a'], ['a'], 0));
    history.mapItems((item) => '$item-new');
    final restored = history.undo(['a-new'], ['a-new'], 0)!;
    expect(restored.items, ['a-new', 'b-new']);
    expect(restored.backup, ['a-new', 'b-new']);
  });

  test('editing a stopped queue can be undone without creating an active track',
      () {
    final history = QueueEditHistory<String>();
    final before = QueueSnapshot(['a'], ['a'], -1);
    final after = QueueSnapshot<String>([], [], -1);
    expect(history.record(before, after), isTrue);
    final restored = history.undo([], [], -1)!;
    expect(restored.currentIndex, -1);
    expect(restored.items, ['a']);
  });
}
