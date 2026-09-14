import 'dart:async';

import 'package:dan_player/component/app_dialog_content.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_preview.dart';
import 'package:dan_player/play_service/seek_target.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:dan_player/utils.dart' show showAppNotice;

typedef AudioTrimSaver = Future<AudioTrimResult> Function(
    Audio audio, AudioTrimRequest request,
    {void Function(double)? onProgress, AudioTrimCancellation? cancellation});

/// Native diagnostics are intentionally reduced to stable, translated messages.
/// In particular paths and internal error codes never become dialog copy.
String audioTrimErrorMessage(Object error) {
  if (error.toString().contains('TAG_LAYOUT_UNSUPPORTED')) {
    return ui('此文件包含不支持的混合容器或标签布局，暂不能安全裁剪。原文件未修改。');
  }
  if (error is AudioTrimException) {
    return error.message.split('\n').map(ui).join('\n');
  }
  final code = RegExp(r'TRIM_[A-Z_]+').firstMatch(error.toString())?.group(0);
  return ui(switch (code) {
    'TRIM_TAGS_UNSUPPORTED' => '无法完整保留原标签或封面。可关闭继承原歌曲信息，并另存副本。',
    'TRIM_SOURCE_CHANGED' => '原歌曲在裁剪期间发生变化，请关闭窗口后重新打开。',
    'TRIM_DESTINATION_EXISTS' || 'TRIM_BACKUP_EXISTS' => '此文件名已存在，请换一个名称保存副本',
    'TRIM_PATH_INVALID' || 'TRIM_PATH_ALIAS' => '请选择有效的保存位置和文件名',
    'TRIM_READ_ONLY' ||
    'TRIM_STAGE_FAILED' ||
    'TRIM_COMMIT_FAILED' =>
      '无法保存，请检查文件是否被占用以及文件夹写入权限。',
    'TRIM_FORMAT_UNSUPPORTED' || 'TRIM_FORMAT_CHANGED' => '此音频格式暂不支持安全裁剪',
    'TRIM_BUSY' => '曲库操作正在进行，请稍后再裁剪',
    'TRIM_NOT_VERIFIED' ||
    'TRIM_VERIFY_FAILED' ||
    'TRIM_OUTPUT_CHANGED' ||
    'TRIM_EMPTY_OUTPUT' =>
      '裁剪结果校验失败，原文件未被修改',
    _ => '未完成裁剪。',
  });
}

Future<AudioTrimResult?> showAudioTrimDialog(BuildContext context,
        {required Audio audio}) =>
    showAppDialog<AudioTrimResult>(
        context: context, builder: (_) => AudioTrimDialog(audio: audio));

String formatTrimTime(double seconds) {
  final ms = (seconds * 1000).round();
  final hours = ms ~/ 3600000;
  final minutes = (ms ~/ 60000) % 60;
  final tail = '${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.'
      '${(ms % 1000).toString().padLeft(3, '0')}';
  return hours == 0
      ? '${ms ~/ 60000}:$tail'
      : '$hours:${minutes.toString().padLeft(2, '0')}:$tail';
}

class AudioTrimDialog extends StatefulWidget {
  const AudioTrimDialog(
      {super.key,
      required this.audio,
      this.inspect,
      this.save = trimAudio,
      this.preview,
      this.pickDirectory});
  final Audio audio;
  final Future<AudioTrimInfo> Function(Audio)? inspect;
  final AudioTrimSaver save;
  final AudioTrimPreview? preview;
  final FutureOr<String?> Function()? pickDirectory;

  @override
  State<AudioTrimDialog> createState() => _AudioTrimDialogState();
}

