import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/audio_tile.dart';
import 'package:dan_player/component/audio_columns.dart';
import 'package:dan_player/page/audio_sort_methods.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:dan_player/page/uni_page_components.dart';
import 'package:dan_player/page/folders_page.dart' show folderDisplayName;
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:path/path.dart' as path_util;

class FolderDetailPage extends StatelessWidget {
  final AudioFolder folder;
  const FolderDetailPage({super.key, required this.folder});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<int>(
      valueListenable: AudioLibrary.changes,
      builder: (context, _, __) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final current = AudioLibrary.instance.folders.where(
      (candidate) => path_util.equals(candidate.path, folder.path),
    );
    final resolved = current.isEmpty ? folder : current.first;
    final contentList = List<Audio>.from(resolved.audios);
    final multiSelectController = MultiSelectController<Audio>();
    return UniPage<Audio>(
      pref: AppPreference.instance.folderDetailPagePref,
      title: folderDisplayName(resolved.path),
      subtitle: ui("{0} 首乐曲 · {1}", [contentList.length, resolved.path]),
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) => AudioTile(
        audioIndex: i,
        playlist: contentList,
        multiSelectController: multiSelectController,
        columns: AudioColumnsScope.of(context),
      ),
      enableShufflePlay: true,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      enableAudioColumns: true,
      multiSelectController: multiSelectController,
      multiSelectViewActions: [
        MultiSelectSelectOrClearAll(
          multiSelectController: multiSelectController,
          contentList: contentList,
        ),
        MultiSelectExit(multiSelectController: multiSelectController),
      ],
      sortMethods: audioSortMethods(AudioSortProfile.folder),
    );
  }
}
