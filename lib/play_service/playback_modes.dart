import 'dart:math';

/// Repeat policy is independent of queue order (shuffle).
enum PlayMode {
  forward,
  loop,
  singleLoop;

  static PlayMode? fromString(Object? playMode) {
    for (final value in values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

class QueueAdvance {
  const QueueAdvance.stop()
      : index = null,
        newShuffleCycle = false;
  const QueueAdvance.play(this.index) : newShuffleCycle = false;
  const QueueAdvance.shuffleCycle()
      : index = 0,
        newShuffleCycle = true;

  final int? index;
  final bool newShuffleCycle;
}

/// Manual next always crosses a boundary. Natural completion obeys repeat,
/// including stopping at the end of a shuffled queue when repeat is off.
QueueAdvance nextQueueAdvance({
  required int length,
  required int currentIndex,
  required PlayMode playMode,
  required bool shuffle,
  required bool automatic,
}) {
  if (length <= 0) return const QueueAdvance.stop();
  if (automatic && playMode == PlayMode.singleLoop) {
    return QueueAdvance.play(currentIndex.clamp(0, length - 1));
  }
  if (currentIndex < length - 1) {
    return QueueAdvance.play((currentIndex + 1).clamp(0, length - 1));
  }
  if (automatic && playMode == PlayMode.forward) {
    return const QueueAdvance.stop();
  }
  return shuffle
      ? const QueueAdvance.shuffleCycle()
      : const QueueAdvance.play(0);
}

/// Match occurrences, not just distinct paths. This also maps old persisted
/// queues that predate an in-memory permutation. No entries are deduplicated.
int queueOccurrenceIndex<T, K>(List<T> source, int index, List<T> destination,
    {required K Function(T) keyOf}) {
  if (index < 0 || index >= source.length) return -1;
  final key = keyOf(source[index]);
  var occurrence = 0;
  for (var i = 0; i < index; i++) {
    if (keyOf(source[i]) == key) occurrence++;
  }
  for (var i = 0; i < destination.length; i++) {
    if (keyOf(destination[i]) == key && occurrence-- == 0) return i;
  }
  return -1;
}

bool sameQueuePool<T, K>(List<T> left, List<T> right,
    {required K Function(T) keyOf}) {
  if (left.isEmpty || left.length != right.length) return false;
  final counts = <K, int>{};
  for (final item in left) {
    counts.update(keyOf(item), (count) => count + 1, ifAbsent: () => 1);
  }
  for (final item in right) {
    final key = keyOf(item);
    final count = counts[key] ?? 0;
    if (count == 0) return false;
    counts[key] = count - 1;
  }
  return true;
}

/// A permutation retains each original occurrence, even when several entries
/// point to the exact same Audio object. It can restore both active and pending
/// indices without reopening a decoder or resetting playback progress.
class ShuffleQueueCycle<T> {
  ShuffleQueueCycle(
    List<T> original, {
    int? startIndex,
    bool Function(T)? avoidFirst,
    Random? random,
  }) : source = List<T>.unmodifiable(original) {
    final order = List.generate(source.length, (index) => index);
    final pin =
        startIndex != null && startIndex >= 0 && startIndex < order.length
            ? order.removeAt(startIndex)
            : null;
    order.shuffle(random);
    if (pin != null) {
      order.insert(0, pin);
    } else if (order.length > 1 &&
        avoidFirst?.call(source[order.first]) == true) {
      final different =
          order.indexWhere((index) => !avoidFirst!(source[index]));
      if (different > 0) {
        final first = order.first;
        order[0] = order[different];
        order[different] = first;
      }
    }
    sourceIndices = List<int>.unmodifiable(order);
    items = List<T>.unmodifiable(order.map((index) => source[index]));
  }

  final List<T> source;
  late final List<int> sourceIndices;
  late final List<T> items;

  int sourceIndex(int queueIndex) =>
      queueIndex >= 0 && queueIndex < sourceIndices.length
          ? sourceIndices[queueIndex]
          : -1;
  int queueIndex(int sourceIndex) => sourceIndices.indexOf(sourceIndex);

  bool appliesTo(List<T> queue, List<T> backup,
      {bool Function(T, T)? sameItem}) {
    if (identical(queue, items) && identical(backup, source)) return true;
    if (sameItem == null ||
        queue.length != items.length ||
        backup.length != source.length) {
      return false;
    }
    for (var i = 0; i < source.length; i++) {
      if (!sameItem(source[i], backup[i]) || !sameItem(items[i], queue[i])) {
        return false;
      }
    }
    return true;
  }
}
