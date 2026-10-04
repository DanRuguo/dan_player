import 'dart:io';

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/data/folder_move_transaction.dart';
import 'package:dan_player/data/folder_explorer.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/music_folder_move.dart';
import 'package:dan_player/folder_note_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

class FolderActions extends StatelessWidget {
  const FolderActions(
      {super.key,
      required this.directory,
      required this.builder,
      this.isPlayerData = false,
      this.onBrowse,
      this.onMove,
      this.onStatistics,
      this.notes,
      this.saveNotes});
  final Directory directory;
  final bool isPlayerData;
  final Widget Function(BuildContext, MenuController) builder;
  final VoidCallback? onBrowse, onMove, onStatistics;
  final ValueNotifier<FolderNotePreferences>? notes;
  final Future<void> Function(FolderNotePreferences)? saveNotes;

  @override
  Widget build(BuildContext context) => AppMenuAnchor(
        menuChildren: [
          MenuItemButton(
              key: const ValueKey('folder-note-menu'),
              leadingIcon: const Icon(Symbols.edit_note),
              onPressed: () => _editNote(context),
              child: Text(ui('文件夹备注'))),
          MenuItemButton(
              leadingIcon: const Icon(Symbols.folder_open),
              onPressed: onBrowse ??
                  () async {
                    try {
                      await browseFolderInExplorer(directory);
                    } catch (_) {
                      if (!context.mounted) return;
                      showAppNotice(ui('无法打开此文件夹'),
                          context: context, kind: AppNoticeKind.error);
                    }
                  },
              child: Text(ui('在文件资源管理器浏览'))),
          MenuItemButton(
              leadingIcon: const Icon(Symbols.drive_file_move),
              onPressed: onMove ?? () => _chooseMove(context),
              child: Text(ui(isPlayerData ? '移动缓存文件夹' : '移动音乐文件夹'))),
          MenuItemButton(
              leadingIcon: const Icon(Symbols.monitoring),
              onPressed: onStatistics ??
                  () => context.push(Uri(
                          path: app_paths.STATISTICS_PAGE,
                          queryParameters: {
                            'section': isPlayerData ? 'cache' : 'folders',
                            if (!isPlayerData) 'folder': directory.path
                          }).toString()),
              child: Text(ui('查看占用统计'))),
        ],
        builder: (context, controller, _) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (event) =>
                controller.open(position: event.localPosition),
            onLongPressStart: (event) =>
                controller.open(position: event.localPosition),
            child: builder(context, controller)),
      );

  Future<void> _editNote(BuildContext context) async {
    final notifier = notes ?? AppSettings.instance.folderNotes;
    final text = await showAppDialog<String>(
        context: context,
        builder: (_) => FolderNoteDialog(
            folderPath: directory.path,
            initialText: notifier.value.noteFor(directory.path) ?? ''));
    if (text == null) return;
    final previous = notifier.value;
    final next = previous.withNote(directory.path, text);
    notifier.value = next;
    try {
      if (saveNotes case final save?) {
        await save(next);
      } else {
        await AppSettings.instance.saveSettings(
            throwOnError: true, captureWindowSize: false, requireCommit: true);
      }
    } catch (_) {
      if (identical(notifier.value, next)) notifier.value = previous;
      if (!context.mounted) return;
      showAppNotice(ui('无法保存文件夹备注'),
          context: context, kind: AppNoticeKind.error);
    }
  }

  Future<void> _chooseMove(BuildContext context) async {
    try {
      final parent = (DirectoryPicker()..title = ui('选择移入的文件夹（可新建文件夹）'))
          .getDirectory()
          ?.path;
      if (parent == null || !context.mounted) return;
      final destination = Directory(p.join(parent, p.basename(directory.path)));
      await FolderMoveTransaction.validate(directory, destination);
      if (!context.mounted) return;
      final confirmed = await showAppDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: Text(ui(isPlayerData ? '移动缓存文件夹' : '移动音乐文件夹')),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ui('从 {0}\n移至 {1}',
                            [directory.path, destination.path])),
                        const SizedBox(height: 12),
                        Text(ui(isPlayerData
                            ? '缓存与播放器资料一起移动，保留歌单、歌词、统计和设置。确认后退出，下次打开时先完成剪切和路径同步。'
                            : '整个文件夹及其子文件夹将剪切到新位置，歌单、歌词、书签和统计保持关联。确认后退出，下次打开时先完成移动和路径同步。')),
                        const SizedBox(height: 8),
                        Text(ui('不会覆盖已有文件夹；跨盘移动先校验文件，再删除原文件。')),
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: Text(ui('取消'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: Text(ui('确认移动并退出')))
                  ]));
      if (confirmed != true) return;
      await LibraryMutationGate.shared.run(() async {
        if (isPlayerData) {
          final data = await getAppDataDir();
          if (await MusicFolderMove(data).pending) {
            throw StateError('A music move is pending');
          }
          await scheduleAppDataDirectoryMove(destination);
        } else {
          await MusicFolderMove(await getAppDataDir())
              .schedule(directory, destination);
        }
      });
      try {
        await shutdownAndExit(throwOnError: true);
      } catch (_) {
        if (!context.mounted) return;
        showAppNotice(ui('移动已安排，请退出并重新打开播放器完成移动'),
            context: context, kind: AppNoticeKind.error);
      }
    } catch (_) {
      if (!context.mounted) return;
      showAppNotice(ui('无法移动：请检查目录权限，目标不得已存在、包含原目录或位于原目录内，且不能有其他待完成的迁移。'),
          context: context, kind: AppNoticeKind.error);
    }
  }
}

