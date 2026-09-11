import 'package:desktop_lyric/frame_pacing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum SpectrumDensity {
  low(36),
  medium(72),
  high(112);

  const SpectrumDensity(this.maximumBars);
  final int maximumBars;
}

/// Visual preferences; audio clocks and accessibility remain independent.
@immutable
class RenderingPreferences {
  const RenderingPreferences(
      {this.pauseWhenHidden = true,
      this.lyricSpectrum = true,
      this.spectrumDensity = SpectrumDensity.high,
      this.frameRate = const FrameRatePreference()});

  final bool pauseWhenHidden;
  final bool lyricSpectrum;
  final SpectrumDensity spectrumDensity;
  final FrameRatePreference frameRate;

  RenderingPreferences copyWith(
          {bool? pauseWhenHidden,
          bool? lyricSpectrum,
          SpectrumDensity? spectrumDensity,
          FrameRatePreference? frameRate}) =>
      RenderingPreferences(
        pauseWhenHidden: pauseWhenHidden ?? this.pauseWhenHidden,
        lyricSpectrum: lyricSpectrum ?? this.lyricSpectrum,
        spectrumDensity: spectrumDensity ?? this.spectrumDensity,
        frameRate: frameRate ?? this.frameRate,
      );

  Map<String, Object> toMap() => {
        'pauseWhenHidden': pauseWhenHidden,
        'lyricSpectrum': lyricSpectrum,
        'spectrumDensity': spectrumDensity.name,
        'frameRate': frameRate.toMap()
      };

  factory RenderingPreferences.fromMap(Object? value) => RenderingPreferences(
        spectrumDensity: SpectrumDensity.values.firstWhere(
            (v) => value is Map && value['spectrumDensity'] == v.name,
            orElse: () => SpectrumDensity.high),
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
      spectrumDensity == other.spectrumDensity &&
      frameRate == other.frameRate;

  @override
  int get hashCode =>
      Object.hash(pauseWhenHidden, lyricSpectrum, spectrumDensity, frameRate);
}

/// A listenable lets stream/timer owners apply a change synchronously even
/// while a native-hidden window is not producing Flutter frames.
class RenderingPreferencesScope
    extends InheritedNotifier<ValueListenable<RenderingPreferences>> {
  const RenderingPreferencesScope({
    super.key,
    required ValueListenable<RenderingPreferences> preferences,
    required super.child,
  }) : super(notifier: preferences);

  static const _defaults = AlwaysStoppedAnimation(RenderingPreferences());

  static ValueListenable<RenderingPreferences> listenableOf(
          BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<RenderingPreferencesScope>()
          ?.notifier ??
      _defaults;

  static RenderingPreferences of(BuildContext context) =>
      listenableOf(context).value;
}
