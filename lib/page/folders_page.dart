import 'package:dan_player/app_preference.dart';
import 'dart:math' as math;
import 'package:dan_player/component/music_grid.dart';
import 'package:dan_player/library/audio_folder_sort.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/page/uni_page.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path;

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:desktop_lyric/ui_language.dart';

class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final contentList = List<AudioFolder>.from(AudioLibrary.instance.folders);
    return UniPage<AudioFolder>(
      pref: AppPreference.instance.foldersPagePref,
      title: ui("文件夹"),
      subtitle: ui("{0} 个文件夹", [contentList.length]),
      contentList: contentList,
      contentBuilder: (context, item, i, multiSelectController) =>
          AudioFolderTile(audioFolder: item),
      enableShufflePlay: false,
      enableSortMethod: true,
      enableSortOrder: true,
      enableContentViewSwitch: true,
      listItemExtent: folderTileExtent(context),
      gridDelegate: CompactMusicGridDelegate(
          mainAxisExtent: folderTileExtent(context), minimumTileWidth: 320),
      sortMethods: [
        SortMethodDesc(
          icon: Symbols.title,
          name: ui("路径"),
          method: (list, order) => sortAudioFoldersInPlace(
            list,
            AudioFolderSortField.path,
            direction: order == SortOrder.ascending
                ? SortDirection.ascending
                : SortDirection.descending,
          ),
        ),
        SortMethodDesc(
          icon: Symbols.edit,
          name: ui("修改日期"),
          method: (list, order) => sortAudioFoldersInPlace(
            list,
            AudioFolderSortField.modified,
            direction: order == SortOrder.ascending
                ? SortDirection.ascending
                : SortDirection.descending,
          ),
        ),
        SortMethodDesc(
          icon: Symbols.music_note,
          name: ui("歌曲数量"),
          method: (list, order) => sortAudioFoldersInPlace(
            list,
            AudioFolderSortField.songCount,
            direction: order == SortOrder.ascending
                ? SortDirection.ascending
                : SortDirection.descending,
          ),
        ),
      ],
    );
  }
}

String folderDisplayName(String value) {
  if (value.trim().isEmpty) return ui("未命名文件夹");
  final normalized = path.windows.normalize(value);
  final name = path.windows.basename(normalized);
  return name.isEmpty ? normalized : name;
}

double folderTileExtent(BuildContext context) =>
    math.max(88, musicGridLineHeight(context) * 3 + 24);

class AudioFolderTile extends StatelessWidget {
  final AudioFolder audioFolder;
  const AudioFolderTile({
    super.key,
    required this.audioFolder,
  });

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final normalized = path.windows.normalize(audioFolder.path);
    final parent = path.windows.dirname(normalized);
    final hierarchy =
        parent == '.' ? ui("本地音乐") : parent.replaceAll('\\', ' › ');
    final modified = audioFolder.modified > 0
        ? DateTime.fromMillisecondsSinceEpoch(audioFolder.modified * 1000)
            .toIso8601String()
            .substring(0, 10)
        : ui("未知日期");
    final summary =
        ui("{0} 首歌曲 · 修改于 {1}", [audioFolder.audios.length, modified]);
    return Tooltip(
      message: audioFolder.path,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
              borderRadius: AppShape.controlRadius,
              side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: .6))),
          child: InkWell(
            key: ValueKey('folder-open-${audioFolder.path}'),
            borderRadius: AppShape.controlRadius,
            onTap: () => context.push(
              app_paths.FOLDER_DETAIL_PAGE,
              extra: audioFolder,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: AppShape.smallRadius),
                    child: Icon(Symbols.folder_open,
                        color: scheme.onPrimaryContainer)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(folderDisplayName(audioFolder.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface)),
                      Text(hierarchy,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.25,
                              color: scheme.onSurfaceVariant)),
                      Tooltip(
                          message: summary,
                          child: Text(summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.25,
                                  color: scheme.primary))),
                    ])),
                const SizedBox(width: 8),
                Icon(Symbols.chevron_right,
                    size: 20, color: scheme.onSurfaceVariant),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
