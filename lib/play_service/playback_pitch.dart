/// Pitch in semitones, independent of tempo and source-media timestamps.
abstract final class PlaybackPitch {
  static const min = -12.0;
  static const max = 12.0;
  static const presets = [-12.0, -7.0, -5.0, 0.0, 5.0, 7.0, 12.0];

  static double sanitize(Object? value, {double fallback = 0.0}) {
    final candidate = value is num && value.isFinite
        ? value.toDouble()
        : fallback.isFinite
            ? fallback
            : 0.0;
    return candidate.clamp(min, max);
  }

  static double validate(double value) {
    if (!value.isFinite || value < min || value > max) {
      throw ArgumentError.value(value, 'playbackPitch', '必须在 -12–12 半音之间');
    }
    return value;
  }

  static String label(double value) {
    final pitch = sanitize(value);
    if (pitch == 0) return '0';
    final number = pitch.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    if (number == '0' || number == '-0') return '0';
    return '${pitch > 0 ? '+' : ''}$number';
  }
}
