import 'dart:async';

import 'package:flutter/foundation.dart';

/// A session-only countdown. Pausing removes its timer; elapsed wall time is
/// read on each tick so suspend/resume never adds another sleep period.
class SleepTimerController {
  SleepTimerController({required this.onElapsed, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const maximum = Duration(hours: 24);
  final void Function(bool finishCurrent) onElapsed;
  final DateTime Function() _now;
  final remaining = ValueNotifier<Duration?>(null);
  final paused = ValueNotifier(false);
  final finishCurrent = ValueNotifier(false);
  Timer? _ticker;
  DateTime? _deadline;
  bool _disposed = false;

  void start(Duration duration) {
    if (_disposed) return;
    cancel();
    if (duration <= Duration.zero) return;
    remaining.value = duration > maximum ? maximum : duration;
    _deadline = _now().add(remaining.value!);
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_disposed || paused.value || _deadline == null) return;
    final left = _deadline!.difference(_now());
    if (left > Duration.zero) {
      remaining.value = left > maximum ? maximum : left;
      return;
    }
    final finish = finishCurrent.value;
    cancel();
    onElapsed(finish);
  }

  void togglePaused() {
    if (_disposed || remaining.value == null) return;
    if (paused.value) {
      _deadline = _now().add(remaining.value!);
      paused.value = false;
      _startTicker();
    } else {
      _tick();
      if (remaining.value == null) return;
      _ticker?.cancel();
      _ticker = null;
      _deadline = null;
      paused.value = true;
    }
  }

  void adjust(Duration delta) {
    if (_disposed || remaining.value == null) return;
    if (!paused.value) _tick();
    final current = remaining.value;
    if (current == null) return;
    final milliseconds = (current + delta).inMilliseconds.clamp(
        const Duration(seconds: 1).inMilliseconds, maximum.inMilliseconds);
    remaining.value = Duration(milliseconds: milliseconds);
    if (!paused.value) _deadline = _now().add(remaining.value!);
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    remaining.value = null;
    paused.value = false;
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    remaining.dispose();
    paused.dispose();
    finishCurrent.dispose();
  }
}

String formatSleepRemaining(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil().clamp(0, 86400);
  final minutes = (seconds % 3600) ~/ 60;
  final tail = '${minutes.toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
  return seconds >= 3600
      ? '${(seconds ~/ 3600).toString().padLeft(2, '0')}:$tail'
      : tail;
}
