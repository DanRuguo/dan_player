import 'package:flutter/foundation.dart';
import 'package:dan_player/play_service/playback_rate.dart';

/// Additive preferences for the desktop/player experience. Missing or damaged
/// fields use defaults without migrating the library or changing playlist data.
@immutable
class PlayerExperiencePreferences {
  const PlayerExperiencePreferences({
    this.closeToTray = false,
    this.taskbarControls = true,
    this.taskbarSongPreview = true,
    this.trayMenuBlurRadius = 0,
    this.springLyrics = true,
    this.desktopLyricVertical = false,
    this.playbackRate = 1.0,
    this.exclusiveOutput = false,
    this.sidebarWidth = defaultSidebarWidth,
    this.sidebarLocked = false,
    this.windowSizeLocked = false,
    this.windowAspectRatioLocked = false,
    this.windowAspectRatio = 0,
    this.roundedWindowCorners = true,
    this.preventSleepDuringPlayback = false,
  });

  final bool closeToTray;
  final bool taskbarControls;
  final bool taskbarSongPreview;

  /// Gaussian kernel radius in logical pixels. Zero keeps the menu solid.
  final double trayMenuBlurRadius;
  final bool springLyrics;
  final bool desktopLyricVertical;
  final double playbackRate;
  final bool exclusiveOutput;
  final double sidebarWidth;
  final bool sidebarLocked;
  final bool windowSizeLocked;
  final bool windowAspectRatioLocked;
  final bool roundedWindowCorners;
  final bool preventSleepDuringPlayback;

  /// The normal-window client ratio captured when ratio locking is enabled.
  /// Zero means that the next live application should capture the current
  /// window instead of guessing from a stale or missing setting.
  final double windowAspectRatio;

  static const minSidebarWidth = 76.0;
  static const maxTrayMenuBlurRadius = 24.0;

  static double safeTrayMenuBlurRadius(Object? value, {double fallback = 0}) {
    final safeFallback =
        fallback.isFinite ? fallback.clamp(0.0, maxTrayMenuBlurRadius) : 0.0;
    final number = value is num ? value.toDouble() : safeFallback;
    if (!number.isFinite) return safeFallback;
    return number.clamp(0, maxTrayMenuBlurRadius);
  }

  static const defaultSidebarWidth = 300.0;
  static const maxSidebarWidth = 380.0;
  static const compactSidebarThreshold = 156.0;

  static double safeSidebarWidth(Object? value,
      {double fallback = defaultSidebarWidth}) {
    final number = value is num ? value.toDouble() : fallback;
    if (!number.isFinite) return fallback;
    return number.clamp(minSidebarWidth, maxSidebarWidth);
  }

  static const minPlaybackRate = PlaybackRate.min;
  static const maxPlaybackRate = PlaybackRate.max;
  static const playbackRates = PlaybackRate.presets;

  static double safePlaybackRate(Object? value, {double fallback = 1.0}) =>
      PlaybackRate.sanitize(value, fallback: fallback);

  static double safeWindowAspectRatio(Object? value, {double fallback = 0}) {
    final number = value is num ? value.toDouble() : fallback;
    if (number == 0) return 0;
    if (!number.isFinite || number < 0.25 || number > 4) return fallback;
    return number;
  }

  PlayerExperiencePreferences copyWith({
    bool? closeToTray,
    bool? taskbarControls,
    bool? taskbarSongPreview,
    double? trayMenuBlurRadius,
    bool? springLyrics,
    bool? desktopLyricVertical,
    double? playbackRate,
    bool? exclusiveOutput,
    double? sidebarWidth,
    bool? sidebarLocked,
    bool? windowSizeLocked,
    bool? windowAspectRatioLocked,
    double? windowAspectRatio,
    bool? roundedWindowCorners,
    bool? preventSleepDuringPlayback,
  }) {
    var nextWindowSizeLocked = windowSizeLocked ?? this.windowSizeLocked;
    var nextWindowAspectRatioLocked =
        windowAspectRatioLocked ?? this.windowAspectRatioLocked;
    if (nextWindowSizeLocked && nextWindowAspectRatioLocked) {
      // An explicitly enabled ratio lock wins over a previously enabled size
      // lock. In every other ambiguous case the stricter fixed-size policy
      // wins, including old callers that pass both flags together.
      if (windowAspectRatioLocked == true && windowSizeLocked != true) {
        nextWindowSizeLocked = false;
      } else {
        nextWindowAspectRatioLocked = false;
      }
    }
    return PlayerExperiencePreferences(
      closeToTray: closeToTray ?? this.closeToTray,
      taskbarControls: taskbarControls ?? this.taskbarControls,
      taskbarSongPreview: taskbarSongPreview ?? this.taskbarSongPreview,
      trayMenuBlurRadius: safeTrayMenuBlurRadius(trayMenuBlurRadius,
          fallback: this.trayMenuBlurRadius),
      springLyrics: springLyrics ?? this.springLyrics,
      desktopLyricVertical: desktopLyricVertical ?? this.desktopLyricVertical,
      playbackRate: safePlaybackRate(playbackRate, fallback: this.playbackRate),
      exclusiveOutput: exclusiveOutput ?? this.exclusiveOutput,
      sidebarWidth: safeSidebarWidth(sidebarWidth, fallback: this.sidebarWidth),
      sidebarLocked: sidebarLocked ?? this.sidebarLocked,
      windowSizeLocked: nextWindowSizeLocked,
      windowAspectRatioLocked: nextWindowAspectRatioLocked,
      roundedWindowCorners: roundedWindowCorners ?? this.roundedWindowCorners,
      preventSleepDuringPlayback:
          preventSleepDuringPlayback ?? this.preventSleepDuringPlayback,
      windowAspectRatio: safeWindowAspectRatio(
        windowAspectRatio,
        fallback: this.windowAspectRatio,
      ),
    );
  }

