enum ProcessResourceDisplay { numbers, line, bar }

/// Display choices only; sampling is active only while the monitor is visible.
class ProcessResourcePreferences {
  const ProcessResourcePreferences({
    this.enabled = false,
    this.intervalSeconds = 5,
    this.display = ProcessResourceDisplay.numbers,
  });

  final int intervalSeconds;
  final bool enabled;
  final ProcessResourceDisplay display;
  static const intervals = [1, 5, 10];

  factory ProcessResourcePreferences.fromMap(dynamic value) {
    if (value is! Map) return const ProcessResourcePreferences();
    final interval = value['intervalSeconds'];
    final name = value['display'];
    return ProcessResourcePreferences(
      enabled: value['enabled'] is bool ? value['enabled'] as bool : false,
      intervalSeconds:
          interval is int && intervals.contains(interval) ? interval : 5,
      display: ProcessResourceDisplay.values
              .where((e) => e.name == name)
              .firstOrNull ??
          ProcessResourceDisplay.numbers,
    );
  }

  Map<String, Object> toMap() => {
        'enabled': enabled,
        'intervalSeconds': intervalSeconds,
        'display': display.name
      };
  ProcessResourcePreferences copyWith(
          {bool? enabled,
          int? intervalSeconds,
          ProcessResourceDisplay? display}) =>
      ProcessResourcePreferences(
        enabled: enabled ?? this.enabled,
        intervalSeconds: intervals.contains(intervalSeconds)
            ? intervalSeconds!
            : this.intervalSeconds,
        display: display ?? this.display,
      );

  @override
  bool operator ==(Object other) =>
      other is ProcessResourcePreferences &&
      other.enabled == enabled &&
      other.intervalSeconds == intervalSeconds &&
      other.display == display;
  @override
  int get hashCode => Object.hash(enabled, intervalSeconds, display);
}
