import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class FolderMoveRecovery extends StatefulWidget {
  const FolderMoveRecovery(
      {super.key, required this.error, required this.retry});
  final Object error;
  final Future<void> Function() retry;
  @override
  State<FolderMoveRecovery> createState() => _FolderMoveRecoveryState();
}

class _FolderMoveRecoveryState extends State<FolderMoveRecovery> {
  bool _busy = false;
  late Object _error = widget.error;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Scaffold(
        body: Center(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.drive_file_move_outline,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(ui('文件夹移动尚未完成'),
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      Text(ui(
                          '播放器尚未载入资料。已保留移动记录和仍未剪切的原文件，请连接相关磁盘、检查权限后重试；不会覆盖其他文件夹。')),
                      const SizedBox(height: 12),
                      SelectableText('$_error'),
                      const SizedBox(height: 20),
                      if (_busy)
                        const LinearProgressIndicator()
                      else
                        Wrap(spacing: 12, children: [
                          FilledButton(
                              onPressed: () async {
                                setState(() => _busy = true);
                                try {
                                  await widget.retry();
                                } catch (error) {
                                  if (mounted) {
                                    setState(() {
                                      _error = error;
                                      _busy = false;
                                    });
                                  }
                                }
                              },
                              child: Text(ui('重试并继续'))),
                          TextButton(
                              onPressed: windowManager.close,
                              child: Text(ui('退出'))),
                        ]),
                    ])))));
  }
}
