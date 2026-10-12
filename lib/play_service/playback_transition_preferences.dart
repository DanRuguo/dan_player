/// Optional native mixing. The default retains the existing output path.
enum PlaybackTransitionMode { standard, gapless, crossfade }

class PlaybackTransitionPreferences {
  const PlaybackTransitionPreferences({
    this.mode = PlaybackTransitionMode.standard,
    this.crossfadeSeconds = 3,
  });

  final PlaybackTransitionMode mode;
  final double crossfadeSeconds;
  bool get enabled => mode != PlaybackTransitionMode.standard;

  static double safeSeconds(Object? value) {
    final number = value is num ? value.toDouble() : 3.0;
    return number.isFinite ? number.clamp(0.5, 12).toDouble() : 3.0;
  }

  factory PlaybackTransitionPreferences.fromJson(Object? value) {
    if (value is! Map) return const PlaybackTransitionPreferences();
    final modes =
        PlaybackTransitionMode.values.where((m) => m.name == value['mode']);
    return PlaybackTransitionPreferences(
      mode: modes.isEmpty ? PlaybackTransitionMode.standard : modes.first,
      crossfadeSeconds: safeSeconds(value['crossfadeSeconds']),
    );
  }

  Map<String, Object> toJson() => {
        'mode': mode.name,
        'crossfadeSeconds': safeSeconds(crossfadeSeconds),
      };

  PlaybackTransitionPreferences copyWith(
          {PlaybackTransitionMode? mode, double? crossfadeSeconds}) =>
      PlaybackTransitionPreferences(
          mode: mode ?? this.mode,
          crossfadeSeconds:
              safeSeconds(crossfadeSeconds ?? this.crossfadeSeconds));

  @override
  bool operator ==(Object other) =>
      other is PlaybackTransitionPreferences &&
      mode == other.mode &&
      crossfadeSeconds == other.crossfadeSeconds;
  @override
  int get hashCode => Object.hash(mode, crossfadeSeconds);
}
