import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Smooth cosine volume ramp over the final [fadeWindow] before sleep expiry.
double sleepTimerFadeFactor(
  Duration remaining, {
  Duration fadeWindow = SleepTimerController.fadeWindow,
}) {
  if (fadeWindow <= Duration.zero || remaining >= fadeWindow) return 1.0;
  if (remaining <= Duration.zero) return 0.0;
  final fraction =
      (remaining.inMilliseconds / fadeWindow.inMilliseconds).clamp(0.0, 1.0);
  return (0.5 * (1.0 - math.cos(math.pi * fraction))).clamp(0.0, 1.0);
}

/// A session-only countdown. Pausing removes its timer; elapsed wall time is
/// read on each tick so suspend/resume never adds another sleep period.
class SleepTimerController {
  SleepTimerController({
    required this.onElapsed,
    this.onFadeFactor,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const maximum = Duration(hours: 24);
  static const fadeWindow = Duration(seconds: 5);
  static const _normalInterval = Duration(seconds: 1);
  static const _fadeInterval = Duration(milliseconds: 200);

  final void Function(bool finishCurrent) onElapsed;
  final void Function(double factor)? onFadeFactor;
  final DateTime Function() _now;
  final remaining = ValueNotifier<Duration?>(null);
  final paused = ValueNotifier(false);
  final finishCurrent = ValueNotifier(false);
  final fadeOut = ValueNotifier(true);
  Timer? _ticker;
  Duration? _tickerInterval;
  DateTime? _deadline;
  double _lastFadeFactor = 1.0;
  bool _disposed = false;

  void start(Duration duration) {
    if (_disposed) return;
    cancel();
    if (duration <= Duration.zero) return;
    remaining.value = duration > maximum ? maximum : duration;
    _deadline = _now().add(remaining.value!);
    _syncFadeAndTicker(remaining.value!);
  }

  bool _shouldFade(Duration left) =>
      fadeOut.value && !finishCurrent.value && !paused.value && left <= fadeWindow;

  void _emitFadeFactor(double factor) {
    if (_disposed) return;
    if ((_lastFadeFactor - factor).abs() < 1e-4) return;
    _lastFadeFactor = factor;
    onFadeFactor?.call(factor);
  }

  void _startTicker(Duration interval) {
    if (_ticker != null && _tickerInterval == interval) return;
    _ticker?.cancel();
    _tickerInterval = interval;
    _ticker = Timer.periodic(interval, (_) => _tick());
  }

  void _syncFadeAndTicker(Duration left) {
    if (_shouldFade(left)) {
      _emitFadeFactor(sleepTimerFadeFactor(left));
      _startTicker(_fadeInterval);
    } else {
      _emitFadeFactor(1.0);
      _startTicker(_normalInterval);
    }
  }

  void setFinishCurrent(bool enabled) {
    if (_disposed) return;
    finishCurrent.value = enabled;
    final left = remaining.value;
    if (left != null && !paused.value) {
      _syncFadeAndTicker(left);
    } else if (enabled) {
      _emitFadeFactor(1.0);
    }
  }

  void setFadeOut(bool enabled) {
    if (_disposed) return;
    fadeOut.value = enabled;
    final left = remaining.value;
    if (left != null && !paused.value) {
      _syncFadeAndTicker(left);
    } else if (!enabled) {
      _emitFadeFactor(1.0);
    }
  }

  void _tick() {
    if (_disposed || paused.value || _deadline == null) return;
    final left = _deadline!.difference(_now());
    if (left > Duration.zero) {
      final bounded = left > maximum ? maximum : left;
      remaining.value = bounded;
      _syncFadeAndTicker(bounded);
      return;
    }
    final finish = finishCurrent.value;
    if (!finish && fadeOut.value) {
      _emitFadeFactor(0.0);
    }
    _ticker?.cancel();
    _ticker = null;
    _tickerInterval = null;
    _deadline = null;
    remaining.value = null;
    paused.value = false;
    onElapsed(finish);
    _emitFadeFactor(1.0);
  }

  void togglePaused() {
    if (_disposed || remaining.value == null) return;
    if (paused.value) {
      _deadline = _now().add(remaining.value!);
      paused.value = false;
      _syncFadeAndTicker(remaining.value!);
    } else {
      _tick();
      if (remaining.value == null) return;
      _ticker?.cancel();
      _ticker = null;
      _tickerInterval = null;
      _deadline = null;
      paused.value = true;
      _emitFadeFactor(1.0);
    }
  }

  void adjust(Duration delta) {
    if (_disposed || remaining.value == null) return;
    if (!paused.value) _tick();
    final current = remaining.value;
    if (current == null) return;
    final milliseconds = (current + delta).inMilliseconds.clamp(
        const Duration(seconds: 1).inMilliseconds, maximum.inMilliseconds);
    final updated = Duration(milliseconds: milliseconds);
    remaining.value = updated;
    if (!paused.value) {
      _deadline = _now().add(updated);
      _syncFadeAndTicker(updated);
    }
  }

  void cancel() {
    _ticker?.cancel();
    _ticker = null;
    _tickerInterval = null;
    _deadline = null;
    remaining.value = null;
    paused.value = false;
    _emitFadeFactor(1.0);
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    remaining.dispose();
    paused.dispose();
    finishCurrent.dispose();
    fadeOut.dispose();
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
