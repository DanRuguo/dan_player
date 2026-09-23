import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
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
    final selected = await showAppDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: AppDialogTitle(ui('选择已导入的文件夹'),
                  leading: const Icon(Symbols.folder)),
              content: SizedBox(
                  width: 560,
                  height: 320,
                  child: choices.isEmpty
                      ? Center(child: Text(ui('请先将音乐文件夹导入乐库。')))
                      : ListView.builder(
                          itemCount: choices.length,
                          itemBuilder: (context, index) => ListTile(
                            leading: const Icon(Symbols.folder),
                            title: Text(choices[index],
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            selected: _selected == choices[index],
                            onTap: () => Navigator.pop(context, choices[index]),
                          ),
                        )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ui('取消')))
              ],
            ));
    if (mounted && selected != null) setState(() => _selected = selected);
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
                            child: Text(ui('取消')))
                      else
                        FilledButton.icon(
                            key: const ValueKey('lyric-batch-start'),
                            onPressed: selection != null &&
                                    _folders.contains(selection)
                                ? () => task.start(selection)
                                : null,
                            icon: const Icon(Symbols.download),
                            label: Text(ui('开始缓存'))),
                    ]),
                const SizedBox(height: 12),
                Text(ui(task.status)),
                if (task.running) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value: task.scanning || task.total == 0
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
