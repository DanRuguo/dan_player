import 'package:flutter/foundation.dart';

enum QueueStopCancelReason {
  removed,
  sourceReplaced,
  manuallyPassed,
  targetFailed,
  sleepTimer,
  userCancelled
}

/// Single-use boundary. Commands and completions carry the playback session
/// token, so late A -> B -> A responses cannot consume a newly armed target.
class QueueStopBoundary extends ChangeNotifier {
  int? target;
  int? _playing;
  int? _session;
  QueueStopCancelReason? lastCancellation;
  bool get active => target != null;
  bool canAdvanceAutomatically = true;

  void resumeAdvance() => canAdvanceAutomatically = true;
  void suspendAdvance() => canAdvanceAutomatically = false;

  void sleepExpired() {
    suspendAdvance();
    cancel(QueueStopCancelReason.sleepTimer);
  }

  void arm(int occurrence) {
    target = occurrence;
    lastCancellation = null;
    notifyListeners();
  }

  bool cancel(QueueStopCancelReason reason) {
    if (target == null) return false;
    target = null;
    lastCancellation = reason;
    notifyListeners();
    return true;
  }

  void retain(Iterable<int> occurrences) {
    if (target != null && !occurrences.contains(target)) {
      cancel(QueueStopCancelReason.removed);
    }
  }

  void loading(int occurrence, int session) {
    resumeAdvance();
    _playing = occurrence;
    _session = session;
  }

  /// Manual jumps forward across the marker, or away from its own playing
  /// occurrence, cancel it. Adjacent wraparound does not cross all other rows.
  void manualJump(List<int> order, int from, int to, {bool adjacent = false}) {
    final boundary = order.indexOf(target ?? -1);
    if (boundary < 0 || from < 0 || to < 0) return;
    if ((from == boundary && to != from) ||
        (!adjacent &&
            ((from < boundary && to > boundary) ||
                (from > boundary && to < boundary)))) {
      cancel(QueueStopCancelReason.manuallyPassed);
    }
  }

  void failed(int occurrence, int session) {
    if (_session == session && _playing == occurrence && target == occurrence) {
      cancel(QueueStopCancelReason.targetFailed);
    }
  }

  bool complete(int occurrence, int session) {
    if (_playing != occurrence || _session != session || target != occurrence) {
      return false;
    }
    target = null;
    suspendAdvance();
    lastCancellation = null;
    notifyListeners();
    return true;
  }
}
