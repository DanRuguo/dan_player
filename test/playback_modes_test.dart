import 'dart:math';

import 'package:dan_player/play_service/playback_modes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final shuffle in [false, true]) {
    for (final mode in PlayMode.values) {
      test(
          'automatic $mode shuffle=$shuffle respects the current cycle boundary',
          () {
        final middle = nextQueueAdvance(
            length: 4,
            currentIndex: 1,
            playMode: mode,
            shuffle: shuffle,
            automatic: true);
        expect(middle.index, mode == PlayMode.singleLoop ? 1 : 2);
        expect(middle.newShuffleCycle, isFalse);
        final end = nextQueueAdvance(
            length: 4,
            currentIndex: 3,
            playMode: mode,
            shuffle: shuffle,
            automatic: true);
        expect(
            end.index,
            switch (mode) {
              PlayMode.forward => null,
              PlayMode.loop => 0,
              PlayMode.singleLoop => 3,
            });
        expect(end.newShuffleCycle, mode == PlayMode.loop && shuffle);
      });

      test(
          'manual next crosses boundary independently of $mode shuffle=$shuffle',
          () {
        final middle = nextQueueAdvance(
            length: 4,
            currentIndex: 1,
            playMode: mode,
            shuffle: shuffle,
            automatic: false);
        expect(middle.index, 2);
        expect(middle.newShuffleCycle, isFalse);
        final end = nextQueueAdvance(
            length: 4,
            currentIndex: 3,
            playMode: mode,
            shuffle: shuffle,
            automatic: false);
        expect(end.index, 0);
        expect(end.newShuffleCycle, shuffle);
      });
    }
  }

  test('empty and one-item queues follow explicit stop and repeat policy', () {
    for (final shuffle in [false, true]) {
      for (final mode in PlayMode.values) {
        expect(
            nextQueueAdvance(
                    length: 0,
                    currentIndex: -1,
                    playMode: mode,
                    shuffle: shuffle,
                    automatic: true)
                .index,
            isNull);
        expect(
            nextQueueAdvance(
                    length: 1,
                    currentIndex: 0,
                    playMode: mode,
                    shuffle: shuffle,
                    automatic: true)
                .index,
            mode == PlayMode.forward ? null : 0);
      }
    }
  });

  test('forward stops after each occurrence including duplicates exactly once',
      () {
    for (final seed in List.generate(30, (i) => i)) {
      final cycle =
          ShuffleQueueCycle(['A', 'B', 'A', 'C'], random: Random(seed));
      var index = 0;
      final visited = <int>[];
      while (true) {
        visited.add(cycle.sourceIndex(index));
        final next = nextQueueAdvance(
            length: cycle.items.length,
            currentIndex: index,
            playMode: PlayMode.forward,
            shuffle: true,
            automatic: true);
        expect(next.newShuffleCycle, isFalse);
        if (next.index == null) break;
        index = next.index!;
        expect(visited.length, lessThan(5));
      }
      expect(visited, unorderedEquals([0, 1, 2, 3]));
    }
  });

  test('new random cycle avoids boundary same song and retains all duplicates',
      () {
    for (var seed = 0; seed < 40; seed++) {
      final cycle = ShuffleQueueCycle(['A', 'A', 'B', 'C'],
          avoidFirst: (audio) => audio == 'A', random: Random(seed));
      expect(cycle.items.first, isNot('A'));
      expect(cycle.sourceIndices, unorderedEquals([0, 1, 2, 3]));
      expect(cycle.items, unorderedEquals(['A', 'A', 'B', 'C']));
    }
    final unavoidable = ShuffleQueueCycle(['A', 'A'], avoidFirst: (_) => true);
    expect(unavoidable.items, ['A', 'A']);
  });

  test('current and pending duplicate occurrences survive shuffle on/off', () {
    final repeated = Object();
    final original = [repeated, Object(), repeated, Object(), repeated];
    for (var seed = 0; seed < 25; seed++) {
      final cycle =
          ShuffleQueueCycle(original, startIndex: 2, random: Random(seed));
      expect(cycle.queueIndex(2), 0);
      expect(cycle.sourceIndex(0), 2);
      final pendingIndex = cycle.queueIndex(4);
      expect(pendingIndex, isNot(0));
      expect(cycle.sourceIndex(pendingIndex), 4);
      expect(cycle.items[pendingIndex], same(repeated));
      expect(cycle.source, orderedEquals(original));
      expect(cycle.appliesTo(cycle.items, cycle.source), isTrue);
    }
    expect(original[0], same(original[2]));
    expect(original.length, 5);
  });

  test(
      'metadata object refresh keeps permutation but real queue edits invalidate it',
      () {
    final cycle = ShuffleQueueCycle([
      (path: 'A', revision: 1),
      (path: 'B', revision: 1),
      (path: 'A', revision: 1)
    ], startIndex: 2, random: Random(2));
    final refreshed = [
      for (final item in cycle.items) (path: item.path, revision: 2)
    ];
    final backup = [
      for (final item in cycle.source) (path: item.path, revision: 2)
    ];
    expect(
        cycle.appliesTo(refreshed, backup,
            sameItem: (a, b) => a.path == b.path),
        isTrue);
    expect(cycle.sourceIndex(0), 2);
    expect(
        cycle.appliesTo(refreshed.sublist(1), backup,
            sameItem: (a, b) => a.path == b.path),
        isFalse);
  });

  test('legacy queues map duplicate occurrence and pools count repetitions',
      () {
    const before = ['A', 'B', 'A', 'C'];
    const after = ['C', 'A', 'B', 'A'];
    expect(queueOccurrenceIndex(before, 2, after, keyOf: (s) => s), 3);
    expect(queueOccurrenceIndex(before, 4, after, keyOf: (s) => s), -1);
    expect(queueOccurrenceIndex(before, 2, ['A'], keyOf: (s) => s), -1);
    expect(sameQueuePool(before, after, keyOf: (s) => s), isTrue);
    expect(
        sameQueuePool(before, ['A', 'B', 'C', 'C'], keyOf: (s) => s), isFalse);
  });
}
