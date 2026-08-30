import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Visibility policy only. This does not create pages, control playback, or
/// override accessibility animation preferences and the platform scheduler.
@immutable
class RenderingPreferences {
  const RenderingPreferences({this.pauseWhenHidden = true});

  final bool pauseWhenHidden;

  RenderingPreferences copyWith({bool? pauseWhenHidden}) =>
      RenderingPreferences(
        pauseWhenHidden: pauseWhenHidden ?? this.pauseWhenHidden,
      );

  Map<String, Object> toMap() => {'pauseWhenHidden': pauseWhenHidden};

  factory RenderingPreferences.fromMap(Object? value) => RenderingPreferences(
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
      other is RenderingPreferences && pauseWhenHidden == other.pauseWhenHidden;

  @override
  int get hashCode => pauseWhenHidden.hashCode;
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
