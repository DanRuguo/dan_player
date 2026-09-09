import 'dart:convert';
import 'package:dan_player/component/app_shape.dart';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Native information is queried only when expanded/refreshed or when the
/// central playback state changes, never once per position tick.
class PlaybackDiagnosticsPanel extends StatefulWidget {
  const PlaybackDiagnosticsPanel({super.key, required this.audio});
  final Audio audio;

  @override
  State<PlaybackDiagnosticsPanel> createState() =>
      _PlaybackDiagnosticsPanelState();
}

class _PlaybackDiagnosticsPanelState extends State<PlaybackDiagnosticsPanel> {
  bool _expanded = false;

  Future<void> _export(Map<String, Object?> snapshot) async {
    try {
      final picker = SaveFilePicker()
        ..title = ui('导出播放诊断')
        ..fileName = 'DanPlayer-playback-diagnostics.json'
        ..defaultExtension = 'json'
        ..filterSpecification = {ui('诊断文件'): '*.json'};
      final file = picker.getFile();
      if (file == null) return;
      await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert(snapshot),
          flush: true);
      if (mounted) showTextOnSnackBar('已导出脱敏播放诊断', kind: AppNoticeKind.success);
    } catch (_) {
      if (mounted) {
        showTextOnSnackBar('导出诊断失败，请检查保存位置', kind: AppNoticeKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PlaybackReadyBuilder(
        waitingBuilder: (_) => const SizedBox.shrink(),
        readyBuilder: (_) {
          final playback = PlayService.instance.playbackService;
          return ListenableBuilder(
            listenable: Listenable.merge([
              playback,
              playback.diagnosticsRevision,
              playback.resolvingAudioPath,
              playback.isChangingOutput,
              playback.eqEnabled,
              playback.playbackRate,
              playback.wasapiExclusive,
            ]),
            builder: (context, _) {
              final current = playback.nowPlaying?.path == widget.audio.path;
              final scheme = Theme.of(context).colorScheme;
              return Card.filled(
                  margin: EdgeInsets.zero,
                  color: scheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppShape.controlRadius,
                      side: BorderSide(color: scheme.outlineVariant)),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    key: const ValueKey('playback-diagnostics'),
                    leading: Icon(Symbols.tune,
                        color: Theme.of(context).colorScheme.primary),
                    title: Text(ui('播放详情'),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600)),
                    subtitle: Text(ui(current
                        ? '输出、音频处理与诊断'
                        : playback.nowPlaying == null
                            ? '尚未打开音频，可查看最近错误与输出状态'
                            : '以下参数对应正在播放的歌曲')),
                    onExpansionChanged: (expanded) =>
                        setState(() => _expanded = expanded),
                    children: [
                      if (_expanded)
                        PlaybackDiagnosticsContent(
                          snapshot: playback.playbackDiagnostics(),
                          onExport: _export,
                          onRefresh: () => setState(() {}),
                        ),
                    ],
                  ));
            },
          );
        },
      );
}

class PlaybackDiagnosticsContent extends StatelessWidget {
  const PlaybackDiagnosticsContent({
    super.key,
    required this.snapshot,
    required this.onExport,
    required this.onRefresh,
  });
  final Map<String, Object?> snapshot;
  final Future<void> Function(Map<String, Object?>) onExport;
  final VoidCallback onRefresh;

  String _format(Object? value) {
    if (value is! Map || value['sampleRate'] == null) return ui('未知 / 未接通检测');
    final sample = value['sampleFormat'] ?? ui('精度未知');
    final bits = value['originalBits'];
    return '${value['sampleRate']} Hz · ${value['channels']} ch · $sample'
        '${bits == null ? '' : ' · ${ui('源精度')} $bits bit'}';
  }

  String _mode(Object? value) => switch (value) {
        'album' => ui('专辑'),
        'track' => ui('单曲'),
        'off' => ui('关闭'),
        _ => ui('未应用'),
      };

