import 'dart:async';

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_resize.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/component/ffmpeg_setup_card.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/library/loudness_analysis.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef LoudnessAnalyze = Future<LoudnessReport> Function(
    Audio, LoudnessCancellation, void Function(double));

Future<void> showLoudnessAnalysis(BuildContext context, Audio audio) =>
    showAppDialog<void>(
        context: context, builder: (_) => LoudnessAnalysisDialog(audio: audio));

class LoudnessAnalysisDialog extends StatefulWidget {
  const LoudnessAnalysisDialog(
      {super.key, required this.audio, this.analyze, this.ensureTools});
  final Audio audio;
  final LoudnessAnalyze? analyze;
  final Future<bool> Function()? ensureTools;
  @override
  State<LoudnessAnalysisDialog> createState() => _LoudnessAnalysisDialogState();
}

class _LoudnessAnalysisDialogState extends State<LoudnessAnalysisDialog>
    with WidgetsBindingObserver {
  bool _checking = true, _ready = false, _busy = false;
  double? _progress;
  double _target = -18;
  LoudnessCancellation? _cancellation;
  LoudnessReport? _report;
  String? _error, _message;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
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
    final cancellation = _cancellation = LoudnessCancellation();
    setState(() {
      _busy = true;
      _progress = null;
      _report = null;
      _error = null;
      _message = null;
    });
    void progress(double value) {
      if (!mounted || generation != _generation || cancellation.isCancelled) {
        return;
      }
      if (!value.isFinite) return;
      setState(() => _progress = value.clamp(0.0, 1.0));
    }

    try {
      final report = await (widget.analyze ??
              (audio, token, update) =>
                  LoudnessAnalyzer().analyze(audio, token, onProgress: update))(
          widget.audio, cancellation, progress);
      if (!mounted || generation != _generation) return;
      cancellation.check();
      setState(() => _report = report);
    } on LoudnessAnalysisException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          if (cancellation.isCancelled) {
            _message = '已取消响度分析';
          } else {
            _error = error.message;
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '无法分析此音频文件，请检查文件是否完整');
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

  String _metric(double? value, String unit, {bool integrated = false}) =>
      value == null
          ? ui(integrated ? '低于响度门限' : '静音')
          : '${value.toStringAsFixed(1)} $unit';

  String _reportText(LoudnessReport report) {
    final gain = report.suggestedGain(_target);
    return '${widget.audio.title}\n'
        '${ui(widget.audio.isCueTrack ? '分析当前 CUE 分轨' : '分析整首源文件')}\n'
        '${ui('整体响度')}：${_metric(report.integratedLufs, 'LUFS', integrated: true)}\n'
        '${ui('响度范围')}：${_metric(report.rangeLu, 'LU')}\n'
        '${ui('样本峰值')}：${_metric(report.samplePeakDb, 'dBFS')}\n'
        '${ui('真峰值')}：${_metric(report.truePeakDb, 'dBTP')}\n'
        '${report.analyzedSeconds == null ? '' : '${ui('已分析时长')}：${ui('{0} 秒', [
                report.analyzedSeconds!.toStringAsFixed(2)
              ])}\n'}'
        '${ui('参考目标响度')}：${_target.toStringAsFixed(0)} LUFS\n'
        '${ui('峰值受限的参考增益')}：${gain == null ? ui('无法估算') : '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB'}\n'
        '${ui('测量原始音频，不含播放器音量、均衡器或变速处理。')}';
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: _reportText(report)));
      if (mounted) setState(() => _message = '分析结果已复制');
    } catch (_) {
      if (mounted) setState(() => _error = '无法复制分析结果，请重试');
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
    final gain = report?.suggestedGain(_target);
    final reduceMotion = appToolbarReduceMotion(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(ui('响度与峰值')),
      content: AppDialogResize(
          child: SizedBox(
              width: 570,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.audio.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(ui(widget.audio.isCueTrack ? '分析当前 CUE 分轨' : '分析整首源文件'),
                      style: TextStyle(color: scheme.primary)),
                  const SizedBox(height: 8),
                  Text(ui('测量原始音频，不含播放器音量、均衡器或变速处理。')),
                  const SizedBox(height: 12),
                  if (_checking) Text(ui('正在检查音频工具…')),
                  if (!_checking && !_ready)
                    FfmpegSetupCard(
                        title: ui('安装音频工具'),
                        description:
                            ui('响度分析复用 FFmpeg 组件，不改写歌曲。可手动安装，或按需下载现有组件。'),
                        onReady: () => setState(() => _ready = true)),
                  if (_busy) ...[
                    Semantics(
                        label: ui('正在分析响度…'),
                        liveRegion: true,
                        child: TickerMode(
                            enabled: !reduceMotion,
                            child: ExcludeSemantics(
                                excluding: _progress == null,
                                child: LinearProgressIndicator(
                                    key: const ValueKey('loudness-progress'),
                                    value:
                                        _progress ?? (reduceMotion ? 0 : null),
                                    semanticsLabel: ui('正在分析响度…'))))),
                    const SizedBox(height: 6),
                    Text(_progress == null
                        ? ui('正在分析响度…')
                        : ui('正在分析响度：{0}%', [(_progress! * 100).round()])),
                  ],
                  if (report != null) ...[
                    SettingsSurface(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          _row(
                              '整体响度',
                              _metric(report.integratedLufs, 'LUFS',
                                  integrated: true)),
                          _row('响度范围', _metric(report.rangeLu, 'LU')),
                          _row('样本峰值', _metric(report.samplePeakDb, 'dBFS')),
                          _row('真峰值', _metric(report.truePeakDb, 'dBTP')),
                          if (report.analyzedSeconds != null)
                            _row(
                                '已分析时长',
                                ui('{0} 秒', [
                                  report.analyzedSeconds!.toStringAsFixed(2)
                                ])),
                        ])),
                    const SizedBox(height: 12),
                    Text('${ui('参考目标响度')} · ${_target.toInt()} LUFS'),
                    const SizedBox(height: 6),
                    SizedBox(
                        height: appToolbarControlHeight(context),
                        child: AppSegmentedControl<double>(
                            key: const ValueKey('loudness-target'),
                            semanticLabel: ui('参考目标响度'),
                            value: _target,
                            onChanged: (value) =>
                                setState(() => _target = value),
                            options: [
                              for (final target in [-14.0, -18.0, -23.0])
                                AppSegmentOption(
                                    value: target,
                                    label: '${target.toInt()} LUFS',
                                    icon: Icons.volume_up_outlined)
                            ])),
                    _row(
                        '峰值受限的参考增益',
                        gain == null
                            ? ui('无法估算')
                            : '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)} dB'),
                    Text(ui('仅作静态增益参考，按 −1 dBTP 留出峰值余量；不会自动调整音量或写入标签。')),
                    if (report.truePeakDb != null &&
                        report.truePeakDb! >= 0) ...[
                      const SizedBox(height: 8),
                      Text(ui('真峰值达到或超过 0 dBTP，请留意采样间峰值。'),
                          style: TextStyle(color: scheme.error)),
                    ],
                    if (report.integratedLufs == null) ...[
                      const SizedBox(height: 8),
                      Text(ui('音频过短、静音或低于响度门限，无法可靠估算整体响度增益。')),
                    ],
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
                ],
              ))),
      actions: [
        if (report != null)
          TextButton(
              key: const ValueKey('loudness-copy'),
              onPressed: _copy,
              child: Text(ui('复制结果'))),
        TextButton(
            key: const ValueKey('loudness-close'),
            onPressed: () => Navigator.pop(context),
            child: Text(ui('关闭'))),
        if (_busy)
          OutlinedButton(
              key: const ValueKey('loudness-cancel'),
              onPressed: _cancellation!.cancel,
              child: Text(ui('取消分析')))
        else
          FilledButton(
              key: const ValueKey('loudness-start'),
              onPressed:
                  _ready && !_checking && widget.audio.isLocal ? _start : null,
              child: Text(ui(report == null ? '开始分析' : '重新分析'))),
      ],
    );
  }

  @override
  void dispose() {
    ++_generation;
    _cancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
