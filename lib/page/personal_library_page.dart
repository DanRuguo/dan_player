import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/now_playing_bar_metrics.dart';
import 'package:dan_player/component/personal_library_dialog.dart';
import 'package:dan_player/component/listening_tools_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playback_bookmarks.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class PersonalLibraryPanel extends StatefulWidget {
  const PersonalLibraryPanel(
      {super.key, this.audios, this.personalStore, this.bookmarkStore});
  final List<Audio>? audios;
  final PersonalLibrary? personalStore;
  final PlaybackBookmarkStore? bookmarkStore;
  @override
  State<PersonalLibraryPanel> createState() => _PersonalLibraryPanelState();
}

class _PersonalLibraryPanelState extends State<PersonalLibraryPanel> {
  bool _bookmarks = false;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final tabs = AppSegmentedControl<bool>(
      value: _bookmarks,
      options: [
        AppSegmentOption(
            value: false, label: ui('歌曲'), icon: Symbols.library_music),
        AppSegmentOption(
            value: true, label: ui('全库书签'), icon: Symbols.bookmarks),
      ],
      onChanged: (value) => setState(() => _bookmarks = value),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8,
          _bookmarks ? NowPlayingBarMetrics.reservedSpace(context) : 0),
      child: _bookmarks
          ? BookmarkLibraryDialog(
              embedded: true, store: widget.bookmarkStore, header: tabs)
          : PersonalLibraryDialog(
              embedded: true,
              store: widget.personalStore,
              audios: widget.audios,
              header: tabs),
    );
  }
}
