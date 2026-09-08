import 'package:dan_player/component/app_dialog_content.dart';
import 'dart:math' as math;

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/online/custom_music_source_probe.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/custom_music_source_transport.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<CustomMusicSourceProbeReport?> showCustomMusicSourceProbeDialog(
  BuildContext context, {
  required CustomMusicSourceProfile profile,
  ValueChanged<Set<CustomMusicSourceCapability>>? onApplyCapabilities,
  CustomMusicSourceProbeService? service,
}) =>
    showAppDialog<CustomMusicSourceProbeReport>(
      context: context,
      builder: (_) => _CustomMusicSourceProbeDialog(
        profile: profile,
        onApplyCapabilities: onApplyCapabilities,
        service: service ?? CustomMusicSourceProbeService(),
      ),
    );

class _CustomMusicSourceProbeDialog extends StatefulWidget {
  const _CustomMusicSourceProbeDialog({
    required this.profile,
    required this.service,
    this.onApplyCapabilities,
  });

  final CustomMusicSourceProfile profile;
  final CustomMusicSourceProbeService service;
  final ValueChanged<Set<CustomMusicSourceCapability>>? onApplyCapabilities;

  @override
  State<_CustomMusicSourceProbeDialog> createState() =>
      _CustomMusicSourceProbeDialogState();
}

