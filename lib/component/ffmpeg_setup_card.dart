import 'dart:io';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/ffmpeg_module_install.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FfmpegSetupCard extends StatefulWidget {
  const FfmpegSetupCard({
    super.key,
    required this.onReady,
    this.lyricPreview = false,
    this.title,
    this.description,
    this.ensureTools,
    this.runtime,
    this.installerFactory,
  });

  final String? title, description;
  final Future<bool> Function()? ensureTools;
  final FfmpegRuntime? runtime;
  final FfmpegModuleInstaller Function()? installerFactory;
  final bool lyricPreview;
  final VoidCallback onReady;

  @override
  State<FfmpegSetupCard> createState() => _FfmpegSetupCardState();
}

class _FfmpegSetupCardState extends State<FfmpegSetupCard>
    with WidgetsBindingObserver {
  FfmpegModuleInstaller? _installer;
  late Future<String> _installDirFuture;
  bool _busy = false, _failed = false;
  double? _progress;

  FfmpegRuntime get _runtime => widget.runtime ?? FfmpegRuntime.shared;

  @override
  void initState() {
    super.initState();
    _installDirFuture = _runtime.installDirectory.then((dir) => dir.path);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant FfmpegSetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.runtime, widget.runtime)) {
      _installDirFuture = _runtime.installDirectory.then((dir) => dir.path);
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  Future<void> _run(bool download) async {
    setState(() {
      _busy = true;
      _failed = false;
      _progress = download ? 0 : null;
    });
    try {
      if (download) {
        _installer =
            widget.installerFactory?.call() ?? FfmpegModuleInstaller();
        await _installer!.install(
          runtime: _runtime,
          progress: (value) {
            if (mounted) setState(() => _progress = value);
          },
        );
      }
      if (!await (widget.ensureTools ??
          () => _runtime.ensure(force: true))()) {
        throw const FfmpegUnavailable();
      }
      if (mounted) widget.onReady();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _installer = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _installer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = appToolbarReduceMotion(context);
    final fallbackManual =
        p.join(p.dirname(Platform.resolvedExecutable), 'tool', 'ffmpeg');
    return SettingsSurface(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
          SettingsHeader(
            title:
                widget.title ?? ui(widget.lyricPreview ? '安装试听组件' : '安装裁剪组件'),
            icon: Icons.handyman_outlined,
          ),
          const SizedBox(height: 10),
          Text(widget.description ??
              ui(widget.lyricPreview
                  ? '试听复用精简版 FFmpeg 音频组件，不会改写原歌曲。可自动从 GitHub 下载约 5.2 MB 组件到 tool 目录并复检，或手动安装。'
                  : '音频裁剪需要 FFmpeg、FFprobe 和 FFplay。可从 GitHub 下载约 5.2 MB 的精简音频组件到 tool 目录并自动复检，将遵循播放器的网络代理设置。')),
          const SizedBox(height: 10),
          Text(ui(
              '也可以从发布页或官网下载组件，将可执行文件及配套 DLL 解压到以下目录，然后点击“我已安装好”。')),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: _installDirFuture,
            builder: (context, snapshot) {
              final pathText = snapshot.data ?? fallbackManual;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .46),
                  borderRadius: AppShape.controlRadius,
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .42)),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: SelectableText(
                    pathText,
                    key: const ValueKey('ffmpeg-install-directory'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'Consolas',
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              );
            },
          ),
          if (_busy) ...[
            const SizedBox(height: 14),
            Semantics(
                label: ui(_progress == null ? '正在复检并安装组件…' : '正在下载…'),
                liveRegion: true,
                child: TickerMode(
                    enabled: !reduceMotion,
                    child: ExcludeSemantics(
                        excluding: _progress == null,
                        child: LinearProgressIndicator(
                            value: _progress ?? (reduceMotion ? 0 : null))))),
            const SizedBox(height: 6),
            Text(_progress == null
                ? ui('正在复检并安装组件…')
                : '${ui('正在下载…')} ${(_progress! * 100).round()}%'),
          ],
          if (_failed) ...[
            const SizedBox(height: 12),
            Text(ui('组件仍不可用。请检查网络、工具是否完整及目录权限，或手动安装后重试。'),
                style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 14),
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_installer != null)
                  TextButton(
                      onPressed: _installer!.cancel, child: Text(ui('取消下载'))),
                OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(false),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(ui('我已安装好'))),
                FilledButton.icon(
                    onPressed: _busy ? null : () => _run(true),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(ui('从 GitHub 下载'))),
              ]),
        ]));
  }
}
