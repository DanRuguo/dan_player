import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dan_player/library/playlist.dart';
import 'dart:async';
import 'dart:io';

import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist_exchange.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class PlaylistImportDetails {
  const PlaylistImportDetails(this.name, this.audios,
      {this.targetId, this.expectedSnapshot});
  final String? targetId, expectedSnapshot;
  final String name;
  final List<Audio> audios;
}

Future<PlaylistImportDetails?> importM3uPlaylist(BuildContext context,
    {required List<Audio> library,
    FutureOr<String?> Function()? pickFile,
    Future<M3uDocument> Function(File)? readFile,
    Future<bool> Function(String)? fileExists}) async {
  String? location;
  try {
    location = await (pickFile ??
        () => (OpenFilePicker()
              ..title = ui('导入 M3U8 歌单')
              ..filterSpecification = {'M3U / M3U8': '*.m3u;*.m3u8'})
            .getFile()
            ?.path)();
  } catch (_) {
    if (context.mounted) {
      showTextOnSnackBar('无法打开文件选择器，请稍后重试。',
          context: context, kind: AppNoticeKind.error);
    }
    return null;
  }
  if (location == null || !context.mounted) return null;
  final selectedFile = File(location);
  return showAppDialog<PlaylistImportDetails>(
      context: context,
      builder: (_) => M3uImportDialog(
          file: selectedFile,
          library: library,
          readFile: readFile,
          fileExists: fileExists));
}

class M3uImportDialog extends StatefulWidget {
  const M3uImportDialog(
      {super.key,
      required this.file,
      required this.library,
      this.readFile,
      this.fileExists});
  final File file;
  final List<Audio> library;
  final Future<M3uDocument> Function(File)? readFile;
  final Future<bool> Function(String)? fileExists;
  @override
  State<M3uImportDialog> createState() => _M3uImportDialogState();
}

class _M3uImportDialogState extends State<M3uImportDialog> {
  late final _name =
      TextEditingController(text: p.basenameWithoutExtension(widget.file.path));
  M3uDocument? _document;
  List<Audio>? _audios;
  String? _error;
  String? _targetId, _targetSnapshot, _sourceHash;
  bool _missingOnly = true, _submitting = false;
  int _missing = 0;
  List<Audio> get _additions => _targetSnapshot == null
      ? _audios ?? []
      : playlistMergeAdditions(
          Playlist.fromMap(jsonDecode(_targetSnapshot!) as Map), _audios ?? [],
          missingOnly: _missingOnly);
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      if (widget.readFile == null &&
          await widget.file.length() > 2 * 1024 * 1024) {
        throw const FormatException('歌单文件超过 2 MiB');
      }
      final sourceHash = widget.readFile == null
          ? sha256.convert(await widget.file.readAsBytes()).toString()
          : null;
      final document = await (widget.readFile ?? readM3uFile)(widget.file);
      final audios = await resolveM3uEntries(document, widget.library);
      if (sourceHash != null &&
          sourceHash !=
              sha256.convert(await widget.file.readAsBytes()).toString())
        throw const FormatException('源文件已改变，请重新预览。');
      var missing = 0;
      for (var i = 0; i < audios.length; i += 64) {
        final end = (i + 64).clamp(0, audios.length);
        final states = await Future.wait(audios.sublist(i, end).map((a) =>
            widget.fileExists?.call(a.localFilePath) ??
            File(a.localFilePath).exists()));
        missing += states.where((exists) => !exists).length;
        if (!mounted) return;
      }
      if (mounted) {
        setState(() {
          _sourceHash = sourceHash;
          _missing = missing;
          _document = document;
          _audios = audios;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is FormatException
            ? ui(error.message.toString())
            : ui('无法读取歌单文件，请检查文件位置与访问权限。'));
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting || _audios == null) return;
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 120) return;
    setState(() => _submitting = true);
    try {
      if (_sourceHash != null &&
          _sourceHash !=
              sha256.convert(await widget.file.readAsBytes()).toString())
        throw StateError('源文件已改变，请重新打开预览');
      if (_targetId != null) {
        final current = playlistTree.findPlaylist(_targetId!);
        if (current == null || jsonEncode(current.toMap()) != _targetSnapshot)
          throw StateError('目标歌单已改变，请重新选择目标以更新预览');
      }
      if (mounted)
        Navigator.of(context).pop(PlaylistImportDetails(
            name, List.unmodifiable(_additions),
            targetId: _targetId, expectedSnapshot: _targetSnapshot));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(ui('导入 M3U8 歌单')),
      content: SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                    borderRadius: AppShape.controlRadius,
                    elevation: 3,
                    dropdownColor:
                        Theme.of(context).colorScheme.surfaceContainerLow,
                    initialValue: '',
                    isExpanded: true,
                    decoration: InputDecoration(labelText: ui('导入目标')),
                    items: [
                      DropdownMenuItem(value: '', child: Text(ui('新建歌单'))),
                      for (final target in playlistTree.allPlaylists)
                        DropdownMenuItem(
                            value: target.id,
                            child: Text(target.name,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: _submitting
                        ? null
                        : (id) => setState(() {
                              _targetId = id == '' ? null : id;
                              _targetSnapshot = _targetId == null
                                  ? null
                                  : jsonEncode(playlistTree
                                      .findPlaylist(_targetId!)!
                                      .toMap());
                              _error = null;
                            })),
                if (_targetId != null) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ui('仅补充缺少的出现次数')),
                      subtitle: Text(ui('关闭后全部追加，保留现有顺序。')),
                      value: _missingOnly,
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _missingOnly = v)),
                  Text(ui('现有 {0} 项，将新增 {1} 项', [
                    (jsonDecode(_targetSnapshot!)['entries'] as List).length,
                    _additions.length
                  ])),
                ],
                const SizedBox(height: 12),
                Focus(
                    onFocusChange: HotkeysHelper.onFocusChanges,
                    child: TextField(
                      key: const ValueKey('m3u-import-name'),
                      controller: _name,
                      maxLength: 120,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                          labelText: ui('歌单名称'), border: AppShape.inputBorder),
                    )),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                else if (_document == null)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Text(ui('将导入 {0} 个本地歌曲引用，保留顺序与重复项。', [_additions.length])),
                  Text(ui('暂不可用 {0} 项：保留引用', [_missing])),
                  if (_document!.skipped > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            ui('跳过 {0} 项网络地址或不支持的格式。', [_document!.skipped]))),
                  const SizedBox(height: 8),
                  Text(ui('歌单只记录文件位置，不复制音乐；文件移动后需更新对应引用。')),
                  if (_audios!.isEmpty) Text(ui('没有可导入的本地歌曲。')),
                ],
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ui('取消'))),
        FilledButton(
            key: const ValueKey('m3u-import-confirm'),
            onPressed: !_submitting &&
                    _audios?.isNotEmpty == true &&
                    _name.text.trim().isNotEmpty &&
                    _name.text.trim().length <= 120
                ? _submit
                : null,
            child: Text(ui('导入'))),
      ],
    );
  }
}

