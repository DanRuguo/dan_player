import 'dart:math' as math;

import 'package:dan_player/component/app_content_transition.dart';
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
    final labels = [ui('评分和标签'), ui('全库书签')];
    final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1);
    var segmentWidth = 44.0;
    for (final label in labels) {
      painter.text =
          TextSpan(text: label, style: Theme.of(context).textTheme.labelLarge);
      painter.layout();
      segmentWidth = math.max(segmentWidth, painter.width.ceilToDouble() + 56);
    }
    painter.dispose();
    final tabs = AppSegmentedControl<bool>(
      value: _bookmarks,
      options: [
        AppSegmentOption(value: false, label: labels[0], icon: Symbols.star),
        AppSegmentOption(
            value: true, label: labels[1], icon: Symbols.bookmarks),
      ],
      onChanged: (value) => setState(() => _bookmarks = value),
    );
    // Keep one selector mounted above both filter panels. Different hosts used
    // to size and recreate it independently, interrupting its selected fill.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(
            builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    key: const ValueKey('personal-library-tabs'),
                    width: math.min(constraints.maxWidth, segmentWidth * 2 + 4),
                    child: tabs))),
        const SizedBox(height: 12),
        Expanded(
            child: AppContentTransition(
                key: const ValueKey('personal-library-content'),
                identity: _bookmarks,
                child: Padding(
                    padding: EdgeInsets.only(
                        bottom: _bookmarks
                            ? NowPlayingBarMetrics.reservedSpace(context)
                            : 0),
                    child: _bookmarks
                        ? BookmarkLibraryDialog(
                            embedded: true, store: widget.bookmarkStore)
                        : PersonalLibraryDialog(
                            embedded: true,
                            store: widget.personalStore,
                            audios: widget.audios)))),
      ]),
    );
  }
}
