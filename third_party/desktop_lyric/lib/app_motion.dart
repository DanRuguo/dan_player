import 'package:flutter/material.dart';

enum MotionKind {
  startup,
  nextTrack,
  tracking,
  entrance,
  transitions,
  layout,
  lyrics,
  feedback,
  theme
}

final desktopMotionPreferences = ValueNotifier(const MotionPreferences());

@immutable
class MotionPreferences {
  const MotionPreferences({this.disabled = const {}});
  final Set<MotionKind> disabled;
  bool allows(MotionKind kind) => !disabled.contains(kind);
  bool get allEnabled => disabled.isEmpty;
  bool get allDisabled => disabled.length == MotionKind.values.length;
  MotionPreferences withKind(MotionKind kind, bool enabled) =>
      MotionPreferences(
          disabled: Set.unmodifiable({...disabled}
            ..removeWhere((v) => v == kind)
            ..addAll(enabled ? <MotionKind>[] : [kind])));
  MotionPreferences all(bool enabled) => MotionPreferences(
      disabled: enabled ? const {} : Set.unmodifiable(MotionKind.values));
  Map<String, bool> toMap() =>
      {for (final kind in MotionKind.values) kind.name: allows(kind)};
  factory MotionPreferences.fromMap(Object? raw) => MotionPreferences(
          disabled: Set.unmodifiable({
        for (final kind in MotionKind.values)
          if (raw is Map && raw[kind.name] == false) kind
      }));
  @override
  bool operator ==(Object other) =>
      other is MotionPreferences &&
      disabled.length == other.disabled.length &&
      disabled.containsAll(other.disabled);
  @override
  int get hashCode => Object.hashAll(MotionKind.values.map(allows));
}

class MotionPreferencesScope extends InheritedWidget {
  const MotionPreferencesScope(
      {super.key, required this.preferences, required super.child});
  final MotionPreferences preferences;
  static MotionPreferences of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MotionPreferencesScope>()
          ?.preferences ??
      const MotionPreferences();
  @override
  bool updateShouldNotify(MotionPreferencesScope old) =>
      preferences != old.preferences;
}

abstract final class AppMotion {
  static Duration duration(
          BuildContext context, MotionKind kind, Duration value) =>
      enabled(context, kind) ? value : Duration.zero;
  static bool enabled(BuildContext context, MotionKind kind) =>
      MotionPreferencesScope.of(context).allows(kind) &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
  static ThemeData controlTheme(ThemeData theme, bool enabled) {
    if (enabled) return theme;
    ButtonStyle instant(ButtonStyle? style) =>
        (style ?? const ButtonStyle()).copyWith(
            animationDuration: Duration.zero,
            splashFactory: NoSplash.splashFactory);
    return theme.copyWith(
      splashFactory: NoSplash.splashFactory,
      textButtonTheme:
          TextButtonThemeData(style: instant(theme.textButtonTheme.style)),
      filledButtonTheme:
          FilledButtonThemeData(style: instant(theme.filledButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: instant(theme.outlinedButtonTheme.style)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: instant(theme.elevatedButtonTheme.style)),
      iconButtonTheme:
          IconButtonThemeData(style: instant(theme.iconButtonTheme.style)),
      segmentedButtonTheme: SegmentedButtonThemeData(
          style: instant(theme.segmentedButtonTheme.style)),
      menuButtonTheme:
          MenuButtonThemeData(style: instant(theme.menuButtonTheme.style)),
    );
  }

  static const Duration quick = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration emphasized = Duration(milliseconds: 240);
  static const Duration long = Duration(milliseconds: 300);

  // Smooth sampled positions without changing the playback or word clock.
  static const Duration followSample = Duration(milliseconds: 60);
  static const Duration lyricLine = Duration(milliseconds: 480);
  static const Duration lyricScroll = Duration(milliseconds: 600);
  static const Duration lyricSpring = Duration(milliseconds: 720);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);
}