class _CustomMusicSourceProbeDialogState
    extends State<_CustomMusicSourceProbeDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: '卡农');
  final _artist = TextEditingController();
  final _album = TextEditingController();
  final _controlsScroll = ScrollController();
  final _resultsScroll = ScrollController();
  final _results =
      <CustomMusicSourceCapability, CustomMusicSourceProbeResult>{};
  CustomMusicSourceProbeReport? _report;
  CustomMusicSourceCancellation? _cancellation;
  bool _running = false;
  bool _closed = false;
  String? _error;

  void _cancel() => _cancellation?.cancel();

  void _close() {
    if (_closed) return;
    _closed = true;
    _cancel();
    Navigator.pop(context);
  }

  Future<void> _run() async {
    if (_closed || _running || _form.currentState?.validate() != true) return;
    final cancellation = CustomMusicSourceCancellation();
    _cancellation = cancellation;
    setState(() {
      _running = true;
      _report = null;
      _error = null;
      _results.clear();
    });
    bool active() =>
        mounted && !_closed && identical(_cancellation, cancellation);
    try {
      final report = await widget.service.run(
        widget.profile,
        title: _title.text.trim(),
        artist: _artist.text.trim(),
        album: _album.text.trim(),
        cancellation: cancellation,
        onResult: (result) {
          if (active()) setState(() => _results[result.capability] = result);
        },
      );
      if (!active()) return;
      setState(() {
        _report = report;
        _results.addEntries(report.results
            .map((result) => MapEntry(result.capability, result)));
      });
    } catch (_) {
      if (active()) setState(() => _error = ui('测试未完成，请检查配置后重试'));
    } finally {
      if (active()) {
        setState(() {
          _running = false;
          _cancellation = null;
        });
      }
      cancellation.cancel();
    }
  }

  void _apply() {
    final report = _report;
    if (_closed ||
        _running ||
        report == null ||
        report.detectedCapabilities.isEmpty) {
      return;
    }
    final capabilities = Set<CustomMusicSourceCapability>.unmodifiable({
      ...widget.profile.capabilities,
      ...report.detectedCapabilities,
    });
    final navigator = Navigator.of(context);
    _closed = true;
    _cancel();
    widget.onApplyCapabilities?.call(capabilities);
    navigator.pop(report);
  }

  @override
  void dispose() {
    _closed = true;
    _cancel();
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _controlsScroll.dispose();
    _resultsScroll.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController controller, String label, String key,
          {bool required = false}) =>
      TextFormField(
        key: ValueKey(key),
        controller: controller,
        enabled: !_running,
        maxLength: 160,
        onFieldSubmitted: (_) => _run(),
        validator: required
            ? (value) => value?.trim().isNotEmpty == true ? null : ui('请填写歌曲名')
            : null,
        decoration: InputDecoration(
          labelText: ui(label),
          counterText: '',
          border: AppShape.inputBorder,
          isDense: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = _report;
    return PopScope<CustomMusicSourceProbeReport>(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _closed = true;
        _cancel();
      },
      child: Dialog(
        child: AppDialogContent(
          width: 760,
          maxHeight: math.min(740, MediaQuery.sizeOf(context).height * .88),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogTitle(
                  ui('测试歌源能力'),
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  leading: const Icon(Symbols.network_check),
                  trailing: IconButton(
                    key: const ValueKey('custom-source-probe-close'),
                    onPressed: _close,
                    tooltip: ui('关闭'),
                    icon: const Icon(Symbols.close),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: LayoutBuilder(builder: (context, constraints) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight * .48,
                          ),
                          child: Scrollbar(
                            controller: _controlsScroll,
                            child: SingleChildScrollView(
                              controller: _controlsScroll,
                              primary: false,
                              padding:
                                  const EdgeInsets.only(right: 8, bottom: 8),
                              child: Form(
                                key: _form,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(widget.profile.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    _field(_title, '歌曲名（必填）',
                                        'custom-source-probe-title',
                                        required: true),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      Expanded(
                                          child: _field(_artist, '艺术家（可选）',
                                              'custom-source-probe-artist')),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: _field(_album, '专辑（可选）',
                                              'custom-source-probe-album')),
                                    ]),
                                    const SizedBox(height: 10),
                                    Text(
                                        ui('向此 API 发送查询信息与匹配歌曲标识，仅读取少量响应；不实际播放、不下载整首歌曲。'),
                                        style: theme.textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text(
                                        ui('未找到样本不代表永久不支持；应用结果只补充成功项，不移除已有能力。'),
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_running)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: AppShape.surfaceRadius,
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Scrollbar(
                              controller: _resultsScroll,
                              child: ListView.separated(
                                shrinkWrap: true,
                                key: const ValueKey(
                                    'custom-source-probe-results'),
                                controller: _resultsScroll,
                                primary: false,
                                padding: const EdgeInsets.all(8),
                                itemCount:
                                    CustomMusicSourceCapability.values.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 2),
                                itemBuilder: (context, index) {
                                  final capability =
                                      CustomMusicSourceCapability.values[index];
                                  final result = _results[capability];
                                  final color = switch (result?.status) {
                                    CustomMusicSourceProbeStatus.success =>
                                      scheme.primary,
                                    CustomMusicSourceProbeStatus.failed =>
                                      scheme.error,
                                    _ => scheme.onSurfaceVariant,
                                  };
                                  return ListTile(
                                    key: ValueKey(
                                        'custom-source-probe-${capability.id}'),
                                    leading: Icon(_capabilityIcon(capability),
                                        color: color),
                                    title:
                                        Text(ui(_capabilityLabel(capability))),
                                    subtitle: result == null
                                        ? null
                                        : Text(ui(result.detail)),
                                    trailing: Text(
                                      result == null
                                          ? ui(_running ? '等待测试' : '尚未测试')
                                          : ui(_statusLabel(result.status)),
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(color: color),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                if (report != null) ...[
                  const SizedBox(height: 8),
                  Text(
                      ui('本轮耗时 {0} 秒', [
                        (report.elapsed.inMilliseconds / 1000)
                            .toStringAsFixed(1)
                      ]),
                      style: theme.textTheme.bodySmall),
                  if (report.sampleTitle != null)
                    Text(ui('测试样本：{0}', [report.sampleTitle!]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child:
                          Text(_error!, style: TextStyle(color: scheme.error))),
                const SizedBox(height: 12),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 10,
                  overflowSpacing: 6,
                  children: [
                    TextButton(onPressed: _close, child: Text(ui('关闭'))),
                    OutlinedButton.icon(
                      key: const ValueKey('custom-source-probe-start'),
                      onPressed: _running ? _cancel : _run,
                      icon: Icon(_running
                          ? Symbols.stop_circle
                          : Symbols.network_check),
                      label: Text(ui(_running ? '停止测试' : '开始测试')),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('custom-source-probe-apply'),
                      onPressed: _running ||
                              report == null ||
                              report.detectedCapabilities.isEmpty
                          ? null
                          : _apply,
                      icon: const Icon(Symbols.check),
                      label: Text(ui('应用已测得能力')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(CustomMusicSourceProbeStatus status) => switch (status) {
      CustomMusicSourceProbeStatus.success => '成功',
      CustomMusicSourceProbeStatus.noSample => '未找到样本',
      CustomMusicSourceProbeStatus.unsupported => '未支持',
      CustomMusicSourceProbeStatus.needsLogin => '需登录',
      CustomMusicSourceProbeStatus.timeout => '超时',
      CustomMusicSourceProbeStatus.failed => '失败',
      CustomMusicSourceProbeStatus.cancelled => '已取消',
    };

String _capabilityLabel(CustomMusicSourceCapability capability) =>
    switch (capability) {
      CustomMusicSourceCapability.search => '搜索',
      CustomMusicSourceCapability.metadata => '歌曲信息',
      CustomMusicSourceCapability.cover => '封面',
      CustomMusicSourceCapability.lyrics => '歌词',
      CustomMusicSourceCapability.comments => '评论',
      CustomMusicSourceCapability.stream => '播放',
      CustomMusicSourceCapability.download => '下载',
    };

IconData _capabilityIcon(CustomMusicSourceCapability capability) =>
    switch (capability) {
      CustomMusicSourceCapability.search => Symbols.search,
      CustomMusicSourceCapability.metadata => Symbols.info,
      CustomMusicSourceCapability.cover => Symbols.image,
      CustomMusicSourceCapability.lyrics => Symbols.lyrics,
      CustomMusicSourceCapability.comments => Symbols.comment,
      CustomMusicSourceCapability.stream => Symbols.play_circle,
      CustomMusicSourceCapability.download => Symbols.download,
    };
