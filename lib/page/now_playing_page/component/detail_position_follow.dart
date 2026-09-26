import 'package:flutter/physics.dart';

/// Retarget an existing finite ticker instead of restarting its first frame.
/// Every endpoint is an observed native position; no future time is invented.
class DetailPositionFollow extends Simulation {
  DetailPositionFollow(
      {required double from,
      required double target,
      required Duration duration})
      : assert(duration > Duration.zero),
        _from = from,
        _target = target,
        _seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
  double _from, _target;
  double _startedAt = 0;
  final double _seconds;

  void retarget(
      {required double from,
      required double target,
      required Duration elapsed}) {
    _from = from;
    _target = target;
    _startedAt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }

  @override
  double x(double time) =>
      _from +
      (_target - _from) * ((time - _startedAt) / _seconds).clamp(0.0, 1.0);
  @override
  double dx(double time) => isDone(time) ? 0 : (_target - _from) / _seconds;
  @override
  bool isDone(double time) => time >= _startedAt + _seconds;
}
