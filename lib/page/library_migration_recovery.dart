import 'package:dan_player/library/library_data_migration.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Shown before ordinary stores are opened: a half-installed batch must never
/// be accepted by the normal player and later saved over its recovery files.
class LibraryMigrationRecovery extends StatefulWidget {
  const LibraryMigrationRecovery(
      {super.key,
      required this.migration,
      required this.error,
      required this.resume,
      this.beforeRetry,
      this.allowRestore = true});
  final LibraryDataMigration migration;
  final Object error;
  final Future<void> Function() resume;
  final bool allowRestore;
  final Future<void> Function()? beforeRetry;
  @override
  State<LibraryMigrationRecovery> createState() =>
      _LibraryMigrationRecoveryState();
}

class _LibraryMigrationRecoveryState extends State<LibraryMigrationRecovery> {
  late String _error = '${widget.error}';
  bool _busy = false;
  Future<void> _run(bool restore) async {
    setState(() => _busy = true);
    try {
      if (restore) {
        await widget.migration.restorePrevious();
      } else {
        await widget.beforeRetry?.call();
        await widget.migration.recover();
      }
      await widget.resume();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.settings_backup_restore,
                        size: 44, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(ui('曲库迁移尚未完成'),
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(ui(
                        '播放器尚未载入曲库。迁移现场和同批快照已保留；请连接相关目录后重试。只有明确确认的文件夹移动会剪切文件，其他重定位操作只更新关联。')),
                    const SizedBox(height: 12),
                    SelectableText(_error),
                    const SizedBox(height: 20),
                    if (_busy)
                      const LinearProgressIndicator()
                    else
                      Wrap(spacing: 12, runSpacing: 8, children: [
                        FilledButton(
                            onPressed: () => _run(false),
                            child: Text(ui('重试并继续'))),
                        if (widget.allowRestore)
                          OutlinedButton(
                              onPressed: () async {
                                final answer = await showDialog<bool>(
                                    context: context,
                                    builder: (dialog) => AlertDialog(
                                            title: Text(ui('恢复迁移前的资料？')),
                                            content: Text(ui(
                                                '将成组恢复这一批次的全部资料；尚未开始的迁移则直接取消。')),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dialog, false),
                                                  child: Text(ui('取消'))),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dialog, true),
                                                  child: Text(ui('恢复')))
                                            ]));
                                if (answer == true && mounted) await _run(true);
                              },
                              child: Text(ui('恢复原资料'))),
                        TextButton(
                            onPressed: windowManager.close,
                            child: Text(ui('退出'))),
                      ]),
                  ])))));
}
