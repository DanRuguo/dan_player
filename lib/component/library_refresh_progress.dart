import 'dart:async';

import 'package:dan_player/library/library_refresh.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Reattaches to the task without owning or cancelling its native stream.
class LibraryRefreshProgress extends StatefulWidget {
  const LibraryRefreshProgress(
      {super.key, required this.task, this.onSettled, this.onBackground});
  final LibraryRefreshTask task;
  final ValueChanged<LibraryRefreshTask>? onSettled;
  final VoidCallback? onBackground;

  @override
  State<LibraryRefreshProgress> createState() => _LibraryRefreshProgressState();
}

class _LibraryRefreshProgressState extends State<LibraryRefreshProgress> {
  @override
  void initState() {
    super.initState();
    widget.task.addListener(_changed);
    widget.task.start();
    unawaited(widget.task.completed.then((_) {
      if (mounted) widget.onSettled?.call(widget.task);
    }));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.task.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final task = widget.task;
    final title = switch (task.phase) {
      LibraryRefreshPhase.scanning => ui('正在扫描曲库'),
      LibraryRefreshPhase.cancelling => ui('正在取消扫描'),
      LibraryRefreshPhase.committing => ui('正在提交曲库'),
      LibraryRefreshPhase.cancelled => ui('扫描已取消'),
      LibraryRefreshPhase.completed => ui('曲库刷新完成'),
      LibraryRefreshPhase.failed => ui('曲库刷新失败'),
    };
    final description = switch (task.phase) {
      LibraryRefreshPhase.scanning => ui('可取消扫描；关闭此窗口后继续在后台处理。'),
      LibraryRefreshPhase.cancelling => ui('正在等待当前读取安全结束，原曲库仍保留。'),
      LibraryRefreshPhase.committing => ui('正在保存完整索引并同步曲库，此阶段不能取消。'),
      LibraryRefreshPhase.cancelled => ui('原曲库未改变，可随时重新扫描。'),
      LibraryRefreshPhase.completed => task.pendingMetadata > 0
          ? ui('{0} 首歌曲保留原信息，下次刷新会重试。', [task.pendingMetadata])
          : ui('音乐库已刷新'),
      LibraryRefreshPhase.failed => ui('未完成的刷新已结束，请查看提示后重试。'),
    };
    final progress = task.lastAction?.progress;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              key: const ValueKey('library-refresh-phase'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          if (!task.isTerminal) ...[
            LinearProgressIndicator(
                value: task.phase == LibraryRefreshPhase.scanning &&
                        progress != null &&
                        progress < 1
                    ? progress.clamp(0, 1)
                    : null,
                borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 16),
          ],
          Text(description, textAlign: TextAlign.center),
          if (!task.isTerminal) ...[
            const SizedBox(height: 20),
            Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (task.cancelNative != null)
                    OutlinedButton.icon(
                        key: const ValueKey('library-cancel-scan'),
                        onPressed: task.canCancel ? task.requestCancel : null,
                        icon: const Icon(Symbols.stop_circle),
                        label: Text(ui('取消扫描'))),
                  if (widget.onBackground != null)
                    TextButton.icon(
                        onPressed: widget.onBackground,
                        icon: const Icon(Symbols.close),
                        label: Text(ui('转入后台'))),
                ]),
          ],
        ]);
  }
}
