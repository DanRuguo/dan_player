import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:path/path.dart' as path;
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/page/settings_page/settings_busy_indicator.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_cache_batch.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LyricCacheBatchSettings extends StatefulWidget {
  const LyricCacheBatchSettings({super.key, this.task, this.folders});
  final LyricCacheBatch? task;
  final List<String>? folders;
  @override
  State<LyricCacheBatchSettings> createState() =>
      _LyricCacheBatchSettingsState();
}

class _LyricCacheBatchSettingsState extends State<LyricCacheBatchSettings> {
  String? _selected;
  LyricCacheBatch get _task => widget.task ?? LyricCacheBatch.instance;
  List<String> get _folders =>
      widget.folders ?? LyricCacheBatch.importedFolders;

  Future<void> _choose() async {
    final choices = _folders;
    String? pending = _selected ?? _task.folder;
    final selected = await showAppDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, selectFolder) {
              final theme = Theme.of(context);
              final colors = theme.colorScheme;
              return AlertDialog(
                insetPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                title: AppDialogTitle(ui('选择已导入的文件夹'),
                    leading: const Icon(Symbols.folder_open)),
                content: SizedBox(
                  width: 560,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .55),
                    child: choices.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(ui('请先将音乐文件夹导入乐库。'),
                                textAlign: TextAlign.center))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: choices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final folder = choices[index];
                              final selected = pending == folder;
                              final name = path.posix
                                  .basename(folder.replaceAll('\\', '/'));
                              return Material(
                                color: selected
                                    ? colors.secondaryContainer
                                    : colors.surfaceContainerLow,
                                shape: AppShape.control.copyWith(
                                    side: BorderSide(
                                        color: selected
                                            ? colors.primary
                                            : colors.outlineVariant
                                                .withValues(alpha: .45))),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () =>
                                      selectFolder(() => pending = folder),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(children: [
                                      Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                              color: colors.primary
                                                  .withValues(alpha: .10),
                                              borderRadius:
                                                  AppShape.smallRadius),
                                          child: Icon(Symbols.folder_open,
                                              size: 22, color: colors.primary)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                            Text(name.isEmpty ? folder : name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.titleSmall),
                                            const SizedBox(height: 4),
                                            Tooltip(
                                                message: folder,
                                                child: Text(folder,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: theme
                                                        .textTheme.bodySmall
                                                        ?.copyWith(
                                                            color: colors
                                                                .onSurfaceVariant))),
                                          ])),
                                      const SizedBox(width: 12),
                                      Icon(
                                          selected
                                              ? Symbols.check_circle
                                              : Symbols.radio_button_unchecked,
                                          size: 22,
                                          color: selected
                                              ? colors.primary
                                              : colors.onSurfaceVariant),
                                    ]),
                                  ),
                                ),
                              );
                            }),
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(ui('取消'))),
                  FilledButton.icon(
                      key: const ValueKey('lyric-batch-start'),
                      onPressed: pending != null && choices.contains(pending)
                          ? () => Navigator.pop(context, pending)
                          : null,
                      icon: const Icon(Symbols.download),
                      label: Text(ui('开始缓存'))),
                ],
              );
            }));
    if (mounted && selected != null && _folders.contains(selected)) {
      setState(() => _selected = selected);
      await _task.start(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: Listenable.merge([_task, AudioLibrary.changes]),
        builder: (context, _) {
          final task = _task;
          final selection = _selected ?? task.folder;
          return SettingsSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SettingsHeader(
                    title: ui('批量缓存歌词'),
                    icon: Symbols.download,
                    subtitle: ui(
                        '仅处理所选已导入文件夹及子文件夹中的入库歌曲；跳过已有歌词，只缓存匹配成功的结果，不修改音乐文件。')),
                const SizedBox(height: 12),
                if (selection != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(selection,
                          maxLines: 3, overflow: TextOverflow.ellipsis)),
                Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                          key: const ValueKey('lyric-batch-folder'),
                          onPressed: task.running ? null : _choose,
                          icon: const Icon(Symbols.folder_open),
                          label: Text(ui('选择已导入的文件夹'))),
                      if (task.running)
                        TextButton(
                            key: const ValueKey('lyric-batch-cancel'),
                            onPressed: task.cancelling ? null : task.cancel,
                            child: Text(ui('取消'))),
                    ]),
                const SizedBox(height: 12),
                Text(ui(task.status)),
                if (task.running) ...[
                  const SizedBox(height: 8),
                  SettingsBusyIndicator.linear(
                      progress: task.scanning || task.total == 0
                          ? null
                          : task.completed / task.total),
                  if (task.currentTitle.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(task.currentTitle,
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                if (task.total > 0)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(ui(
                          '已处理 {0}/{1} · 缓存 {2} · 跳过 {3} · 无匹配 {4} · 纯音乐 {5} · 失败 {6}',
                          [
                            task.completed,
                            task.total,
                            task.saved,
                            task.skipped,
                            task.unmatched,
                            task.instrumental,
                            task.failed
                          ]))),
              ]));
        });
  }
}
