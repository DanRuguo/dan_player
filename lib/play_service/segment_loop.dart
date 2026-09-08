import 'package:flutter/foundation.dart';

/// A small transport state machine. It observes the existing player clock;
/// no timer, background player, or repeated widget rebuild drives the loop.
class SegmentLoopController extends ChangeNotifier {
  double? start;
  double? end;
  bool enabled = false;
  bool _awaitingSeek = false;
  int? totalRounds;
  int completedRounds = 0;
  double intervalSeconds = 0;
  bool finished = false;
  void configurePractice({int? rounds, double interval = 0}) {
    if ((rounds != null && (rounds < 2 || rounds > 999)) ||
        !interval.isFinite ||
        interval < 0 ||
        interval > 10) throw ArgumentError('练习次数 2–999，间隔 0–10 秒');
    totalRounds = rounds;
    intervalSeconds = interval;
    setEnabled(false);
  }

  bool get hasRange => start != null && end != null && end! - start! >= 1;

  bool setStart(double position, double duration) {
    if (!position.isFinite || !duration.isFinite || duration < 1) return false;
    start = position.clamp(0.0, duration - 1);
    if (end != null && end! - start! < 1) end = null;
    enabled = false;
    completedRounds = 0;
    finished = false;
    _awaitingSeek = false;
    notifyListeners();
    return true;
  }

  bool setEnd(double position, double duration) {
    if (!position.isFinite || !duration.isFinite || duration < 1) return false;
    final candidate = position.clamp(0.0, duration);
    if (candidate - (start ?? 0) < 1) return false;
    start ??= 0;
    end = candidate;
    enabled = false;
    completedRounds = 0;
    finished = false;
    _awaitingSeek = false;
    notifyListeners();
    return true;
  }

  void setEnabled(bool value) {
    enabled = value && hasRange;
    completedRounds = 0;
    finished = false;
    _awaitingSeek = false;
    notifyListeners();
  }

  /// Suppress stale frames at B until the player's clock acknowledges the seek.
  double? targetForPosition(double position) {
    if (!enabled || finished || !hasRange || !position.isFinite) return null;
    if (position < end! - .1) _awaitingSeek = false;
    if (position < end! || _awaitingSeek) return null;
    _awaitingSeek = true;
    completedRounds++;
    finished = totalRounds != null && completedRounds >= totalRounds!;
    notifyListeners();
    return start;
  }

  void manualSeek(double position) {
    if (enabled && (position < start! || position >= end!)) setEnabled(false);
  }

  void clear() {
    if (start == null && end == null && !enabled) return;
    completedRounds = 0;
    finished = false;
    start = null;
    end = null;
    enabled = false;
    completedRounds = 0;
    finished = false;
    _awaitingSeek = false;
    notifyListeners();
  }
}
