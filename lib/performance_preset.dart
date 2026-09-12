import 'package:flutter/foundation.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'background_preferences.dart';
import 'player_experience_preferences.dart';
import 'rendering_preferences.dart';

enum PerformanceMode { custom, economy, performance }

/// Only preferences owned by the presets are captured. Playback, network and
/// window geometry remain independent, including edits made while a preset runs.
@immutable
class PerformanceSnapshot {
  const PerformanceSnapshot(
      {required this.rendering,
      required this.backgrounds,
      required this.dynamicTheme,
      required this.springLyrics,
      required this.taskbarSongPreview,
      required this.trayBlur});
  final RenderingPreferences rendering;
  final BackgroundPreferences backgrounds;
  final bool dynamicTheme, springLyrics, taskbarSongPreview;
  final double trayBlur;

  factory PerformanceSnapshot.capture(
          RenderingPreferences rendering,
          BackgroundPreferences backgrounds,
          PlayerExperiencePreferences experience,
          bool dynamicTheme) =>
      PerformanceSnapshot(
          rendering: rendering,
          backgrounds: backgrounds,
          dynamicTheme: dynamicTheme,
          springLyrics: experience.springLyrics,
          taskbarSongPreview: experience.taskbarSongPreview,
          trayBlur: experience.trayMenuBlurRadius);

  Map<String, Object> toMap() => {
        'rendering': rendering.toMap(),
        'backgrounds': backgrounds.toMap(),
        'dynamicTheme': dynamicTheme,
        'springLyrics': springLyrics,
        'taskbarSongPreview': taskbarSongPreview,
        'trayBlur': trayBlur
      };

  static PerformanceSnapshot? fromMap(Object? raw) {
    if (raw is! Map ||
        raw['rendering'] is! Map ||
        raw['backgrounds'] is! Map ||
        raw['dynamicTheme'] is! bool ||
        raw['springLyrics'] is! bool ||
        raw['taskbarSongPreview'] is! bool ||
        raw['trayBlur'] is! num) return null;
    return PerformanceSnapshot(
        rendering: RenderingPreferences.fromMap(raw['rendering']),
        backgrounds: BackgroundPreferences.fromMap(raw['backgrounds']),
        dynamicTheme: raw['dynamicTheme'],
        springLyrics: raw['springLyrics'],
        taskbarSongPreview: raw['taskbarSongPreview'],
        trayBlur: PlayerExperiencePreferences.safeTrayMenuBlurRadius(
            raw['trayBlur']));
  }

  PerformanceSnapshot forMode(PerformanceMode mode) {
    if (mode == PerformanceMode.custom) return this;
    final high = mode == PerformanceMode.performance;
    var background = backgrounds;
    for (final scene in BackgroundScene.values) {
      final original = backgrounds.forScene(scene);
      background = background.withScene(
          scene,
          original.copyWith(
            source: !high
                ? BackgroundSource.solid
                : original.source == BackgroundSource.solid
                    ? BackgroundSource.artwork
                    : original.source,
            motion: high,
          ));
    }
    return PerformanceSnapshot(
        rendering: rendering.copyWith(
            pauseWhenHidden: true,
            lyricSpectrum: high,
            compactSpectrum: high,
            surfaceBlur: high,
            spectrumDensity: high ? SpectrumDensity.high : SpectrumDensity.low,
            frameRate: FrameRatePreference(
                mode: high ? FrameRateMode.display : FrameRateMode.fixed,
                fps: 30)),
        backgrounds: background,
        dynamicTheme: high,
        springLyrics: high,
        taskbarSongPreview: high,
        trayBlur: high ? 20 : 0);
  }
}

@immutable
class PerformancePresetState {
  const PerformancePresetState(
      {this.mode = PerformanceMode.custom, this.before});
  final PerformanceMode mode;
  final PerformanceSnapshot? before;
  Map<String, Object> toMap() =>
      {'mode': mode.name, if (before != null) 'before': before!.toMap()};
  factory PerformancePresetState.fromMap(Object? raw) {
    if (raw is! Map) return const PerformancePresetState();
    final before = PerformanceSnapshot.fromMap(raw['before']);
    if (before == null) return const PerformancePresetState();
    return PerformancePresetState(
        before: before,
        mode: PerformanceMode.values.firstWhere((v) => v.name == raw['mode'],
            orElse: () => PerformanceMode.custom));
  }
}

class PerformancePresetController
    extends ValueNotifier<PerformancePresetState> {
  PerformancePresetController(
      {required this.capture, required this.apply, required this.persist})
      : super(const PerformancePresetState());
  final PerformanceSnapshot Function() capture;
  final void Function(PerformanceSnapshot) apply;
  final Future<void> Function() persist;
  bool _busy = false;

  Future<void> select(PerformanceMode mode) async {
    if (_busy || value.mode == mode) return;
    final originalState = value;
    final live = capture();
    // Starting a new override always captures the current user's preferences.
    final before = value.mode == PerformanceMode.custom ? live : value.before!;
    _busy = true;
    try {
      if (value.mode == PerformanceMode.custom) {
        value = PerformancePresetState(before: before);
        await persist(); // Save the recovery copy before changing any preference.
      }
      apply(before.forMode(mode));
      value = mode == PerformanceMode.custom
          ? const PerformancePresetState()
          : PerformancePresetState(mode: mode, before: before);
      await persist();
    } catch (_) {
      apply(live);
      value = originalState;
      // Another settings writer may have committed the temporary override
      // before this request was superseded. Persist the rollback too, while
      // preserving the original failure if storage remains unavailable.
      try {
        await persist();
      } catch (_) {}
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
