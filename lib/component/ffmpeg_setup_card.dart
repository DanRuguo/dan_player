import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/library/ffmpeg_module_install.dart';
import 'package:path/path.dart' as p;

class FfmpegSetupCard extends StatefulWidget {
  const FfmpegSetupCard(
      {super.key, required this.onReady, this.lyricPreview = false});
  final bool lyricPreview;
  final VoidCallback onReady;
  @override
  State<FfmpegSetupCard> createState() => _FfmpegSetupCardState();
}

class _FfmpegSetupCardState extends State<FfmpegSetupCard> {
  FfmpegModuleInstaller? _installer;
  bool _busy = false, _failed = false;
  double? _progress;
  Future<void> _run(bool download) async {
    setState(() {
      _busy = true;
      _failed = false;
      _progress = download ? 0 : null;
    });
    try {
      if (download) {
        _installer = FfmpegModuleInstaller();
        await _installer!.install(progress: (value) {
          if (mounted) setState(() => _progress = value);
        });
      } else if (!await FfmpegRuntime.shared.ensure(force: true)) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final manual =
        p.join(p.dirname(Platform.resolvedExecutable), 'tool', 'ffmpeg');
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: AppShape.controlRadius,
            border: Border.all(color: scheme.outlineVariant)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(ui(widget.lyricPreview ? '安装试听组件' : '安装裁剪组件'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text(ui(widget.lyricPreview
              ? '试听复用 FFmpeg 组件，不会改写歌曲。可以手动安装，或从 GitHub 下载约 70 MB 的组件。'
              : '裁剪需要 FFmpeg、FFprobe 和 FFplay。未找到可用的完整工具。可从 GitHub 下载约 70 MB 的组件，将使用 Windows 系统代理。')),
          const SizedBox(height: 10),
          Text(ui(
              '也可以从官网下载 Windows 完整编译包，将 bin 目录中的程序及 DLL 放到以下目录，然后点击“我已安装好”。')),
          const SizedBox(height: 6),
          const SelectableText('https://ffmpeg.org/download.html'),
          const SizedBox(height: 6),
          SelectableText(manual, style: Theme.of(context).textTheme.bodySmall),
          if (_busy) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 6),
            Text(_progress == null
                ? ui('正在检查并安装组件…')
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
                OutlinedButton(
                    onPressed: _busy ? null : () => _run(false),
                    child: Text(ui('我已安装好'))),
                FilledButton.icon(
                    onPressed: _busy ? null : () => _run(true),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(ui('从 GitHub 下载'))),
              ]),
        ]));
  }
}
