import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/batch_audio_metadata.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> showBatchAudioMetadataDialog(
    BuildContext context, List<Audio> audios) async {
  final batch = BatchAudioMetadata(audios);
  try {
    await showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BatchAudioMetadataDialog(batch: batch));
  } finally {
    batch.dispose();
  }
}

String batchMetadataStatusLabel(BatchMetadataStatus status) => switch (status) {
      BatchMetadataStatus.ready => '待应用',
      BatchMetadataStatus.success => '已保存',
      BatchMetadataStatus.unchanged => '未修改',
      BatchMetadataStatus.skipped => '已跳过',
      BatchMetadataStatus.failed => '失败',
      BatchMetadataStatus.pendingSync => '已写入，待同步',
      BatchMetadataStatus.cancelled => '未开始，已取消',
    };

class BatchAudioMetadataDialog extends StatefulWidget {
  const BatchAudioMetadataDialog({super.key, required this.batch});
  final BatchAudioMetadata batch;
  @override
  State<BatchAudioMetadataDialog> createState() =>
      _BatchAudioMetadataDialogState();
}

class _BatchAudioMetadataDialogState extends State<BatchAudioMetadataDialog> {
  late final _artist = TextEditingController(
      text: widget.batch.commonValue((audio) => audio.artist) ?? '');
  late final _album = TextEditingController(
      text: widget.batch.commonValue((audio) => audio.album) ?? '');
  final _titleEdits = <String>{};
  late final _titles = {
    for (final target in widget.batch.targets)
      target.trackId: TextEditingController(text: target.audio.title)
  };
  bool _setArtist = false, _setAlbum = false;
  @override
  void dispose() {
    _artist.dispose();
    _album.dispose();
    for (final controller in _titles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _preview() async {
    try {
      await widget.batch.preview(BatchMetadataDraft(
          artist: _setArtist ? _artist.text : null,
          album: _setAlbum ? _album.text : null,
          titles: {for (final id in _titleEdits) id: _titles[id]!.text}));
    } catch (error) {
      if (mounted) {
        showAppNotice(
            error is FormatException ? error.message : error.toString(),
            context: context,
            kind: AppNoticeKind.warning);
      }
    }
  }

  Widget _commonField(
      BuildContext context,
      String label,
      IconData icon,
      TextEditingController controller,
      bool enabled,
      ValueChanged<bool> setEnabled,
      bool mixed) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
        key: ValueKey('batch-common-$label'),
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: AppShape.controlRadius,
            side: BorderSide(
                color: enabled ? scheme.primary : scheme.outlineVariant)),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(icon, color: scheme.primary),
                  title: Text(ui(label)),
                  subtitle: Text(
                      enabled
                          ? ui('设置为以下值')
                          : '${ui('不修改')} · ${mixed ? ui('多个值') : controller.text.isEmpty ? ui('空值') : controller.text}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  value: enabled,
                  onChanged: widget.batch.busy ? null : setEnabled),
              if (enabled)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                        controller: controller,
                        enabled: !widget.batch.busy,
                        decoration: InputDecoration(
                            labelText: ui(label),
                            prefixIcon: Icon(icon),
                            hintText: mixed ? ui('多个值') : null,
                            helperText: ui('空白不会清除标签'),
                            helperMaxLines: 2))),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
        listenable: widget.batch,
        builder: (context, _) {
          final batch = widget.batch;
          final scheme = Theme.of(context).colorScheme;
          return PopScope(
              canPop: !batch.busy,
              child: Dialog(
                  child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 860,
                    maxHeight: MediaQuery.sizeOf(context).height * .86),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AppDialogTitle(ui('批量编辑标签'),
                          leading: const Icon(Symbols.edit_note),
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      Text(
                          ui('处理 {0} 个文件；文件名保持不变。已保存的文件不会因取消而撤销。',
                              [batch.targets.length]),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall),
                      if (batch.busy)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator()),
                      const SizedBox(height: 12),
                      Flexible(
                          child: ListView(shrinkWrap: true, children: [
                        if (!batch.previewed) ...[
                          LayoutBuilder(builder: (context, constraints) {
                            final fields = [
                              _commonField(
                                  context,
                                  '艺术家',
                                  Symbols.person,
                                  _artist,
                                  _setArtist,
                                  (value) => setState(() => _setArtist = value),
                                  batch.commonValue((audio) => audio.artist) ==
                                      null),
                              _commonField(
                                  context,
                                  '专辑',
                                  Symbols.album,
                                  _album,
                                  _setAlbum,
                                  (value) => setState(() => _setAlbum = value),
                                  batch.commonValue((audio) => audio.album) ==
                                      null),
                            ];
                            return constraints.maxWidth /
                                        MediaQuery.textScalerOf(context)
                                            .scale(1) >=
                                    640
                                ? IntrinsicHeight(
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                        Expanded(child: fields[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: fields[1])
                                      ]))
                                : Column(children: [
                                    fields[0],
                                    const SizedBox(height: 12),
                                    fields[1]
                                  ]);
                          }),
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(children: [
                                Icon(Symbols.queue_music,
                                    color: scheme.primary, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(ui('逐首标题'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: scheme.primary)))
                              ])),
                        ] else
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(BatchMetadataStatus.values
                                  .where((status) => batch.count(status) > 0)
                                  .map((status) =>
                                      '${ui(batchMetadataStatusLabel(status))} ${batch.count(status)}')
                                  .join(' · '))),
                        for (final target in batch.targets)
                          Card(
                            color: scheme.surfaceContainerLow,
                            elevation: 0,
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      DecoratedBox(
                                          decoration: BoxDecoration(
                                              color: scheme.primaryContainer,
                                              borderRadius:
                                                  AppShape.smallRadius),
                                          child: Padding(
                                              padding: const EdgeInsets.all(10),
                                              child: Icon(Symbols.music_note,
                                                  color:
                                                      scheme.onPrimaryContainer,
                                                  size: 22))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(target.audio.displayTitle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall),
                                            const SizedBox(height: 4),
                                            Tooltip(
                                                message: target.path,
                                                child: SelectableText(
                                                    target.path,
                                                    maxLines: 1,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                            color: scheme
                                                                .onSurfaceVariant))),
                                          ])),
                                      if (!batch.previewed) ...[
                                        const SizedBox(width: 8),
                                        Tooltip(
                                            message: ui('修改此曲标题'),
                                            child: Switch.adaptive(
                                                value: _titleEdits
                                                    .contains(target.trackId),
                                                onChanged: batch.busy ||
                                                        !target.audio
                                                            .canEditLocalFile
                                                    ? null
                                                    : (value) => setState(() {
                                                          if (value) {
                                                            _titleEdits.add(
                                                                target.trackId);
                                                          } else {
                                                            _titleEdits.remove(
                                                                target.trackId);
                                                          }
                                                        }))),
                                      ],
                                    ]),
                                    if (!batch.previewed) ...[
                                      if (_titleEdits.contains(target.trackId))
                                        Padding(
                                            padding:
                                                const EdgeInsets.only(top: 14),
                                            child: TextField(
                                                controller:
                                                    _titles[target.trackId],
                                                enabled: !batch.busy,
                                                decoration: InputDecoration(
                                                    labelText: ui('标题'),
                                                    prefixIcon: const Icon(
                                                        Symbols.title),
                                                    border:
                                                        const OutlineInputBorder()))),
                                      if (!target.audio.canEditLocalFile)
                                        Text(ui(target.audio.isOnline
                                            ? '联网歌曲不能写入本地标签'
                                            : 'CUE 分轨不能修改整轨音频标签')),
                                    ] else ...[
                                      const SizedBox(height: 8),
                                      Text(
                                          ui(batchMetadataStatusLabel(
                                              target.status)),
                                          style: TextStyle(
                                              color: target.status ==
                                                          BatchMetadataStatus
                                                              .failed ||
                                                      target.status ==
                                                          BatchMetadataStatus
                                                              .pendingSync
                                                  ? scheme.error
                                                  : scheme.primary)),
                                      if (target.before != null &&
                                          target.edit != null) ...[
                                        _diff('标题', target.before!.title,
                                            target.edit!.title),
                                        _diff('艺术家', target.before!.artist,
                                            target.edit!.artist),
                                        _diff('专辑', target.before!.album,
                                            target.edit!.album),
                                      ],
                                      if (target.reason.isNotEmpty)
                                        Text(ui(target.reason),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall),
                                    ],
                                  ],
                                )),
                          ),
                      ])),
                      const SizedBox(height: 12),
                      AppDialogActions(children: [
                        TextButton(
                            onPressed: batch.busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: Text(ui('关闭'))),
                        if (batch.busy)
                          OutlinedButton(
                              onPressed: batch.cancellationRequested
                                  ? null
                                  : batch.cancel,
                              child: Text(ui(batch.cancellationRequested
                                  ? '正在停止…'
                                  : '停止后续处理'))),
                        if (!batch.previewed)
                          FilledButton(
                              onPressed: batch.busy ? null : _preview,
                              child: Text(ui('预览修改'))),
                        if (batch.previewed &&
                            batch.count(BatchMetadataStatus.ready) > 0)
                          FilledButton(
                              onPressed:
                                  batch.busy ? null : () => batch.apply(),
                              child: Text(ui('应用预览'))),
                        if (batch.previewed &&
                            batch.targets.any((target) => target.retryable))
                          OutlinedButton(
                              onPressed: batch.busy
                                  ? null
                                  : () => batch.apply(retryOnly: true),
                              child: Text(ui('仅重试失败和待同步项'))),
                      ]),
                    ])),
              )));
        });
  }

  Widget _diff(String label, String before, String after) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(before == after
          ? '${ui(label)} · ${before.isEmpty ? ui('空值') : before} · ${ui('不修改')}'
          : '${ui(label)} · ${before.isEmpty ? ui('空值') : before} → $after'));
}
