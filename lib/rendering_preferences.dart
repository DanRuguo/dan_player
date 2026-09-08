import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Visibility policy only. This does not create pages, control playback, or
/// override accessibility animation preferences and the platform scheduler.
@immutable
class RenderingPreferences {
  const RenderingPreferences(
      {this.pauseWhenHidden = true, this.lyricSpectrum = true});

  final bool pauseWhenHidden;
  final bool lyricSpectrum;

  RenderingPreferences copyWith({bool? pauseWhenHidden, bool? lyricSpectrum}) =>
      RenderingPreferences(
        pauseWhenHidden: pauseWhenHidden ?? this.pauseWhenHidden,
        lyricSpectrum: lyricSpectrum ?? this.lyricSpectrum,
      );

  Map<String, Object> toMap() =>
      {'pauseWhenHidden': pauseWhenHidden, 'lyricSpectrum': lyricSpectrum};

  factory RenderingPreferences.fromMap(Object? value) => RenderingPreferences(
        lyricSpectrum: value is Map && value['lyricSpectrum'] is bool
            ? value['lyricSpectrum'] as bool
            : true,
        pauseWhenHidden: value is Map && value['pauseWhenHidden'] is bool
            ? value['pauseWhenHidden'] as bool
            : true,
      );

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
            (lifecycle == null || lifecycle == AppLifecycleState.resumed));
  }

  @override
  bool operator ==(Object other) =>
      other is RenderingPreferences &&
      pauseWhenHidden == other.pauseWhenHidden &&
      lyricSpectrum == other.lyricSpectrum;

  @override
  int get hashCode => Object.hash(pauseWhenHidden, lyricSpectrum);
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
