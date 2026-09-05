/// Queue operations use occurrence indices: equal tracks may occur more than
/// once, and moving/removing one must not silently select another occurrence.
class QueueEdit<T> {
  const QueueEdit(this.items, this.currentIndex);

  final List<T> items;
  final int currentIndex;

  /// Insert a batch once, preserving its order and repeated occurrences.
  static QueueEdit<T> insert<T>(List<T> items, int current, List<T> additions,
      {required bool next}) {
    final insertion =
        next ? (current + 1).clamp(0, items.length) : items.length;
    return QueueEdit(List<T>.from(items)..insertAll(insertion, additions),
        current >= insertion ? current + additions.length : current);
  }

  static QueueEdit<T>? remove<T>(List<T> items, int current, int index) {
    if (index < 0 || index >= items.length || index == current) return null;
    return QueueEdit(List<T>.from(items)..removeAt(index),
        current > index ? current - 1 : current);
  }

  static QueueEdit<T>? moveNext<T>(List<T> items, int current, int index) {
    if (current < 0 ||
        current >= items.length ||
        index < 0 ||
        index >= items.length ||
        index == current ||
        index == current + 1) {
      return null;
    }
    final next = List<T>.from(items);
    final moved = next.removeAt(index);
    final currentAfterRemoval = current > index ? current - 1 : current;
    next.insert(currentAfterRemoval + 1, moved);
    return QueueEdit(next, currentAfterRemoval);
  }
}

/// A queue snapshot intentionally contains no decoder, position or play state.
/// Restoring it can only rearrange the currently open track's occurrence.
class QueueSnapshot<T> {
  QueueSnapshot(List<T> items, List<T> backup, this.currentIndex)
      : items = List<T>.unmodifiable(items),
        backup = List<T>.unmodifiable(backup);

  final List<T> items;
  final List<T> backup;
  final int currentIndex;

  bool matches(List<T> items, List<T> backup, int currentIndex) =>
      this.currentIndex == currentIndex &&
      _sameItems(this.items, items) &&
      _sameItems(this.backup, backup);

  static bool _sameItems<T>(List<T> left, List<T> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

/// Bounded in-memory undo for edits within one open track occurrence. Source
/// changes, queue replacement and physical deletion must call [clear].
class QueueEditHistory<T> {
  QueueEditHistory({this.maxEntries = 10, this.maxRetainedItems = 400000})
      : assert(maxEntries > 0),
        assert(maxRetainedItems > 0);

  final int maxEntries;
  final int maxRetainedItems;
  final List<({QueueSnapshot<T> before, QueueSnapshot<T> after})> _entries = [];
  int _retainedItems = 0;

  int get length => _entries.length;

  bool canUndo(List<T> items, List<T> backup, int currentIndex) =>
      _entries.isNotEmpty &&
      _entries.last.after.matches(items, backup, currentIndex);

  bool record(QueueSnapshot<T> before, QueueSnapshot<T> after) {
    if (before.matches(after.items, after.backup, after.currentIndex)) {
      return false;
    }
    final beforeIndex = before.currentIndex;
    final afterIndex = after.currentIndex;
    final hasCurrent = beforeIndex >= 0 && beforeIndex < before.items.length;
    final hasAfter = afterIndex >= 0 && afterIndex < after.items.length;
    if (hasCurrent != hasAfter ||
        (hasCurrent && before.items[beforeIndex] != after.items[afterIndex]) ||
        (!hasCurrent && (beforeIndex != -1 || afterIndex != -1))) {
      return false;
    }
    if (_entries.isNotEmpty &&
        !canUndo(before.items, before.backup, before.currentIndex)) {
      clear();
    }
    final retained = _size(before) + _size(after);
    // Large queues remain editable without retaining an unbounded old copy.
    if (retained > maxRetainedItems) {
      clear();
      return false;
    }
    while (_entries.isNotEmpty &&
        (_entries.length >= maxEntries ||
            _retainedItems + retained > maxRetainedItems)) {
      final oldest = _entries.removeAt(0);
      _retainedItems -= _size(oldest.before) + _size(oldest.after);
    }
    _entries.add((before: before, after: after));
    _retainedItems += retained;
    return true;
  }

  QueueSnapshot<T>? undo(List<T> items, List<T> backup, int currentIndex) {
    if (!canUndo(items, backup, currentIndex)) {
      clear();
      return null;
    }
    final entry = _entries.removeLast();
    _retainedItems -= _size(entry.before) + _size(entry.after);
    return entry.before;
  }

  /// Metadata refreshes and file renames update retained references as well.
  void mapItems(T Function(T item) replace) {
    QueueSnapshot<T> mapped(QueueSnapshot<T> state) => QueueSnapshot(
        state.items.map(replace).toList(),
        state.backup.map(replace).toList(),
        state.currentIndex);
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      _entries[i] = (before: mapped(entry.before), after: mapped(entry.after));
    }
  }

  void clear() {
    _entries.clear();
    _retainedItems = 0;
  }

  int _size(QueueSnapshot<T> state) => state.items.length + state.backup.length;
}
