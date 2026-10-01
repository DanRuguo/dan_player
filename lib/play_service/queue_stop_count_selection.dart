/// A short-lived choice from the displayed queue. Confirming a count selects
/// one existing occurrence; it does not start a completed-song counter.
class QueueStopCountSelection {
  QueueStopCountSelection._({
    required Object queueIdentity,
    required int sourceSession,
    required this.currentIndex,
    required this.queueLength,
  })  : _queueIdentity = queueIdentity,
        _sourceSession = sourceSession;

  final Object _queueIdentity;
  final int _sourceSession;
  final int currentIndex;
  final int queueLength;

  int get remainingCount => queueLength - currentIndex;

  static QueueStopCountSelection? capture({
    required Object queueIdentity,
    required int sourceSession,
    required int currentIndex,
    required int queueLength,
  }) {
    if (currentIndex < 0 || currentIndex >= queueLength) return null;
    return QueueStopCountSelection._(
        queueIdentity: queueIdentity,
        sourceSession: sourceSession,
        currentIndex: currentIndex,
        queueLength: queueLength);
  }

  bool isCurrent({
    required Object queueIdentity,
    required int sourceSession,
    required int currentIndex,
    required int queueLength,
  }) =>
      identical(_queueIdentity, queueIdentity) &&
      _sourceSession == sourceSession &&
      this.currentIndex == currentIndex &&
      this.queueLength == queueLength;

  /// Count 1 includes the current occurrence. The choice never wraps around
  /// the queue or changes to a different duplicate of the same song.
  int? targetIndex(int count) =>
      count < 1 || count > remainingCount ? null : currentIndex + count - 1;
}
