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
