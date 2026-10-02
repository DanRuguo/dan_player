import 'dart:async';

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/audio_integrity.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef AudioIntegrityInspect = Future<AudioIntegrityReport> Function(
    Audio, AudioTrimCancellation, void Function(AudioIntegrityProgress));

Future<void> showAudioIntegrity(BuildContext context, Audio audio) =>
    showAppDialog<void>(
        context: context, builder: (_) => AudioIntegrityDialog(audio: audio));

class AudioIntegrityDialog extends StatefulWidget {
  const AudioIntegrityDialog(
      {super.key, required this.audio, this.inspect, this.ensureTools});
  final Audio audio;
  final AudioIntegrityInspect? inspect;
  final Future<bool> Function()? ensureTools;
  @override
  State<AudioIntegrityDialog> createState() => _AudioIntegrityDialogState();
}

class _AudioIntegrityDialogState extends State<AudioIntegrityDialog>
    with WidgetsBindingObserver {
  late final _title = widget.audio.title;
  late final _cue = widget.audio.isCueTrack;
  bool _checking = true, _ready = false, _busy = false;
  AudioTrimCancellation? _cancellation;
  AudioIntegrityProgress? _progress;
  AudioIntegrityReport? _report;
  String? _error, _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _title;
    _cue;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkTools());
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  Future<void> _checkTools() async {
    bool ready;
    try {
      ready = await (widget.ensureTools ?? FfmpegRuntime.shared.ensure)();
    } catch (_) {
      ready = false;
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _ready = ready;
      });
    }
  }

  Future<void> _start() async {
    if (_busy || !_ready || !widget.audio.isLocal) return;
    final generation = ++_generation;
    final token = _cancellation = AudioTrimCancellation();
    setState(() {
      _busy = true;
      _report = null;
      _progress = null;
      _error = null;
      _message = null;
    });
    void update(AudioIntegrityProgress progress) {
      if (!mounted || generation != _generation || token.isCancelled) return;
      final fraction = progress.fraction;
      if (fraction != null && !fraction.isFinite) return;
      setState(() => _progress =
          AudioIntegrityProgress(progress.phase, fraction?.clamp(0.0, 1.0)));
    }

    try {
      final result = await (widget.inspect ??
          (audio, token, update) => AudioIntegrityInspector().inspect(
              audio, token,
              onProgress: update))(widget.audio, token, update);
      if (!mounted || generation != _generation) return;
      if (token.isCancelled) {
        throw const AudioIntegrityException('已取消文件校验');
      }
      setState(() => _report = result);
    } on AudioIntegrityException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          if (token.isCancelled) {
            _message = '已取消文件校验';
          } else {
            _error = error.message;
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '解码检查未通过，请检查文件或编码格式');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _cancellation = null;
        });
      }
    }
  }

  String _reportText(AudioIntegrityReport report) => '$_title\n'
      '${ui('解码检查通过')}\n'
      '${ui('源文件')}：${report.path}\n'
      '${ui('文件大小')}：${report.bytes} ${ui('字节')}\n'
      '${ui('已解码时长')}：${ui('{0} 秒', [
            report.decodedSeconds.toStringAsFixed(2)
          ])}\n'
      'SHA-256：${report.sha256}\n'
      '${ui('校验值用于核对文件副本；解码检查不代表已与原始文件比对。')}';

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    final generation = _generation;
    bool stillCurrent() =>
        mounted && generation == _generation && identical(_report, report);
    try {
      await Clipboard.setData(ClipboardData(text: _reportText(report)));
      if (stillCurrent()) setState(() => _message = '文件校验结果已复制');
    } catch (_) {
      if (stillCurrent()) setState(() => _error = '无法复制校验结果，请重试');
    }
  }

  Widget _row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(ui(label)),
            SelectableText(value,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600))
          ]));

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final report = _report;
    final progress = _progress;
    final reduceMotion = appToolbarReduceMotion(context);
    final phase = progress?.phase == AudioIntegrityPhase.hashing
        ? '正在计算文件校验值…'
        : '正在检查音频解码…';
    return AlertDialog(
        scrollable: true,
        title: AppDialogTitle(ui('音频文件校验')),
        content: AppDialogResize(
            child: SizedBox(
                width: 540,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(ui(_cue ? '校验 CUE 对应的整份源文件' : '校验整份源文件的首个音轨'),
                          style: TextStyle(color: scheme.primary)),
                      const SizedBox(height: 8),
                      Text(ui('按需读取文件并完整解码，检测可识别的编码错误；同时计算 SHA-256，不改写歌曲。')),
                      const SizedBox(height: 12),
                      if (_checking) Text(ui('正在检查音频工具…')),
                      if (!_checking && !_ready)
                        FfmpegSetupCard(
                            title: ui('安装音频工具'),
                            description: ui('文件校验复用现有 FFmpeg 组件，可手动安装或按需下载。'),
                            onReady: () => setState(() => _ready = true)),
                      if (_busy) ...[
                        Semantics(
                            label: ui(phase),
                            liveRegion: true,
                            child: TickerMode(
                                enabled: !reduceMotion,
                                child: ExcludeSemantics(
                                    excluding: progress?.fraction == null,
                                    child: LinearProgressIndicator(
                                        key: const ValueKey(
                                            'integrity-progress'),
                                        value: progress?.fraction ??
                                            (reduceMotion ? 0 : null),
                                        semanticsLabel: ui(phase))))),
                        const SizedBox(height: 6),
                        Text(progress?.fraction == null
                            ? ui(phase)
                            : '${ui(phase)} ${(progress!.fraction! * 100).round()}%'),
                      ],
                      if (report != null) ...[
                        SettingsSurface(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Text(ui('解码检查通过'),
                                  style: TextStyle(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600)),
                              _row('文件大小', '${report.bytes} ${ui('字节')}'),
                              _row(
                                  '已解码时长',
                                  ui('{0} 秒', [
                                    report.decodedSeconds.toStringAsFixed(2)
                                  ])),
                              const SizedBox(height: 6),
                              const Text('SHA-256'),
                              const SizedBox(height: 4),
                              SelectableText(report.sha256,
                                  style: TextStyle(
                                      color: scheme.primary, fontSize: 13)),
                            ])),
                        const SizedBox(height: 10),
                        Text(ui('校验值用于核对文件副本；解码检查不代表已与原始文件比对。')),
                      ],
                      if (_message != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Semantics(
                                liveRegion: true, child: Text(ui(_message!)))),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Semantics(
                                liveRegion: true,
                                child: Text(ui(_error!),
                                    style: TextStyle(color: scheme.error)))),
                    ]))),
        actions: [
          if (report != null)
            TextButton(
                key: const ValueKey('integrity-copy'),
                onPressed: _copy,
                child: Text(ui('复制结果'))),
          TextButton(
              key: const ValueKey('integrity-close'),
              onPressed: () => Navigator.pop(context),
              child: Text(ui('关闭'))),
          if (_busy)
            OutlinedButton(
                key: const ValueKey('integrity-cancel'),
                onPressed: _cancellation!.cancel,
                child: Text(ui('取消校验')))
          else
            FilledButton(
                key: const ValueKey('integrity-start'),
                onPressed: _ready && !_checking && widget.audio.isLocal
                    ? _start
                    : null,
                child: Text(ui(report == null ? '开始校验' : '重新校验'))),
        ]);
  }

  @override
  void dispose() {
    ++_generation;
    _cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
