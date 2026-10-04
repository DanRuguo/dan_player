import 'package:dan_player/app_preference.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/folder_actions.dart';
import 'package:dan_player/component/anchored_menu_action.dart';
import 'package:dan_player/folder_note_preferences.dart';
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

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key, this.dataDirectory});
  final Directory? dataDirectory;
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  late final Future<Directory> _data = widget.dataDirectory == null
      ? getAppDataDir()
      : Future.value(widget.dataDirectory);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return FutureBuilder<Directory>(
        future: _data,
        builder: (context, data) => ListenableBuilder(
            listenable: AudioLibrary.changes,
            builder: (context, _) {
              final cache = data.data == null
                  ? null
                  : AudioFolder([], data.data!.path, 0, 0);
              final contentList = [
                ...AudioLibrary.instance.folders,
                if (cache != null) cache
              ];
              void sort(List<AudioFolder> list, AudioFolderSortField field,
                  SortOrder order) {
                list.remove(cache);
                sortAudioFoldersInPlace(list, field,
                    direction: order == SortOrder.ascending
                        ? SortDirection.ascending
                        : SortDirection.descending);
                if (cache != null) list.add(cache);
              }

              return UniPage<AudioFolder>(
                pref: AppPreference.instance.foldersPagePref,
                title: ui("文件夹"),
                subtitle:
                    ui("{0} 个文件夹", [AudioLibrary.instance.folders.length]),
                contentList: contentList,
                contentBuilder: (context, item, i, multiSelectController) =>
                    identical(item, cache)
                        ? PlayerDataFolderTile(directory: data.data!)
                        : AudioFolderTile(audioFolder: item),
                enableShufflePlay: false,
                enableSortMethod: true,
                enableSortOrder: true,
                enableContentViewSwitch: true,
                listItemExtent: folderTileExtent(context),
                gridDelegate: CompactMusicGridDelegate(
                    mainAxisExtent: folderTileExtent(context),
                    minimumTileWidth: 320),
                sortMethods: [
                  SortMethodDesc(
                    icon: Symbols.title,
                    name: ui("路径"),
                    method: (list, order) =>
                        sort(list, AudioFolderSortField.path, order),
                  ),
                  SortMethodDesc(
                    icon: Symbols.edit,
                    name: ui("修改日期"),
                    method: (list, order) =>
                        sort(list, AudioFolderSortField.modified, order),
                  ),
                  SortMethodDesc(
                    icon: Symbols.music_note,
                    name: ui("歌曲数量"),
                    method: (list, order) =>
                        sort(list, AudioFolderSortField.songCount, order),
                  ),
                ],
              );
            }));
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
    this.notes,
    this.saveNotes,
  });
  final ValueNotifier<FolderNotePreferences>? notes;
  final Future<void> Function(FolderNotePreferences)? saveNotes;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final normalized = path.windows.normalize(audioFolder.path);
    final modified = audioFolder.modified > 0
        ? DateTime.fromMillisecondsSinceEpoch(audioFolder.modified * 1000)
            .toIso8601String()
            .substring(0, 10)
        : ui("未知日期");
    final summary =
        ui("{0} 首歌曲 · 修改于 {1}", [audioFolder.audios.length, modified]);
    return ValueListenableBuilder<FolderNotePreferences>(
        valueListenable: notes ?? AppSettings.instance.folderNotes,
        builder: (context, preferences, _) => FolderActions(
            directory: Directory(audioFolder.path),
            notes: notes,
            saveNotes: saveNotes,
            builder: (context, menu) => Tooltip(
                  triggerMode: TooltipTriggerMode.manual,
                  message: audioFolder.path,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                      color: scheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                          borderRadius: AppShape.controlRadius,
                          side: BorderSide(
                              color:
                                  scheme.outlineVariant.withValues(alpha: .6))),
                      child: InkWell(
                        key: ValueKey('folder-open-${audioFolder.path}'),
                        borderRadius: AppShape.controlRadius,
                        onTap: () => context.push(
                          app_paths.FOLDER_DETAIL_PAGE,
                          extra: audioFolder,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      preferences.noteFor(audioFolder.path) ??
                                          folderDisplayName(audioFolder.path),
                                      key: ValueKey(
                                          'folder-name-${audioFolder.path}'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 16,
                                          height: 1.25,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.onSurface)),
                                  Text(normalized,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 14,
                                          height: 1.25,
                                          color: scheme.onSurfaceVariant)),
                                  Tooltip(
                                      triggerMode: TooltipTriggerMode.manual,
                                      message: '${ui('音乐文件夹')} · $summary',
                                      child: Text('${ui('音乐文件夹')} · $summary',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14,
                                              height: 1.25,
                                              color: scheme.primary))),
                                ])),
                            const SizedBox(width: 8),
                            Builder(
                                builder: (actionContext) => IconButton(
                                    tooltip: ui('更多'),
                                    onPressed: () => toggleMenuAtAction(
                                        menu, context, actionContext),
                                    icon: Icon(Symbols.more_horiz,
                                        size: 20,
                                        color: scheme.onSurfaceVariant))),
                          ]),
                        ),
                      ),
                    ),
                  ),
                )));
  }
}

class PlayerDataFolderTile extends StatelessWidget {
  const PlayerDataFolderTile(
      {super.key, required this.directory, this.notes, this.saveNotes});
  final Directory directory;
  final ValueNotifier<FolderNotePreferences>? notes;
  final Future<void> Function(FolderNotePreferences)? saveNotes;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<FolderNotePreferences>(
        valueListenable: notes ?? AppSettings.instance.folderNotes,
        builder: (context, preferences, _) => FolderActions(
            directory: directory,
            isPlayerData: true,
            notes: notes,
            saveNotes: saveNotes,
            builder: (context, menu) => Tooltip(
                triggerMode: TooltipTriggerMode.manual,
                message: directory.path,
                child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Material(
                        color: scheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                            borderRadius: AppShape.controlRadius,
                            side: BorderSide(
                                color: scheme.outlineVariant
                                    .withValues(alpha: .6))),
                        child: InkWell(
                            borderRadius: AppShape.controlRadius,
                            onTap: menu.open,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                          color: scheme.primaryContainer,
                                          borderRadius: AppShape.smallRadius),
                                      child: Icon(Symbols.database,
                                          color: scheme.onPrimaryContainer)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(
                                            preferences
                                                    .noteFor(directory.path) ??
                                                folderDisplayName(
                                                    directory.path),
                                            key: ValueKey(
                                                'folder-name-${directory.path}'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 16,
                                                height: 1.25,
                                                fontWeight: FontWeight.w600,
                                                color: scheme.onSurface)),
                                        Tooltip(
                                            triggerMode:
                                                TooltipTriggerMode.manual,
                                            message: directory.path,
                                            child: Text(directory.path,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.25,
                                                    color: scheme
                                                        .onSurfaceVariant))),
                                        Text(ui('缓存文件夹'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                height: 1.25,
                                                color: scheme.primary)),
                                      ])),
                                  Builder(
                                      builder: (actionContext) => IconButton(
                                          tooltip: ui('更多'),
                                          onPressed: () => toggleMenuAtAction(
                                              menu, context, actionContext),
                                          icon:
                                              const Icon(Symbols.more_horiz))),
                                ]))))))));
  }
}
