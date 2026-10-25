import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
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
    Future<bool> Function()? ensureTools,
    PlaylistFolderExportRunner runExport = runPlaylistFolderExport}) async {
  late final PlaylistFolderExportPlan plan;
  try {
    plan = snapshotPlaylistFolderExport(List<Audio>.of(audios));
  } catch (error) {
    _showError(context, error);
    return;
  }
  if (plan.availableEntryCount == 0) {
    showAppNotice(ui('所选歌曲中没有可导出的本地文件。'),
        context: context, kind: AppNoticeKind.warning);
    return;
  }
  final confirmed = await showAppDialog<PlaylistFolderExportPlan>(
      context: context,
      dialogBottomInset: 24,
      builder: (_) => PlaylistFolderExportConfirmation(
          plan: plan, ensureTools: ensureTools));
  if (confirmed == null || !context.mounted) return;
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
            plan: confirmed,
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
    ui(switch (error) {
      PlaylistFolderExportException() => error.message,
      FormatException() => error.message.toString(),
      _ => '导出失败，请检查目标目录与写入权限。',
    }),
    context: context,
    kind: AppNoticeKind.error);

class PlaylistFolderExportConfirmation extends StatefulWidget {
  const PlaylistFolderExportConfirmation(
      {super.key, required this.plan, this.ensureTools});
  final PlaylistFolderExportPlan plan;
  final Future<bool> Function()? ensureTools;

  @override
  State<PlaylistFolderExportConfirmation> createState() =>
      _PlaylistFolderExportConfirmationState();
}

