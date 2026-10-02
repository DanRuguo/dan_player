import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist_folder_export.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

typedef PlaylistFolderExportRunner
    = Future<PlaylistFolderExportResult> Function(
        PlaylistFolderExportPlan plan, Directory parent,
        {String name,
        required PlaylistFolderExportCancellation cancellation,
        void Function(PlaylistFolderExportProgress)? onProgress});

/// Freeze file references and metadata before any dialog or native picker.
Future<void> exportMusicFolder(BuildContext context, List<Audio> audios,
    {String name = 'Dan Player',
    FutureOr<String?> Function()? pickDirectory,
    PlaylistFolderExportRunner runExport = runPlaylistFolderExport}) async {
  late final PlaylistFolderExportPlan plan;
  try {
    plan = snapshotPlaylistFolderExport(List<Audio>.of(audios));
  } catch (error) {
    _showError(context, error);
    return;
  }
  if (plan.entries.isEmpty) {
    showAppNotice(ui('所选歌曲中没有可导出的本地文件。'),
        context: context, kind: AppNoticeKind.warning);
    return;
  }
  final confirmed = await showAppDialog<bool>(
      context: context,
      dialogBottomInset: 24,
      builder: (_) => PlaylistFolderExportConfirmation(plan: plan));
  if (confirmed != true || !context.mounted) return;
  try {
    final location = pickDirectory == null
        ? (DirectoryPicker()..title = ui('选择保存文件夹')).getDirectory()?.path
        : await pickDirectory();
    if (location == null || !context.mounted) return;
    final outcome = await showAppDialog<_FolderExportOutcome>(
        context: context,
        barrierDismissible: false,
        dialogBottomInset: 24,
        builder: (_) => PlaylistFolderExportProgressDialog(
            plan: plan,
            parent: Directory(location),
            name: name,
            runExport: runExport));
    if (!context.mounted || outcome == null) return;
    if (outcome.error != null) {
      _showError(context, outcome.error!);
    } else if (outcome.result case final result?) {
      showAppNotice(
          '${ui('音乐文件夹已导出（{0} 首，{1} 个文件）。', [
                result.entryCount,
                result.copiedFiles
              ])}\n${result.directory.path}',
          context: context,
          kind: AppNoticeKind.success,
          duration: const Duration(seconds: 8));
    }
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

void _showError(BuildContext context, Object error) => showAppNotice(
    ui(error is FormatException
        ? error.message.toString()
        : '导出失败，请检查目标目录与写入权限。'),
    context: context,
    kind: AppNoticeKind.error);

class PlaylistFolderExportConfirmation extends StatelessWidget {
  const PlaylistFolderExportConfirmation({super.key, required this.plan});
  final PlaylistFolderExportPlan plan;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      scrollable: true,
      title: AppDialogTitle(ui('导出音乐文件夹')),
      content: SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ui('将 {0} 首歌曲导出到新文件夹，复制 {1} 个音频文件。',
                    [plan.entries.length, plan.uniqueFileCount])),
                const SizedBox(height: 12),
                Text(ui('保留歌曲顺序和重复项，生成相对路径 M3U8；原文件不变。')),
                if (plan.skipped > 0) ...[
                  const SizedBox(height: 12),
                  Text(ui('跳过 {0} 项联网歌曲、CUE 分轨或不支持的文件。', [plan.skipped])),
                ],
                const SizedBox(height: 12),
                Text(ui('不转换音频，也不复制歌词或封面侧车文件。')),
              ])),
      actions: [
        TextButton(
            key: const ValueKey('folder-export-dismiss'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(ui('取消'))),
        FilledButton(
            key: const ValueKey('folder-export-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ui('选择保存文件夹'))),
      ],
    );
  }
}

class _FolderExportOutcome {
  const _FolderExportOutcome({this.result, this.error});
  final PlaylistFolderExportResult? result;
  final Object? error;
}

class PlaylistFolderExportProgressDialog extends StatefulWidget {
  const PlaylistFolderExportProgressDialog(
      {super.key,
      required this.plan,
      required this.parent,
      required this.name,
      this.runExport = runPlaylistFolderExport});
  final PlaylistFolderExportPlan plan;
  final Directory parent;
  final String name;
  final PlaylistFolderExportRunner runExport;

  @override
  State<PlaylistFolderExportProgressDialog> createState() =>
      _PlaylistFolderExportProgressDialogState();
}

class _PlaylistFolderExportProgressDialogState
    extends State<PlaylistFolderExportProgressDialog>
    with WidgetsBindingObserver {
  final _cancellation = PlaylistFolderExportCancellation();
  PlaylistFolderExportProgress? _progress;
  bool _cancelling = false;
  final _progressClock = Stopwatch()..start();
  int _lastProgressMilliseconds = -100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  Future<void> _run() async {
    final task = TaskbarProgress.instance.begin();
    _FolderExportOutcome? outcome;
    try {
      final result = await widget.runExport(widget.plan, widget.parent,
          name: widget.name, cancellation: _cancellation, onProgress: (value) {
        if (!mounted) return;
        final now = _progressClock.elapsedMilliseconds;
        final phaseChanged = value.preparing != (_progress?.preparing ?? true);
        if (!phaseChanged &&
            value.fraction != 1 &&
            now - _lastProgressMilliseconds < 100) {
          return;
        }
        _lastProgressMilliseconds = now;
        task.update(value.fraction);
        setState(() => _progress = value);
      });
      outcome = _FolderExportOutcome(result: result);
    } on PlaylistFolderExportCancelled {
      // Keep the modal open until the worker has removed its temporary files.
    } catch (error) {
      outcome = _FolderExportOutcome(error: error);
    } finally {
      task.dispose();
      if (mounted) Navigator.of(context).pop(outcome);
    }
  }

  void _cancel() {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    _cancellation.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancellation.cancel();
    _progressClock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final progress = _progress;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final animate = AppMotion.enabled(context, MotionKind.feedback) &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    final indicator = LinearProgressIndicator(
        key: const ValueKey('folder-export-progress'),
        value: progress?.fraction ?? (animate ? null : 0));
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _cancel();
        },
        child: AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          scrollable: true,
          title: AppDialogTitle(ui('正在导出音乐文件夹')),
          content: AppDialogResize(
              child: SizedBox(
                  width: 400,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name),
                        const SizedBox(height: 16),
                        TickerMode(
                            enabled: animate,
                            child: progress?.fraction == null && !animate
                                ? Semantics(
                                    key: const ValueKey(
                                        'folder-export-static-progress'),
                                    container: true,
                                    label:
                                        ui(_cancelling ? '正在取消…' : '正在准备音频文件…'),
                                    child: ExcludeSemantics(child: indicator))
                                : indicator),
                        const SizedBox(height: 12),
                        Text(ui(
                            _cancelling
                                ? '正在取消…'
                                : progress?.fraction == null
                                    ? '正在准备音频文件…'
                                    : '已复制 {0}/{1} 个文件',
                            [
                              progress?.copiedFiles ?? 0,
                              progress?.totalFiles ??
                                  widget.plan.uniqueFileCount
                            ])),
                      ]))),
          actions: [
            TextButton(
                key: const ValueKey('folder-export-cancel'),
                onPressed: _cancelling ? null : _cancel,
                child: Text(ui('取消'))),
          ],
        ));
  }
}
