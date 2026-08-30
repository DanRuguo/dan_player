/// Playback tempo is independent of pitch and source-media timestamps.
abstract final class PlaybackRate {
  static const min = .5;
  static const max = 2.0;
  static const presets = [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0];

  static double sanitize(Object? value, {double fallback = 1.0}) {
    final candidate = value is num && value.isFinite
        ? value.toDouble()
        : fallback.isFinite
            ? fallback
            : 1.0;
    return candidate.clamp(min, max);
  }

  static double validate(double value) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, 'playbackRate', '必须在 0.5–2.0 之间');
    }
    return value;
  }

  static double tempoPercent(double value) => (validate(value) - 1.0) * 100;

  static String label(double value) {
    final rate = sanitize(value);
    return '${rate.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')}×';
  }
}