class _PlaylistFolderExportConfirmationState
    extends State<PlaylistFolderExportConfirmation> {
  late PlaylistFolderExportOptions _options = widget.plan.options;
  late bool _toolsReady =
      widget.ensureTools == null && FfmpegRuntime.shared.ready;
  bool _checking = false;

  PlaylistFolderExportPlan get _plan => widget.plan.withOptions(_options);

  @override
  void initState() {
    super.initState();
    if (_options.convertsAudio && !_toolsReady) unawaited(_checkTools());
  }

  Future<void> _checkTools() async {
    if (_checking) return;
    setState(() => _checking = true);
    bool ready;
    try {
      ready = await (widget.ensureTools ?? FfmpegRuntime.shared.ensure)();
    } catch (_) {
      ready = false;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _toolsReady = ready;
    });
  }

  void _selectFormat(PlaylistFolderExportFormat value) {
    setState(() => _options =
        PlaylistFolderExportOptions(format: value, quality: _options.quality));
    if (_options.convertsAudio && !_toolsReady) unawaited(_checkTools());
  }

  String _formatLabel(PlaylistFolderExportFormat format) => switch (format) {
        PlaylistFolderExportFormat.original => ui('原样复制'),
        PlaylistFolderExportFormat.mp3 => 'MP3',
        PlaylistFolderExportFormat.opus => 'Opus',
        PlaylistFolderExportFormat.flac => 'FLAC',
      };

  String _qualityLabel(PlaylistFolderExportQuality quality) => ui(
          switch (quality) {
            PlaylistFolderExportQuality.compact => '体积优先 · {0} kbps',
            PlaylistFolderExportQuality.standard => '均衡 · {0} kbps',
            PlaylistFolderExportQuality.high => '高音质 · {0} kbps',
          },
          [
            PlaylistFolderExportOptions(
                    format: _options.format, quality: quality)
                .bitrateKbps!
          ]);

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final plan = _plan;
    final converting = _options.convertsAudio;
    final canConfirm =
        plan.entries.isNotEmpty && (!converting || (_toolsReady && !_checking));
    final style = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AppDialogContent(
        width: 508,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppDialogTitle(ui('导出音乐文件夹'), style: style.headlineSmall),
                    const SizedBox(height: 20),
                    Text(ui('输出格式'), style: style.titleSmall),
                    const SizedBox(height: 8),
                    AppSegmentedControl<PlaylistFolderExportFormat>(
                        key: const ValueKey('folder-export-format'),
                        value: _options.format,
                        wrapCompactLabel: true,
                        semanticLabel: ui('输出格式'),
                        options: [
                          for (final format
                              in PlaylistFolderExportFormat.values)
                            AppSegmentOption(
                                value: format,
                                key: ValueKey(
                                    'folder-export-format-${format.name}'),
                                label: _formatLabel(format),
                                icon: format ==
                                        PlaylistFolderExportFormat.original
                                    ? Icons.copy_outlined
                                    : Icons.audio_file_outlined),
                        ],
                        onChanged: _selectFormat),
                    if (_options.bitrateKbps != null) ...[
                      const SizedBox(height: 16),
                      Text(ui('转换质量'), style: style.titleSmall),
                      const SizedBox(height: 8),
                      AppSegmentedControl<PlaylistFolderExportQuality>(
                          key: const ValueKey('folder-export-quality'),
                          value: _options.quality,
                          wrapCompactLabel: true,
                          semanticLabel: ui('转换质量'),
                          options: [
                            for (final quality
                                in PlaylistFolderExportQuality.values)
                              AppSegmentOption(
                                  value: quality,
                                  key: ValueKey(
                                      'folder-export-quality-${quality.name}'),
                                  label: _qualityLabel(quality),
                                  icon: switch (quality) {
                                    PlaylistFolderExportQuality.compact =>
                                      Icons.storage_outlined,
                                    PlaylistFolderExportQuality.standard =>
                                      Icons.tune,
                                    PlaylistFolderExportQuality.high =>
                                      Icons.graphic_eq,
                                  }),
                          ],
                          onChanged: (quality) => setState(() => _options =
                              PlaylistFolderExportOptions(
                                  format: _options.format, quality: quality))),
                    ],
                    const SizedBox(height: 16),
                    Text(
                        ui(
                            converting
                                ? '将 {0} 首歌曲转换为 {1} 个 {2} 文件，其中 {3} 首为 CUE 分轨。'
                                : '将 {0} 首歌曲导出到新文件夹，复制 {1} 个音频文件。',
                            [
                              plan.entries.length,
                              plan.uniqueFileCount,
                              _formatLabel(_options.format),
                              plan.cueTrackCount
                            ]),
                        key: const ValueKey('folder-export-summary')),
                    if (!converting && plan.availableCueTrackCount > 0) ...[
                      const SizedBox(height: 12),
                      Text(ui('已选择 {0} 首 CUE 分轨；选择转换格式可导出为独立音频文件。',
                          [plan.availableCueTrackCount])),
                    ],
                    const SizedBox(height: 12),
                    Text(ui('保留歌曲顺序和重复项，生成相对路径 M3U8；原文件不变。')),
                    if (plan.skipped > 0) ...[
                      const SizedBox(height: 12),
                      Text(ui(
                          converting
                              ? '跳过 {0} 项联网歌曲或不支持的文件。'
                              : '跳过 {0} 项联网歌曲、CUE 分轨或不支持的文件。',
                          [plan.skipped])),
                    ],
                    const SizedBox(height: 12),
                    Text(ui(converting
                        ? '保留标题、艺术家、专辑等基本文字标签；不保留内嵌歌词、封面或侧车文件。'
                        : '原样复制完整音频文件，不改变编码和嵌入标签；不复制单独的歌词或封面文件。')),
                    if (converting) ...[
                      const SizedBox(height: 12),
                      Text(ui(switch (_options.format) {
                        PlaylistFolderExportFormat.mp3 =>
                          'MP3 输出为 44.1 kHz，单声道保留，其余转为双声道，便于车载和便携设备播放。',
                        PlaylistFolderExportFormat.opus =>
                          'Opus 输出为 48 kHz，单声道保留，其余转为双声道。请确认目标设备支持 Opus。',
                        _ => 'FLAC 保留采样率和声道，不会提升有损音源的音质。',
                      })),
                      if (_checking) ...[
                        const SizedBox(height: 16),
                        Text(ui('正在检查转换组件…'),
                            key:
                                const ValueKey('folder-export-checking-tools')),
                      ] else if (!_toolsReady) ...[
                        const SizedBox(height: 16),
                        FfmpegSetupCard(
                            key: const ValueKey('folder-export-setup'),
                            title: ui('安装音频转换组件'),
                            description: ui(
                                '转换复用 FFmpeg 组件。可以手动安装，或从 GitHub 下载约 70 MB 的组件；原样复制无需安装。'),
                            ensureTools: widget.ensureTools,
                            onReady: () => setState(() => _toolsReady = true)),
                      ],
                    ],
                  ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 4,
              children: [
                TextButton(
                    key: const ValueKey('folder-export-dismiss'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(ui('取消'))),
                FilledButton(
                    key: const ValueKey('folder-export-confirm'),
                    onPressed: canConfirm
                        ? () => Navigator.of(context).pop(plan)
                        : null,
                    child: Text(ui('选择保存文件夹'))),
              ],
            ),
          ),
        ]),
      ),
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
        final phaseChanged =
            value.preparing != (_progress?.preparing ?? true) ||
                value.converting != (_progress?.converting ?? false) ||
                value.currentTitle != _progress?.currentTitle;
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
                                    : progress?.converting == true
                                        ? '已转换 {0}/{1} 个文件'
                                        : '已复制 {0}/{1} 个文件',
                            [
                              progress?.copiedFiles ?? 0,
                              progress?.totalFiles ??
                                  widget.plan.uniqueFileCount
                            ])),
                        if (!_cancelling && progress?.currentTitle != null) ...[
                          const SizedBox(height: 8),
                          Text(progress!.currentTitle!,
                              key:
                                  const ValueKey('folder-export-current-title'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ],
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
