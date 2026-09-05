import 'package:flutter/foundation.dart';

/// A small transport state machine. It observes the existing player clock;
/// no timer, background player, or repeated widget rebuild drives the loop.
class SegmentLoopController extends ChangeNotifier {
  double? start;
  double? end;
  bool enabled = false;
  bool _awaitingSeek = false;

  bool get hasRange => start != null && end != null && end! - start! >= 1;

  bool setStart(double position, double duration) {
    if (!position.isFinite || !duration.isFinite || duration < 1) return false;
    start = position.clamp(0.0, duration - 1);
    if (end != null && end! - start! < 1) end = null;
    enabled = false;
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
    _awaitingSeek = false;
    notifyListeners();
    return true;
  }

  void setEnabled(bool value) {
    enabled = value && hasRange;
    _awaitingSeek = false;
    notifyListeners();
  }

  /// Suppress stale frames at B until the player's clock acknowledges the seek.
  double? targetForPosition(double position) {
    if (!enabled || !hasRange || !position.isFinite) return null;
    if (position < end! - .1) _awaitingSeek = false;
    if (position < end! || _awaitingSeek) return null;
    _awaitingSeek = true;
    return start;
  }

  void manualSeek(double position) {
    if (enabled && (position < start! || position >= end!)) setEnabled(false);
  }

  void clear() {
    if (start == null && end == null && !enabled) return;
    start = null;
    end = null;
    enabled = false;
    _awaitingSeek = false;
    notifyListeners();
  }
}