class FolderNoteDialog extends StatefulWidget {
  const FolderNoteDialog(
      {super.key, required this.folderPath, this.initialText = ''});
  final String folderPath, initialText;

  @override
  State<FolderNoteDialog> createState() => _FolderNoteDialogState();
}

class _FolderNoteDialogState extends State<FolderNoteDialog> {
  late final _text = TextEditingController(text: widget.initialText);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final valid = FolderNotePreferences.isValidText(_text.text);
    return AlertDialog(
        scrollable: true,
        title: AppDialogTitle(ui('编辑备注')),
        content: SizedBox(
            width: 440,
            child: AppDialogResize(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Tooltip(
                      message: widget.folderPath,
                      child: Text(widget.folderPath,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant))),
                  const SizedBox(height: 12),
                  Text(ui('只改变显示名称，不重命名文件夹。留空恢复原名。')),
                  const SizedBox(height: 16),
                  TextField(
                      key: const ValueKey('folder-note-input'),
                      controller: _text,
                      autofocus: true,
                      maxLines: 1,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (FolderNotePreferences.isValidText(_text.text)) {
                          Navigator.pop(context, _text.text);
                        }
                      },
                      decoration: InputDecoration(
                          labelText: ui('文件夹备注'),
                          border: AppShape.inputBorder,
                          counterText:
                              '${_text.text.runes.length}/${FolderNotePreferences.maxCodePoints}',
                          errorText: valid
                              ? null
                              : ui('最多 {0} 个字符，不允许控制字符',
                                  [FolderNotePreferences.maxCodePoints]))),
                ]))),
        actions: [
          TextButton(
              key: const ValueKey('folder-note-clear'),
              onPressed: () => setState(_text.clear),
              child: Text(ui('清除备注'))),
          TextButton(
              key: const ValueKey('folder-note-cancel'),
              onPressed: () => Navigator.pop(context),
              child: Text(ui('取消'))),
          FilledButton(
              key: const ValueKey('folder-note-save'),
              onPressed:
                  valid ? () => Navigator.pop(context, _text.text) : null,
              child: Text(ui('保存'))),
        ]);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }
}
