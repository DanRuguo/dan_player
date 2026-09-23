import 'package:desktop_lyric/frame_pacing.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum SpectrumDensity {
  low(36),
  medium(72),
  high(112);

  const SpectrumDensity(this.maximumBars);
  final int maximumBars;
}

enum LyricSpectrumPlacement { progress, cover }

/// Visual preferences; audio clocks and accessibility remain independent.
@immutable
class RenderingPreferences {
  const RenderingPreferences(
      {this.pauseWhenHidden = true,
      this.lyricSpectrum = true,
      this.compactSpectrum = true,
      this.surfaceBlur = true,
      this.animations = const MotionPreferences(),
      this.spectrumDensity = SpectrumDensity.high,
      this.lyricSpectrumPlacement = LyricSpectrumPlacement.progress,
      this.frameRate = const FrameRatePreference()});

  final bool pauseWhenHidden;
  final bool lyricSpectrum;
  final bool compactSpectrum;
  final bool surfaceBlur;
  final SpectrumDensity spectrumDensity;
  final LyricSpectrumPlacement lyricSpectrumPlacement;
  final FrameRatePreference frameRate;
  final MotionPreferences animations;

  RenderingPreferences copyWith(
          {bool? pauseWhenHidden,
          bool? lyricSpectrum,
          bool? compactSpectrum,
          bool? surfaceBlur,
          SpectrumDensity? spectrumDensity,
          LyricSpectrumPlacement? lyricSpectrumPlacement,
          FrameRatePreference? frameRate,
          MotionPreferences? animations}) =>
      RenderingPreferences(
        pauseWhenHidden: pauseWhenHidden ?? this.pauseWhenHidden,
        lyricSpectrum: lyricSpectrum ?? this.lyricSpectrum,
        compactSpectrum: compactSpectrum ?? this.compactSpectrum,
        surfaceBlur: surfaceBlur ?? this.surfaceBlur,
        spectrumDensity: spectrumDensity ?? this.spectrumDensity,
        lyricSpectrumPlacement:
            lyricSpectrumPlacement ?? this.lyricSpectrumPlacement,
        frameRate: frameRate ?? this.frameRate,
        animations: animations ?? this.animations,
      );

  Map<String, Object> toMap() => {
        'pauseWhenHidden': pauseWhenHidden,
        'lyricSpectrum': lyricSpectrum,
        'compactSpectrum': compactSpectrum,
        'surfaceBlur': surfaceBlur,
        'spectrumDensity': spectrumDensity.name,
        'lyricSpectrumPlacement': lyricSpectrumPlacement.name,
        'frameRate': frameRate.toMap(),
        'animations': animations.toMap()
      };

  factory RenderingPreferences.fromMap(Object? value) => RenderingPreferences(
        animations: MotionPreferences.fromMap(
            value is Map ? value['animations'] : null),
        compactSpectrum: value is Map && value['compactSpectrum'] is bool
            ? value['compactSpectrum']
            : true,
        surfaceBlur: value is Map && value['surfaceBlur'] is bool
            ? value['surfaceBlur']
            : true,
        spectrumDensity: SpectrumDensity.values.firstWhere(
            (v) => value is Map && value['spectrumDensity'] == v.name,
            orElse: () => SpectrumDensity.high),
        lyricSpectrumPlacement: LyricSpectrumPlacement.values.firstWhere(
            (v) => value is Map && value['lyricSpectrumPlacement'] == v.name,
            orElse: () => LyricSpectrumPlacement.progress),
        frameRate: FrameRatePreference.fromMap(
            value is Map ? value['frameRate'] : null),
        lyricSpectrum: value is Map && value['lyricSpectrum'] is bool
            ? value['lyricSpectrum'] as bool
            : true,
        pauseWhenHidden: value is Map && value['pauseWhenHidden'] is bool
            ? value['pauseWhenHidden'] as bool
            : true,
      );

  /// Inactive includes a visible desktop window without keyboard focus. Only
  /// hidden/native-hidden/offstage surfaces are eligible for visibility pause.
  /// Paused/detached always stop. Opting out bypasses our visibility gates, not
  /// disposal, reduced motion, or the framework's own offstage frame policy.
  bool allowsVisualUpdates({
    AppLifecycleState? lifecycle,
    bool treeVisible = true,
    bool nativeHidden = false,
  }) {
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      return false;
    }
    return !pauseWhenHidden ||
        (treeVisible &&
            !nativeHidden &&
            (lifecycle == null ||
                lifecycle == AppLifecycleState.resumed ||
                lifecycle == AppLifecycleState.inactive));
  }

  @override
  bool operator ==(Object other) =>
      other is RenderingPreferences &&
      pauseWhenHidden == other.pauseWhenHidden &&
      lyricSpectrum == other.lyricSpectrum &&
      compactSpectrum == other.compactSpectrum &&
      surfaceBlur == other.surfaceBlur &&
      animations == other.animations &&
      spectrumDensity == other.spectrumDensity &&
      lyricSpectrumPlacement == other.lyricSpectrumPlacement &&
      frameRate == other.frameRate;

  @override
  int get hashCode => Object.hash(
      pauseWhenHidden,
      lyricSpectrum,
      compactSpectrum,
      surfaceBlur,
      spectrumDensity,
      lyricSpectrumPlacement,
      frameRate,
      animations);
}

/// A listenable lets stream/timer owners apply a change synchronously even
/// while a native-hidden window is not producing Flutter frames.
class RenderingPreferencesScope extends StatelessWidget {
  const RenderingPreferencesScope({
    super.key,
    required this.preferences,
    required this.child,
  });
  final ValueListenable<RenderingPreferences> preferences;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<RenderingPreferences>(
          valueListenable: preferences,
          child: child,
          builder: (_, value, child) => _RenderingPreferencesData(
              notifier: preferences,
              child: MotionPreferencesScope(
                  preferences: value.animations,
                  child: Theme(
                      data: AppMotion.controlTheme(Theme.of(context),
                          value.animations.allows(MotionKind.feedback)),
                      child: child!))));

  static const _defaults = AlwaysStoppedAnimation(RenderingPreferences());

  static ValueListenable<RenderingPreferences> listenableOf(
          BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_RenderingPreferencesData>()
          ?.notifier ??
      _defaults;

  static RenderingPreferences of(BuildContext context) =>
      listenableOf(context).value;
}

class _RenderingPreferencesData
    extends InheritedNotifier<ValueListenable<RenderingPreferences>> {
  const _RenderingPreferencesData(
      {required super.notifier, required super.child});
}
