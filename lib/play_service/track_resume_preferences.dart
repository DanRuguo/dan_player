enum TrackResumeMode { off, longAudio, allLocal }

/// Opt-in per-track progress, independent of restoring the last app session.
class TrackResumePreferences {
  const TrackResumePreferences({
    this.mode = TrackResumeMode.off,
    this.minimumMinutes = 20,
  });

  static const durationChoices = [10, 20, 30, 60];
  final TrackResumeMode mode;
  final int minimumMinutes;

  bool accepts({required bool local, required double duration}) =>
      local &&
      duration.isFinite &&
      duration > 20 &&
      duration <= 365 * 24 * 60 * 60 &&
      mode != TrackResumeMode.off &&
      (mode == TrackResumeMode.allLocal || duration >= minimumMinutes * 60);

  factory TrackResumePreferences.fromJson(Object? value) {
    if (value is! Map) return const TrackResumePreferences();
    return TrackResumePreferences(
      mode: TrackResumeMode.values.firstWhere(
          (mode) => mode.name == value['mode'],
          orElse: () => TrackResumeMode.off),
      minimumMinutes: value['minimumMinutes'] is int &&
              durationChoices.contains(value['minimumMinutes'])
          ? value['minimumMinutes'] as int
          : 20,
    );
  }

  Map<String, Object> toJson() =>
      {'mode': mode.name, 'minimumMinutes': minimumMinutes};
  TrackResumePreferences copyWith(
          {TrackResumeMode? mode, int? minimumMinutes}) =>
      TrackResumePreferences(
          mode: mode ?? this.mode,
          minimumMinutes: minimumMinutes ?? this.minimumMinutes);
  @override
  bool operator ==(Object other) =>
      other is TrackResumePreferences &&
      mode == other.mode &&
      minimumMinutes == other.minimumMinutes;
  @override
  int get hashCode => Object.hash(mode, minimumMinutes);
}
