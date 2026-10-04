enum ProcessResourceDisplay { numbers, line, bar }

/// Display choices only; sampling is active only while the monitor is visible.
class ProcessResourcePreferences {
  const ProcessResourcePreferences({
    this.enabled = false,
    this.intervalSeconds = 5,
    this.display = ProcessResourceDisplay.numbers,
    this.showInSidebar = false,
    this.showInLyrics = false,
  });

  final int intervalSeconds;
  final bool enabled;
  final ProcessResourceDisplay display;
  final bool showInSidebar, showInLyrics;
  static const intervals = [1, 5, 10];

  factory ProcessResourcePreferences.fromMap(dynamic value) {
    if (value is! Map) return const ProcessResourcePreferences();
    final interval = value['intervalSeconds'];
    final name = value['display'];
    return ProcessResourcePreferences(
      enabled: value['enabled'] is bool ? value['enabled'] as bool : false,
      showInSidebar: value['showInSidebar'] == true,
      showInLyrics: value['showInLyrics'] == true,
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
        'showInSidebar': showInSidebar,
        'showInLyrics': showInLyrics,
        'intervalSeconds': intervalSeconds,
        'display': display.name
      };
  ProcessResourcePreferences copyWith(
          {bool? enabled,
          int? intervalSeconds,
          ProcessResourceDisplay? display,
          bool? showInSidebar,
          bool? showInLyrics}) =>
      ProcessResourcePreferences(
        enabled: enabled ?? this.enabled,
        intervalSeconds: intervals.contains(intervalSeconds)
            ? intervalSeconds!
            : this.intervalSeconds,
        display: display ?? this.display,
        showInSidebar: showInSidebar ?? this.showInSidebar,
        showInLyrics: showInLyrics ?? this.showInLyrics,
      );

  @override
  bool operator ==(Object other) =>
      other is ProcessResourcePreferences &&
      other.enabled == enabled &&
      other.intervalSeconds == intervalSeconds &&
      other.display == display &&
      other.showInSidebar == showInSidebar &&
      other.showInLyrics == showInLyrics;
  @override
  int get hashCode => Object.hash(
      enabled, intervalSeconds, display, showInSidebar, showInLyrics);
}