  @override
  Widget build(BuildContext context) {
    final output = snapshot['output'] as Map? ?? const {};
    final device = output['deviceFormat'];
    final deviceExclusive = device is Map ? device['exclusive'] : null;
    final gain = output['replayGainEffectiveDb'];
    final eqBands = output['eqAppliedBands'] as int? ?? 0;
    final multiplier = output['effectiveDspMultiplier'];
    final error = snapshot['error'] ?? output['error'];
    final phase = switch (snapshot['phase']) {
      'paused' => ui('已暂停'),
      'playing' => ui('正在播放'),
      _ => '${snapshot['phase'] ?? '—'}',
    };
    final rows = <String, String>{
      '会话 / 状态': '${output['session'] ?? '—'} · $phase',
      '音源 / 解码输出': _format(output['source']),
      '请求输出': output['requestedOutput'] == 'exclusive'
          ? ui('WASAPI 独占 · 格式由设备协商')
          : ui('系统共享 · 格式由 Windows 决定'),
      '已接通链路': output['streamOutput'] == 'exclusive'
          ? ui(deviceExclusive == true ? 'WASAPI 独占已初始化' : '独占解码链路；设备尚未确认')
          : ui('BASS 系统共享输出'),
      '设备编号': '${output['deviceNumber'] ?? ui('未知')}',
      '设备实际格式': _format(device),
      if (output['mixerFormat'] != null)
        '混音 / 处理格式': _format(output['mixerFormat']),
      'ReplayGain 请求 / 生效':
          '${_mode(output['replayGainRequested'])} / ${_mode(output['replayGainApplied'])}',
      '实际响度增益':
          gain is num ? '${gain.toStringAsFixed(2)} dB' : ui('未应用、静音或无法检测'),
      '实际 DSP 音量倍数':
          multiplier is num ? multiplier.toStringAsFixed(4) : ui('未知'),
      'EQ 请求 / 生效': '${ui(output['eqRequested'] == true ? '开启' : '关闭')} / '
          '${eqBands == 0 ? ui('未应用') : ui('{0} 个频段', [eqBands])}'
          '${output['eqRequested'] == true && output['eqSettingsApplied'] == false ? ' · ${ui('部分设置未应用')}' : ''}',
      '播放速度': '${output['playbackRate'] ?? '—'}×',
      if (output['endReason'] != null) '最近结束原因': '${output['endReason']}',
      if (error is Map)
        '最近错误 / 原生代码': '${error['category']} / ${error['nativeCode'] ?? '—'}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = constraints.maxWidth / scale >= 760 ? 2 : 1;
            final contentWidth =
                (constraints.maxWidth - (columns - 1) * 12) / columns - 28;
            final groups = [
              _DiagnosticGroup(
                  contentWidth: contentWidth,
                  title: ui('音频输出'),
                  icon: Symbols.speaker,
                  rows: Map.fromEntries(rows.entries.where((row) => [
                        '音源 / 解码输出',
                        '请求输出',
                        '已接通链路',
                        '设备编号',
                        '设备实际格式',
                        '混音 / 处理格式'
                      ].contains(row.key)))),
              _DiagnosticGroup(
                  contentWidth: contentWidth,
                  title: ui('音频处理'),
                  icon: Symbols.tune,
                  rows: Map.fromEntries(rows.entries.where((row) => [
                        'ReplayGain 请求 / 生效',
                        '实际响度增益',
                        '实际 DSP 音量倍数',
                        'EQ 请求 / 生效',
                        '播放速度'
                      ].contains(row.key)))),
            ];
            return columns == 2
                ? IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                        Expanded(child: groups[0]),
                        const SizedBox(width: 12),
                        Expanded(child: groups[1])
                      ]))
                : Column(children: [
                    groups[0],
                    const SizedBox(height: 12),
                    groups[1]
                  ]);
          }),
          const SizedBox(height: 12),
          LayoutBuilder(
              builder: (context, constraints) => _DiagnosticGroup(
                  contentWidth: constraints.maxWidth - 28,
                  title: ui('状态与诊断'),
                  icon: Symbols.monitor_heart,
                  rows: Map.fromEntries(rows.entries.where((row) => [
                        '会话 / 状态',
                        '最近结束原因',
                        '最近错误 / 原生代码'
                      ].contains(row.key))))),
          const SizedBox(height: 8),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(ui('检测与隐私说明'),
                  style: Theme.of(context).textTheme.bodyMedium),
              leading: Icon(Symbols.info,
                  color: Theme.of(context).colorScheme.primary, size: 20),
              children: [
                Text(
                    ui('独占不代表 Bit-perfect 已验证。结束位置来自后端媒体边界，未检测硬件缓冲排空。'
                        '削波保护只约束已有 ReplayGain 标签，后续 EQ 和变速仍可能改变样本；未提供 R128 或全链路削波测量。'),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(ui('导出仅包含版本、状态、错误分类和输出参数，不包含歌曲名称、私人路径、凭据或音乐文件。'),
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
          const SizedBox(height: 12),
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Symbols.refresh),
                    label: Text(ui('刷新详情'))),
                OutlinedButton.icon(
                    onPressed: () => onExport(snapshot),
                    icon: const Icon(Symbols.download),
                    label: Text(ui('导出脱敏诊断'))),
              ]),
        ],
      ),
    );
  }
}

class _DiagnosticGroup extends StatelessWidget {
  const _DiagnosticGroup(
      {required this.title,
      required this.icon,
      required this.rows,
      required this.contentWidth});
  final double contentWidth;
  final String title;
  final IconData icon;
  final Map<String, String> rows;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        key: ValueKey('diagnostic-group-$title'),
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: AppShape.controlRadius,
            border:
                Border.all(color: scheme.outlineVariant.withValues(alpha: .6))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: scheme.primary)))
          ]),
          const SizedBox(height: 10),
          for (final row in rows.entries)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Builder(builder: (context) {
                  final label = Text(ui(row.key),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant));
                  final value = SelectableText(row.value,
                      style: Theme.of(context).textTheme.bodyMedium);
                  return contentWidth /
                              MediaQuery.textScalerOf(context).scale(1) <
                          340
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [label, const SizedBox(height: 4), value])
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Expanded(flex: 4, child: label),
                              const SizedBox(width: 12),
                              Expanded(flex: 6, child: value)
                            ]);
                })),
        ]));
  }
}
