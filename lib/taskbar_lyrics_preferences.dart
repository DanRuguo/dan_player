import 'package:flutter/foundation.dart';

/// The values are stored independently of the taskbar's current orientation.
/// Start/end mean left/right horizontally and top/bottom vertically.
enum TaskbarLyricPosition { auto, start, center, end }

enum TaskbarLyricColorScheme { player, system }

@immutable
class TaskbarLyricsPreferences {
  const TaskbarLyricsPreferences({
    this.position = TaskbarLyricPosition.auto,
    this.showNextTrack = true,
    this.showPauseIndicator = true,
    this.areaSelection = 0,
    this.strokeEnabled = false,
    this.showNextButton = false,
    this.colorScheme = TaskbarLyricColorScheme.player,
    this.showNextLyric = true,
  }) : assert(areaSelection >= 0 && areaSelection <= maxAreaSelection);

  final TaskbarLyricPosition position;
  final bool showNextTrack;
  final bool showPauseIndicator;
  final int areaSelection;
  final bool strokeEnabled;
  final bool showNextButton;
  final TaskbarLyricColorScheme colorScheme;
  final bool showNextLyric;
  static const maxAreaSelection = 65535;

  static int safeAreaSelection(Object? value, {int fallback = 0}) =>
      value is int && value >= 0 && value <= maxAreaSelection
          ? value
          : fallback >= 0 && fallback <= maxAreaSelection
              ? fallback
              : 0;

  TaskbarLyricsPreferences copyWith({
    TaskbarLyricPosition? position,
    bool? showNextTrack,
    bool? showPauseIndicator,
    int? areaSelection,
    bool? strokeEnabled,
    bool? showNextButton,
    TaskbarLyricColorScheme? colorScheme,
    bool? showNextLyric,
  }) =>
      TaskbarLyricsPreferences(
        position: position ?? this.position,
        showNextTrack: showNextTrack ?? this.showNextTrack,
        showPauseIndicator: showPauseIndicator ?? this.showPauseIndicator,
        areaSelection:
            safeAreaSelection(areaSelection, fallback: this.areaSelection),
        strokeEnabled: strokeEnabled ?? this.strokeEnabled,
        showNextButton: showNextButton ?? this.showNextButton,
        colorScheme: colorScheme ?? this.colorScheme,
        showNextLyric: showNextLyric ?? this.showNextLyric,
      );

  TaskbarLyricsPreferences nextArea() =>
      copyWith(areaSelection: (areaSelection + 1) % (maxAreaSelection + 1));

  Map<String, Object> toMap() => {
        'position': position.name,
        'showNextTrack': showNextTrack,
        'showPauseIndicator': showPauseIndicator,
        'areaSelection': areaSelection,
        'strokeEnabled': strokeEnabled,
        'showNextButton': showNextButton,
        'colorScheme': colorScheme.name,
        'showNextLyric': showNextLyric,
      };

  factory TaskbarLyricsPreferences.fromMap(Object? raw) {
    const defaults = TaskbarLyricsPreferences();
    if (raw is! Map) return defaults;
    final position = TaskbarLyricPosition.values
        .where((position) => raw['position'] == position.name)
        .firstOrNull;
    final colorScheme = TaskbarLyricColorScheme.values
        .where((color) => raw['colorScheme'] == color.name)
        .firstOrNull;
    return TaskbarLyricsPreferences(
      position: position ?? defaults.position,
      showNextTrack: raw['showNextTrack'] is bool
          ? raw['showNextTrack'] as bool
          : defaults.showNextTrack,
      showPauseIndicator: raw['showPauseIndicator'] is bool
          ? raw['showPauseIndicator'] as bool
          : defaults.showPauseIndicator,
      areaSelection: safeAreaSelection(raw['areaSelection']),
      strokeEnabled: raw['strokeEnabled'] is bool
          ? raw['strokeEnabled'] as bool
          : defaults.strokeEnabled,
      showNextButton: raw['showNextButton'] is bool
          ? raw['showNextButton'] as bool
          : defaults.showNextButton,
      colorScheme: colorScheme ?? defaults.colorScheme,
      showNextLyric: raw['showNextLyric'] is bool
          ? raw['showNextLyric'] as bool
          : defaults.showNextLyric,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TaskbarLyricsPreferences &&
      other.position == position &&
      other.showNextTrack == showNextTrack &&
      other.showPauseIndicator == showPauseIndicator &&
      other.areaSelection == areaSelection &&
      other.strokeEnabled == strokeEnabled &&
      other.showNextButton == showNextButton &&
      other.colorScheme == colorScheme &&
      other.showNextLyric == showNextLyric;

  @override
  int get hashCode => Object.hash(position, showNextTrack, showPauseIndicator,
      areaSelection, strokeEnabled, showNextButton, colorScheme, showNextLyric);
}
