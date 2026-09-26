import 'package:dan_player/component/title_bar.dart';
import 'package:dan_player/page/audio_detail_page.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Detail reached from the standalone lyric route keeps that route's window
/// chrome and back history, without mounting a second copy of the shell page.
class NowPlayingAudioDetailPage extends StatelessWidget {
  const NowPlayingAudioDetailPage({super.key, required this.audio});
  final Audio audio;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(56),
        child: TitleBarSurface(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              NavBackBtn(),
              Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              WindowControlls(),
            ]),
          ),
        ),
      ),
      body: AudioDetailPage(audio: audio));
}