class _AudioTrimDialogState extends State<AudioTrimDialog> {
  late final _preview = widget.preview ?? ProcessAudioTrimPreview(widget.audio);
  final _start = TextEditingController(text: '0:00.000');
  final _end = TextEditingController();
  final _filename = TextEditingController();
  late final _originalTitle = widget.audio.title;
  late final _originalArtist = widget.audio.artist;
  late final _originalAlbum = widget.audio.album;
  late final _title = TextEditingController(text: _originalTitle);
  late final _artist = TextEditingController(text: _originalArtist);
  late final _album = TextEditingController(text: _originalAlbum);
  late String _directory = path.dirname(widget.audio.localFilePath);
  AudioTrimInfo? _info;
  AudioTrimCancellation? _cancellation;
  AudioTrimCancellation? _inspectionCancellation;
  RangeValues _range = const RangeValues(0, 1);
  String? _error;
  String? _rangeError;
  bool _inspecting = true;
  bool _busy = false;
  bool _closing = false;
  bool _overwrite = false;
  bool _overwriteAcknowledged = false;
  bool _preserve = true;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _preview.addListener(_previewChanged);
    unawaited(_inspect());
  }

  void _previewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _inspect() async {
    setState(() {
      _inspecting = true;
      _error = null;
    });
    final cancellation = _inspectionCancellation = AudioTrimCancellation();
    try {
      final info = await (widget.inspect?.call(widget.audio) ??
          inspectAudioForTrim(widget.audio, cancellation: cancellation));
      if (!mounted) return;
      if (!info.duration.isFinite || info.duration <= 0) {
        throw StateError('Invalid audio duration');
      }
      setState(() {
        _info = info;
        _range = RangeValues(0, info.duration);
        _end.text = formatTrimTime(info.duration);
        _filename.text =
            '${path.basenameWithoutExtension(widget.audio.localFilePath)}'
            '${ui(' - 裁剪')}${info.outputExtension}';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = audioTrimErrorMessage(error));
      }
    } finally {
      if (identical(_inspectionCancellation, cancellation)) {
        _inspectionCancellation = null;
      }
      if (mounted) setState(() => _inspecting = false);
    }
  }

  void _editRange(String _) {
    unawaited(_preview.stop());
    try {
      final start = SeekTarget.parse(_start.text);
      final end = SeekTarget.parse(_end.text);
      if (start.relative ||
          end.relative ||
          start.seconds < 0 ||
          end.seconds - start.seconds < .05 ||
          end.seconds > _info!.duration + .0005) {
        throw const FormatException();
      }
      setState(() {
        _range = RangeValues(
            start.seconds, end.seconds.clamp(0, _info!.duration).toDouble());
        _rangeError = null;
      });
    } catch (_) {
      setState(() => _rangeError = ui('请输入有效的起止时间：开始早于结束，且不超过歌曲时长。'));
    }
  }

  void _slideRange(RangeValues value) {
    unawaited(_preview.stop());
    setState(() {
      _range = value;
      _start.text = formatTrimTime(value.start);
      _end.text = formatTrimTime(value.end);
      _rangeError = value.end - value.start >= .05
          ? null
          : ui('请输入有效的起止时间：开始早于结束，且不超过歌曲时长。');
    });
  }

  Future<void> _chooseDirectory() async {
    final picked = widget.pickDirectory != null
        ? await widget.pickDirectory!()
        : (DirectoryPicker()..title = ui('选择保存文件夹')).getDirectory()?.path;
    if (picked != null && mounted) setState(() => _directory = picked);
  }

  String? get _filenameError {
    final name = _filename.text.trim();
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name) ||
        name.endsWith('.') ||
        name.endsWith(' ')) {
      return ui('请输入有效的文件名，不要包含路径或特殊保留字符。');
    }
    if (_info != null &&
        !name.toLowerCase().endsWith(_info!.outputExtension.toLowerCase())) {
      return ui('请保留文件名末尾的音频扩展名。');
    }
    return null;
  }

  bool get _canSave =>
      !_busy &&
      !_closing &&
      !_inspecting &&
      _info != null &&
      _rangeError == null &&
      _range.end - _range.start >= .05 &&
      (_overwrite ? _overwriteAcknowledged : _filenameError == null);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    final cancellation = _cancellation = AudioTrimCancellation();
    try {
      await _preview.stop();
      cancellation.check();
      final result = await widget.save(
          widget.audio,
          AudioTrimRequest(
            destinationPath: _overwrite
                ? widget.audio.localFilePath
                : path.join(_directory, _filename.text.trim()),
            startSeconds: _range.start,
            endSeconds: _range.end,
            overwrite: _overwrite,
            preserveMetadata: _preserve,
            title:
                _preserve && _title.text == _originalTitle ? null : _title.text,
            artist: _preserve && _artist.text == _originalArtist
                ? null
                : _artist.text,
            album:
                _preserve && _album.text == _originalAlbum ? null : _album.text,
          ), onProgress: (value) {
        if (mounted) setState(() => _progress = value.clamp(0, 1).toDouble());
      }, cancellation: cancellation);
      if (mounted) {
        final message = '${ui('片段已保存')}\n${result.path}'
            '${result.warning == null ? '' : '\n${result.warning!.split('\n').map(ui).join('\n')}'}'
            '${result.libraryUpdated || result.warning != null ? '' : '\n${ui('文件已保存，但曲库暂未更新，请重新扫描文件夹。')}'}';
        showAppNotice(message,
            context: context,
            kind: result.warning == null
                ? AppNoticeKind.success
                : AppNoticeKind.warning,
            duration: const Duration(seconds: 8));
        Navigator.pop(context, result);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = audioTrimErrorMessage(error));
      }
    } finally {
      _cancellation = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) {
      if (_cancellation?.canCancel == true) _cancellation?.cancel();
      return;
    }
    if (_closing) return;
    setState(() => _closing = true);
    await _preview.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _inspectionCancellation?.cancel();
    _preview.removeListener(_previewChanged);
    if (widget.preview == null) {
      _preview.dispose();
    } else {
      unawaited(_preview.stop());
    }
    for (final controller in [
      _start,
      _end,
      _filename,
      _title,
      _artist,
      _album
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _caption(String text) => Text(text,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));

  Widget _rangeCard(AudioTrimInfo info) => SettingsSurface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
              title: ui('选择片段'),
              icon: Icons.content_cut,
              subtitle:
                  '${info.formatLabel} · ${ui('原始时长')} ${formatTrimTime(info.duration)}'),
          const SizedBox(height: 8),
          RangeSlider(
              key: const ValueKey('trim-range'),
              values: _range,
              min: 0,
              max: info.duration,
              labels: RangeLabels(
                  formatTrimTime(_range.start), formatTrimTime(_range.end)),
              onChanged: _busy ? null : _slideRange),
          LayoutBuilder(builder: (context, constraints) {
            final children = [
              TextField(
                  key: const ValueKey('trim-start'),
                  controller: _start,
                  enabled: !_busy,
                  onChanged: _editRange,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: ui('开始时间'))),
              TextField(
                  key: const ValueKey('trim-end'),
                  controller: _end,
                  enabled: !_busy,
                  onChanged: _editRange,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: ui('结束时间'))),
            ];
            return constraints.maxWidth < 360
                ? Column(children: [
                    children[0],
                    const SizedBox(height: 12),
                    children[1]
                  ])
                : Row(children: [
                    Expanded(child: children[0]),
                    const SizedBox(width: 12),
                    Expanded(child: children[1])
                  ]);
          }),
          const SizedBox(height: 10),
          _caption(ui('可输入秒数或 分:秒，最多保留三位小数。')),
          if (_rangeError != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_rangeError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                    '${ui('选区时长')} ${formatTrimTime(_range.end - _range.start)}',
                    style: Theme.of(context).textTheme.titleSmall),
                OutlinedButton.icon(
                    key: const ValueKey('trim-preview'),
                    onPressed: _busy || _closing || _rangeError != null
                        ? null
                        : () {
                            if (_preview.playing || _preview.loading) {
                              unawaited(_preview.stop());
                            } else {
                              unawaited(
                                  _preview.play(_range.start, _range.end));
                            }
                          },
                    icon: Icon(_preview.playing || _preview.loading
                        ? Icons.stop
                        : Icons.play_arrow),
                    label: Text(ui(_preview.playing || _preview.loading
                        ? '停止试听'
                        : '试听选区'))),
              ]),
          const SizedBox(height: 6),
          _caption(ui('试听会暂时暂停主播放；结束后恢复，若已自行操作主播放则不再恢复。')),
          if (_preview.error != null)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(ui(_preview.error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ));

  Widget _destinationCard(AudioTrimInfo info) => SettingsSurface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(title: ui('保存方式'), icon: Icons.save_outlined),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
              key: const ValueKey('trim-overwrite'),
              contentPadding: EdgeInsets.zero,
              title: Text(ui('覆盖原文件')),
              subtitle: Text(ui('默认创建副本，原歌曲保持不变。')),
              value: _overwrite,
              onChanged: _busy || !info.canOverwrite
                  ? null
                  : (value) => setState(() {
                        _overwrite = value;
                        _overwriteAcknowledged = false;
                      })),
          if (_overwrite) ...[
            CheckboxListTile(
                key: const ValueKey('trim-acknowledge'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _overwriteAcknowledged,
                onChanged: _busy
                    ? null
                    : (value) =>
                        setState(() => _overwriteAcknowledged = value == true),
                title: Text(ui('我确认覆盖原文件。被裁掉的内容无法撤销恢复。'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          ] else ...[
            const SizedBox(height: 8),
            TextField(
                key: const ValueKey('trim-filename'),
                controller: _filename,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: ui('文件名'), errorText: _filenameError)),
            const SizedBox(height: 12),
            _caption(ui('保存文件夹')),
            const SizedBox(height: 4),
            Text(_directory, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                  key: const ValueKey('trim-original-folder'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _directory =
                          path.dirname(widget.audio.localFilePath)),
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(ui('原文件夹'))),
              OutlinedButton.icon(
                  key: const ValueKey('trim-other-folder'),
                  onPressed: _busy ? null : _chooseDirectory,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(ui('其他位置'))),
            ]),
          ],
          const SizedBox(height: 8),
          _caption(ui('按原始格式精确裁剪。有损音频会重新编码，无损音频保持无损。')),
          if (info.limitation != null) ...[
            const SizedBox(height: 8),
            _caption(ui(info.limitation!))
          ],
        ],
      ));

  Widget _metadataCard() => SettingsSurface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
              key: const ValueKey('trim-metadata'),
              contentPadding: EdgeInsets.zero,
              value: _preserve,
              title: Text(ui('继承原歌曲信息')),
              subtitle: Text(ui(_preserve
                  ? '保留封面等附加信息，并自动对齐歌词时间；纯文本歌词原样保留。'
                  : '仅写入下方标题、艺术家和专辑；覆盖原文件时仍会对齐独立歌词时间。')),
              onChanged:
                  _busy ? null : (value) => setState(() => _preserve = value)),
          ExpansionTile(
              key: const ValueKey('trim-edit-metadata'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 8),
              title: Text(ui('编辑歌曲信息')),
              subtitle: Text(ui('时长根据裁剪结果自动更新。')),
              children: [
                for (final field in [
                  (_title, '标题', 'trim-title'),
                  (_artist, '艺术家', 'trim-artist'),
                  (_album, '专辑', 'trim-album')
                ])
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                          key: ValueKey(field.$3),
                          controller: field.$1,
                          enabled: !_busy,
                          decoration:
                              InputDecoration(labelText: ui(field.$2)))),
              ]),
        ],
      ));

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final info = _info;
    final compact = MediaQuery.sizeOf(context).width < 480;
    return PopScope(
        canPop: !_busy && !_closing,
        child: Dialog(
          insetPadding:
              EdgeInsets.symmetric(horizontal: compact ? 12 : 40, vertical: 24),
          child: AppDialogContent(
            width: 660,
            maxHeight: MediaQuery.sizeOf(context).height * .90,
            child: Padding(
                padding: EdgeInsets.all(compact ? 16 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppDialogTitle(ui('歌曲裁剪'),
                        style: Theme.of(context).textTheme.titleLarge,
                        subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(widget.audio.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.bodyMedium))),
                    const SizedBox(height: 16),
                    Flexible(
                        child: SingleChildScrollView(
                            child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_inspecting)
                          const Padding(
                              padding: EdgeInsets.all(24),
                              child:
                                  Center(child: CircularProgressIndicator())),
                        if (info != null) ...[
                          _rangeCard(info),
                          const SizedBox(height: 12),
                          _destinationCard(info),
                          const SizedBox(height: 12),
                          _metadataCard(),
                        ],
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        if (!_inspecting && info == null)
                          TextButton(
                              onPressed: _inspect, child: Text(ui('重试'))),
                      ],
                    ))),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 6),
                      _caption(ui('正在裁剪并检查音频…')),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          TextButton(
                              key: const ValueKey('trim-cancel'),
                              onPressed: _closing ||
                                      (_busy &&
                                          _cancellation?.canCancel == false)
                                  ? null
                                  : _close,
                              child: Text(ui(_busy
                                  ? (_cancellation?.canCancel == false
                                      ? '正在保存…'
                                      : '取消裁剪')
                                  : '取消'))),
                          FilledButton.icon(
                              key: const ValueKey('trim-save'),
                              onPressed: _canSave ? _save : null,
                              icon: const Icon(Icons.content_cut),
                              label: Text(ui('保存片段'))),
                        ]),
                  ],
                )),
          ),
        ));
  }
}
