import 'package:flutter/widgets.dart';

enum LibraryRowLayout { classic, columns }

/// Presentation only: this never changes library or playlist ordering.
@immutable
class UiLayoutPreferences {
  const UiLayoutPreferences({
    this.libraryRowLayout = LibraryRowLayout.classic,
    this.compactPlaylists = true,
  });

  final LibraryRowLayout libraryRowLayout;
  final bool compactPlaylists;

  UiLayoutPreferences copyWith({
    LibraryRowLayout? libraryRowLayout,
    bool? compactPlaylists,
  }) =>
      UiLayoutPreferences(
        libraryRowLayout: libraryRowLayout ?? this.libraryRowLayout,
        compactPlaylists: compactPlaylists ?? this.compactPlaylists,
      );

  Map<String, Object> toMap() => {
        'libraryRowLayout': libraryRowLayout.name,
        'compactPlaylists': compactPlaylists,
      };

  factory UiLayoutPreferences.fromMap(Object? value) {
    if (value is! Map) return const UiLayoutPreferences();
    return UiLayoutPreferences(
      libraryRowLayout: LibraryRowLayout.values.firstWhere(
        (layout) => layout.name == value['libraryRowLayout'],
        orElse: () => LibraryRowLayout.classic,
      ),
      compactPlaylists: value['compactPlaylists'] is bool
          ? value['compactPlaylists'] as bool
          : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UiLayoutPreferences &&
      libraryRowLayout == other.libraryRowLayout &&
      compactPlaylists == other.compactPlaylists;
  @override
  int get hashCode => Object.hash(libraryRowLayout, compactPlaylists);
}

class UiLayoutScope extends InheritedWidget {
  const UiLayoutScope(
      {super.key, required this.preferences, required super.child});
  final UiLayoutPreferences preferences;

  static UiLayoutPreferences of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<UiLayoutScope>()
          ?.preferences ??
      const UiLayoutPreferences();

  @override
  bool updateShouldNotify(UiLayoutScope oldWidget) =>
      preferences != oldWidget.preferences;
}