/// Capture the selected occurrences before either dialog, including repeats.
Future<void> exportM3uPlaylist(BuildContext context, List<Audio> audios,
    {String name = 'Dan Player',
    FutureOr<String?> Function(String)? pickFile}) async {
  final entries = [
    for (final audio in audios)
      if (audio.isLocal && isM3uLocalAudioPath(audio.path))
        M3uEntry(audio.path,
            title: '${audio.artist} - ${audio.displayTitle}',
            duration: audio.duration)
  ];
  if (entries.isEmpty) {
    showTextOnSnackBar('所选歌曲中没有可导出的本地文件。',
        context: context, kind: AppNoticeKind.warning);
    return;
  }
  final relative = await showAppDialog<bool>(
      context: context,
      builder: (_) => M3uExportDialog(
          count: entries.length, skipped: audios.length - entries.length));
  if (relative == null || !context.mounted) return;
  final safeName =
      name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
  final proposed = '${safeName.isEmpty ? 'Dan Player' : safeName}.m3u8';
  try {
    final location = await (pickFile ??
        (String suggested) => (SaveFilePicker()
              ..title = ui('导出 M3U8 歌单')
              ..fileName = suggested
              ..defaultExtension = 'm3u8'
              ..filterSpecification = {'M3U8 (UTF-8)': '*.m3u8'})
            .getFile()
            ?.path)(proposed);
    if (location == null) return;
    // Preserve the exact path whose overwrite the native picker confirmed.
    if (!location.toLowerCase().endsWith('.m3u8')) {
      if (context.mounted) {
        showTextOnSnackBar('导出文件名请使用 .m3u8 后缀。',
            context: context, kind: AppNoticeKind.warning);
      }
      return;
    }
    await writeM3uFile(File(location), entries, relative: relative);
    if (context.mounted) {
      showTextOnSnackBar('M3U8 歌单已导出（{0} 首）。',
          arguments: [entries.length],
          context: context,
          kind: AppNoticeKind.success);
    }
  } catch (error) {
    if (context.mounted) {
      showTextOnSnackBar(
          error is FormatException
              ? error.message.toString()
              : '导出失败，请检查目标目录与写入权限。',
          context: context,
          kind: AppNoticeKind.error);
    }
  }
}

class M3uExportDialog extends StatefulWidget {
  const M3uExportDialog(
      {super.key, required this.count, required this.skipped});
  final int count;
  final int skipped;
  @override
  State<M3uExportDialog> createState() => _M3uExportDialogState();
}

class _M3uExportDialogState extends State<M3uExportDialog> {
  bool _relative = true;
  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(ui('导出 M3U8 歌单')),
      content: SizedBox(
          width: 400,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ui('导出 {0} 个本地歌曲引用，保留顺序与重复项。', [widget.count])),
                if (widget.skipped > 0)
                  Text(ui('跳过 {0} 项联网歌曲或不支持的文件引用。', [widget.skipped])),
                const SizedBox(height: 12),
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _relative,
                    title: Text(ui('使用相对路径')),
                    subtitle: Text(ui('与音乐文件一起移动文件夹时，更容易保持歌单可用。')),
                    onChanged: (value) =>
                        setState(() => _relative = value ?? true)),
              ])),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ui('取消'))),
        FilledButton(
            key: const ValueKey('m3u-export-confirm'),
            onPressed: () => Navigator.of(context).pop(_relative),
            child: Text(ui('选择保存位置')))
      ],
    );
  }
}