  Map<String, Object> toMap() => {
        'closeToTray': closeToTray,
        'taskbarControls': taskbarControls,
        'taskbarSongPreview': taskbarSongPreview,
        'trayMenuBlurRadius': safeTrayMenuBlurRadius(trayMenuBlurRadius),
        'springLyrics': springLyrics,
        'desktopLyricVertical': desktopLyricVertical,
        'playbackRate': safePlaybackRate(playbackRate),
        'exclusiveOutput': exclusiveOutput,
        'sidebarWidth': safeSidebarWidth(sidebarWidth),
        'sidebarLocked': sidebarLocked,
        'windowSizeLocked': windowSizeLocked,
        // Persist one authoritative window constraint even when a direct
        // constructor from older code temporarily supplied both flags.
        'windowAspectRatioLocked': windowAspectRatioLocked && !windowSizeLocked,
        'roundedWindowCorners': roundedWindowCorners,
        'preventSleepDuringPlayback': preventSleepDuringPlayback,
        'windowAspectRatio': safeWindowAspectRatio(windowAspectRatio),
      };

  factory PlayerExperiencePreferences.fromMap(Object? value) {
    const defaults = PlayerExperiencePreferences();
    if (value is! Map) return defaults;
    bool flag(String key, bool fallback) =>
        value[key] is bool ? value[key] as bool : fallback;
    final windowSizeLocked =
        flag('windowSizeLocked', defaults.windowSizeLocked);
    final windowAspectRatioLocked = !windowSizeLocked &&
        flag('windowAspectRatioLocked', defaults.windowAspectRatioLocked);
    return PlayerExperiencePreferences(
      closeToTray: flag('closeToTray', defaults.closeToTray),
      taskbarControls: flag('taskbarControls', defaults.taskbarControls),
      taskbarSongPreview:
          flag('taskbarSongPreview', defaults.taskbarSongPreview),
      trayMenuBlurRadius: safeTrayMenuBlurRadius(value['trayMenuBlurRadius']),
      springLyrics: flag('springLyrics', defaults.springLyrics),
      desktopLyricVertical:
          flag('desktopLyricVertical', defaults.desktopLyricVertical),
      playbackRate: safePlaybackRate(value['playbackRate']),
      exclusiveOutput: flag('exclusiveOutput', defaults.exclusiveOutput),
      sidebarWidth: safeSidebarWidth(value['sidebarWidth']),
      sidebarLocked: flag('sidebarLocked', defaults.sidebarLocked),
      windowSizeLocked: windowSizeLocked,
      windowAspectRatioLocked: windowAspectRatioLocked,
      roundedWindowCorners:
          flag('roundedWindowCorners', defaults.roundedWindowCorners),
      preventSleepDuringPlayback: flag('preventSleepDuringPlayback', false),
      windowAspectRatio: safeWindowAspectRatio(value['windowAspectRatio']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerExperiencePreferences &&
      closeToTray == other.closeToTray &&
      taskbarControls == other.taskbarControls &&
      taskbarSongPreview == other.taskbarSongPreview &&
      trayMenuBlurRadius == other.trayMenuBlurRadius &&
      springLyrics == other.springLyrics &&
      desktopLyricVertical == other.desktopLyricVertical &&
      playbackRate == other.playbackRate &&
      exclusiveOutput == other.exclusiveOutput &&
      sidebarWidth == other.sidebarWidth &&
      sidebarLocked == other.sidebarLocked &&
      windowSizeLocked == other.windowSizeLocked &&
      windowAspectRatioLocked == other.windowAspectRatioLocked &&
      roundedWindowCorners == other.roundedWindowCorners &&
      preventSleepDuringPlayback == other.preventSleepDuringPlayback &&
      windowAspectRatio == other.windowAspectRatio;

  @override
  int get hashCode => Object.hash(
      closeToTray,
      taskbarControls,
      taskbarSongPreview,
      trayMenuBlurRadius,
      springLyrics,
      desktopLyricVertical,
      playbackRate,
      exclusiveOutput,
      sidebarWidth,
      sidebarLocked,
      windowSizeLocked,
      windowAspectRatioLocked,
      roundedWindowCorners,
      preventSleepDuringPlayback,
      windowAspectRatio);
}
