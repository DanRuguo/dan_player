import 'dart:math' as math;

/// A clock-free envelope for an already available low-frequency measurement.
/// Exponential attack/release gives the same response at 30, 60 and 144 Hz.
class ArtworkPulse {
  double _level = 0;
  double get scale => 1 + .075 * _level;

  void reset() => _level = 0;

  void advance(double seconds, double level) {
    if (!seconds.isFinite || seconds <= 0) return;
    final target = level.isFinite ? level.clamp(0.0, 1.0) : 0.0;
    final tau = target > _level ? .075 : .28;
    _level += (target - _level) * (1 - math.exp(-seconds / tau));
  }
}
