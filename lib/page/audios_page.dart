import 'package:dan_player/app_preference.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/component/playing_audio_list_row.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class AudiosPage extends StatefulWidget {
  final Audio? locateTo;

  /// Optional test hook allowing isolated locate/highlight verification
  /// without initializing native playback.
  final ValueListenable<String?>? nowPlayingPath;

  const AudiosPage({super.key, this.locateTo, this.nowPlayingPath});

  @override
  State<AudiosPage> createState() => _AudiosPageState();
}

class _AudiosPageState extends State<AudiosPage> {
  final multiSelectController = MultiSelectController<Audio>();
  late Audio? _locateTarget = widget.locateTo;
  int _locateRequest = 0;

  @override
  void didUpdateWidget(covariant AudiosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locateTo != oldWidget.locateTo) {
      _locateTarget = widget.locateTo;
      if (widget.locateTo != null) _locateRequest++;
    }
  }

  @override
  void dispose() {
    multiSelectController.dispose();
    super.dispose();
  }

  Audio? _findMatchingAudio(List<Audio> contentList, String? playingPath) {
    if (playingPath == null || playingPath.isEmpty) return null;
    for (final audio in contentList) {
      if (audio.path == playingPath) return audio;
    }
    return null;
  }

  void _locateAudio(Audio target) {
    setState(() {
      _locateTarget = target;
      _locateRequest++;
    });
  }

  Widget _locateButton(BuildContext context, List<Audio> contentList) {
    Widget buildButton(String? playingPath) {
      final target = _findMatchingAudio(contentList, playingPath);
      return IconButton.outlined(
        key: const ValueKey('music-locate-current'),
        onPressed: target == null ? null : () => _locateAudio(target),
        style: appToolbarControlStyle(context, iconOnly: true),
        tooltip: ui('定位当前歌曲'),
        icon: const Icon(Symbols.my_location),
      );
    }

    final injected = widget.nowPlayingPath;
    if (injected != null) {
      return ValueListenableBuilder<String?>(
        valueListenable: injected,
        builder: (context, playingPath, _) => buildButton(playingPath),
      );
    }
    return PlaybackReadyBuilder(
      waitingBuilder: (_) => buildButton(null),
      readyBuilder: (_) {
        final playback = PlayService.instance.playbackService;
        return ListenableBuilder(
          listenable: playback,
          builder: (context, _) => buildButton(playback.nowPlaying?.path),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        OnlineLibrary.instance,
        AudioLibrary.changes,
      ]),
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final contentList = List<Audio>.from(AudioLibrary.instance.audioCollection);
    return UniPage<Audio>(
      pref: AppPreference.instance.audiosPagePref,
      title: ui("音乐"),
      subtitle: ui("{0} 首乐曲", [contentList.length]),
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) {
        final tile = AudioTile(
          audioIndex: i,
          playlist: contentList,
          focus: item == _locateTarget,
          multiSelectController: multiSelectController,
          columns: AudioColumnsScope.of(context),
        );
        return MusicGridScope.of(context)
            ? tile
            : PlayingAudioListRow(
                audioPath: item.path,
                nowPlayingPath: widget.nowPlayingPath,
                child: tile,
              );
      },
      primaryAction: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonal(
            key: const ValueKey('music-search-action'),
            onPressed: () => context.push(app_paths.SEARCH_PAGE),
            style: appToolbarControlStyle(context, primary: true, tonal: true),
            child: AppToolbarLabel(label: ui("搜索"), icon: Symbols.search),
          ),
          _locateButton(context, contentList),
        ],
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      enableAudioColumns: true,
      locateTo: _locateTarget,
      locateRequest: _locateRequest,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        AudioMultiSelectionActions(
          controller: multiSelectController,
          contentList: contentList,
        ),
      ],
      sortMethods: audioSortMethods(
        AudioSortProfile.library,
        custom: SortMethodDesc<Audio>(
          icon: Symbols.drag_handle,
          name: ui("自定义"),
          usesSortOrder: false,
          supportsReorder: true,
          method: (list, order) => customAudioOrder.applyTo(list),
          onReorder: (list) => customAudioOrder.setFromAudios(list),
        ),
      ),
    );
  }
}
