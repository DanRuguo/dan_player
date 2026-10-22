class SilenceSkipPreferences {
  const SilenceSkipPreferences({
    this.enabled = false,
    this.thresholdDb = -50,
    this.scanSeconds = 10,
  });

  final bool enabled;
  final double thresholdDb;
  final double scanSeconds;

  static double safeThreshold(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(-70, -30).toDouble()
      : -50;
  static double safeScanSeconds(Object? value) => value is num && value.isFinite
      ? value.toDouble().clamp(2, 30).toDouble()
      : 10;

  factory SilenceSkipPreferences.fromJson(Object? value) => value is Map
      ? SilenceSkipPreferences(
          enabled: value['enabled'] == true,
          thresholdDb: safeThreshold(value['thresholdDb']),
          scanSeconds: safeScanSeconds(value['scanSeconds']))
      : const SilenceSkipPreferences();

  Map<String, Object> toJson() => {
        'enabled': enabled,
        'thresholdDb': safeThreshold(thresholdDb),
        'scanSeconds': safeScanSeconds(scanSeconds),
      };

  SilenceSkipPreferences copyWith(
          {bool? enabled, double? thresholdDb, double? scanSeconds}) =>
      SilenceSkipPreferences(
          enabled: enabled ?? this.enabled,
          thresholdDb: safeThreshold(thresholdDb ?? this.thresholdDb),
          scanSeconds: safeScanSeconds(scanSeconds ?? this.scanSeconds));

  @override
  bool operator ==(Object other) =>
      other is SilenceSkipPreferences &&
      enabled == other.enabled &&
      thresholdDb == other.thresholdDb &&
      scanSeconds == other.scanSeconds;
  @override
  int get hashCode => Object.hash(enabled, thresholdDb, scanSeconds);
}
