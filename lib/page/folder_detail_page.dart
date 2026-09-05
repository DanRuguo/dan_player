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

class FolderDetailPage extends StatefulWidget {
  final AudioFolder folder;
  const FolderDetailPage({super.key, required this.folder});

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  final multiSelectController = MultiSelectController<Audio>();

  @override
  void didUpdateWidget(FolderDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!path_util.equals(oldWidget.folder.path, widget.folder.path)) {
      multiSelectController.selected.clear();
      multiSelectController.enableMultiSelectView = false;
    }
  }

  @override
  void dispose() {
    multiSelectController.dispose();
    super.dispose();
  }

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
      (candidate) => path_util.equals(candidate.path, widget.folder.path),
    );
    final resolved = current.isEmpty ? widget.folder : current.first;
    final contentList = List<Audio>.from(resolved.audios);
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
        AudioMultiSelectionActions(
          controller: multiSelectController,
          contentList: contentList,
        ),
      ],
      sortMethods: audioSortMethods(AudioSortProfile.folder),
    );
  }
}
