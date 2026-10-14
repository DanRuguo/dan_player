import 'package:flutter/widgets.dart';

enum LibraryRowLayout { classic, columns }

enum StartupFooter { brand, progress }

/// Presentation only: this never changes library or playlist ordering.
@immutable
class UiLayoutPreferences {
  const UiLayoutPreferences({
    this.libraryRowLayout = LibraryRowLayout.classic,
    this.compactPlaylists = true,
    this.simplePlaybackBarPlaylist = false,
    this.startupFooter = StartupFooter.brand,
  });

  final LibraryRowLayout libraryRowLayout;
  final bool compactPlaylists;
  final bool simplePlaybackBarPlaylist;
  final StartupFooter startupFooter;

  UiLayoutPreferences copyWith({
    LibraryRowLayout? libraryRowLayout,
    bool? compactPlaylists,
    bool? simplePlaybackBarPlaylist,
    StartupFooter? startupFooter,
  }) =>
      UiLayoutPreferences(
        libraryRowLayout: libraryRowLayout ?? this.libraryRowLayout,
        compactPlaylists: compactPlaylists ?? this.compactPlaylists,
        simplePlaybackBarPlaylist:
            simplePlaybackBarPlaylist ?? this.simplePlaybackBarPlaylist,
        startupFooter: startupFooter ?? this.startupFooter,
      );

  Map<String, Object> toMap() => {
        'libraryRowLayout': libraryRowLayout.name,
        'compactPlaylists': compactPlaylists,
        'simplePlaybackBarPlaylist': simplePlaybackBarPlaylist,
        'startupFooter': startupFooter.name,
      };

  factory UiLayoutPreferences.fromMap(Object? value) {
    if (value is! Map) return const UiLayoutPreferences();
    return UiLayoutPreferences(
      libraryRowLayout: LibraryRowLayout.values.firstWhere(
        (layout) => layout.name == value['libraryRowLayout'],
        orElse: () => LibraryRowLayout.classic,
      ),
      startupFooter: StartupFooter.values.firstWhere(
        (footer) => footer.name == value['startupFooter'],
        orElse: () => StartupFooter.brand,
      ),
      compactPlaylists: value['compactPlaylists'] is bool
          ? value['compactPlaylists'] as bool
          : true,
      simplePlaybackBarPlaylist: value['simplePlaybackBarPlaylist'] is bool
          ? value['simplePlaybackBarPlaylist'] as bool
          : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UiLayoutPreferences &&
      libraryRowLayout == other.libraryRowLayout &&
      compactPlaylists == other.compactPlaylists &&
      simplePlaybackBarPlaylist == other.simplePlaybackBarPlaylist &&
      startupFooter == other.startupFooter;
  @override
  int get hashCode => Object.hash(libraryRowLayout, compactPlaylists,
      simplePlaybackBarPlaylist, startupFooter);
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
