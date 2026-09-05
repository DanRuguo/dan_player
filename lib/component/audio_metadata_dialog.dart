import 'package:dan_player/component/app_presentation.dart';
import 'dart:io';

import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/online_metadata_lookup_dialog.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/audio_artwork.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path_util;
import 'package:desktop_lyric/ui_language.dart';

Future<bool> showEditAudioMetadataDialog(
  BuildContext context,
  Audio audio, {
  Future<Audio> Function(Audio, AudioMetadataEdit) saveMetadata =
      applyAudioMetadataEdit,
}) async {
  if (audio.isCueTrack) {
    showTextOnSnackBar('CUE 分轨信息由 CUE 文件提供，不能修改整轨音频。');
    return false;
  }
  if (audio.isOnline) {
    showTextOnSnackBar("联网歌曲信息由来源提供，不能修改其标签");
    return false;
  }
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _AudioMetadataDialog(audio: audio, saveMetadata: saveMetadata),
  );
  return result == true;
}

class _AudioMetadataDialog extends StatefulWidget {
  const _AudioMetadataDialog({required this.audio, required this.saveMetadata});

  final Audio audio;
  final Future<Audio> Function(Audio, AudioMetadataEdit) saveMetadata;

  @override
  State<_AudioMetadataDialog> createState() => _AudioMetadataDialogState();
}

class _AudioMetadataDialogState extends State<_AudioMetadataDialog> {
  late final fileNameController = TextEditingController(
    text: path_util.basename(widget.audio.path),
  );
  late final titleController = TextEditingController(text: widget.audio.title);
  late final artistController =
      TextEditingController(text: widget.audio.artist);
  late final albumController = TextEditingController(text: widget.audio.album);

  String? picturePath;
  Directory? _stagedArtwork;
  bool saving = false;
  bool _lookingUp = false;
  bool _pickingPicture = false;
  bool get _busy => saving || _lookingUp || _pickingPicture;

  @override
  void dispose() {
    fileNameController.dispose();
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    // A native worker can still be reading the staged cover if the whole
    // presentation host is disposed. Keep it until that operation completes.
    if (!saving) unawaited(_removeStagedArtwork(_stagedArtwork));
    super.dispose();
  }

  Future<void> _removeStagedArtwork(Directory? directory) async {
    if (directory == null) return;
    try {
      final file = File(path_util.join(directory.path, 'cover.png'));
      if (await file.exists()) await file.delete();
      await directory.delete();
    } catch (_) {
      // Never recursively remove a folder or a file selected by the user.
    }
  }

  Future<void> _lookupOnline() async {
    if (_busy) return;
    setState(() => _lookingUp = true);
    Directory? staged;
    try {
      final selection = await showOnlineMetadataLookupDialog(context,
          audio: widget.audio,
          title: titleController.text,
          artist: artistController.text);
      if (selection == null || !mounted) return;
      String? downloadedPicture;
      if (selection.artworkPng != null) {
        final data = await getAppDataDir();
        final cache =
            await Directory(path_util.join(data.path, 'metadata_preview'))
                .create(recursive: true);
        staged = await cache.createTemp('artwork-');
        final file = File(path_util.join(staged.path, 'cover.png'));
        await file.writeAsBytes(selection.artworkPng!, flush: true);
        downloadedPicture = file.path;
      }
      if (!mounted) {
        await _removeStagedArtwork(staged);
        return;
      }
      if (staged != null) {
        await _removeStagedArtwork(_stagedArtwork);
        if (!mounted) {
          await _removeStagedArtwork(staged);
          return;
        }
        _stagedArtwork = staged;
      }
      if (!mounted) return;
      setState(() {
        if (selection.title != null) titleController.text = selection.title!;
        if (selection.artist != null) artistController.text = selection.artist!;
        if (selection.album != null) albumController.text = selection.album!;
        if (downloadedPicture != null) picturePath = downloadedPicture;
      });
      showTextOnSnackBar("已填入候选信息，尚未写入文件。请核对后点击“保存”。");
    } catch (error, trace) {
      await _removeStagedArtwork(staged);
      LOGGER.e('[metadata preview] $error', stackTrace: trace);
      if (mounted) showTextOnSnackBar("准备歌曲信息失败：{0}", arguments: [error]);
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  Future<void> pickPicture() async {
    if (_busy) return;
    setState(() => _pickingPicture = true);
    try {
      final picker = OpenFilePicker();
      picker
        ..title = ui("选择专辑图片")
        ..filterSpecification = {
          ui("图片文件"): "*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.gif;*.tif;*.tiff",
          ui("所有文件"): "*.*",
        };

      final file = picker.getFile();
      if (file == null || !mounted) return;
      final previous = _stagedArtwork;
      setState(() {
        _stagedArtwork = null;
        picturePath = file.path;
      });
      await _removeStagedArtwork(previous);
    } catch (error, trace) {
      LOGGER.e('[metadata picture picker] $error', stackTrace: trace);
      if (mounted) showTextOnSnackBar("选择封面失败：{0}", arguments: [error]);
    } finally {
      if (mounted) setState(() => _pickingPicture = false);
    }
  }

  Future<void> save() async {
    if (_busy) return;
    final fileName = fileNameController.text.trim();
    final title = titleController.text.trim();
    final artist = artistController.text.trim().isEmpty
        ? "UNKNOWN"
        : artistController.text.trim();
    final album = albumController.text.trim().isEmpty
        ? "UNKNOWN"
        : albumController.text.trim();
    if (fileName.isEmpty || title.isEmpty) {
      showTextOnSnackBar("文件名和标题不能为空");
      return;
    }

    setState(() {
      saving = true;
    });
    try {
      await widget.saveMetadata(
        widget.audio,
        AudioMetadataEdit(
          fileName: fileName,
          title: title,
          artist: artist,
          album: album,
          picturePath: picturePath,
        ),
      );
      if (!mounted) return;
      showTextOnSnackBar("已更新歌曲信息");
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        saving = false;
      });
      if (err is AudioMetadataEditException) {
        if (err.fileWasUpdated) {
          showTextOnSnackBar(err.userMessage, context: context);
        } else {
          showTextOnSnackBar("更新歌曲信息失败：{0}",
              arguments: [ui(err.userMessage)], context: context);
        }
      } else {
        showTextOnSnackBar("更新歌曲信息失败：{0}", arguments: [err], context: context);
      }
    } finally {
      if (!mounted) await _removeStagedArtwork(_stagedArtwork);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final imageFile = picturePath == null ? null : File(picturePath!);

    return PopScope<bool>(
      canPop: !_busy,
      child: AlertDialog(
        title: AppDialogTitle(ui("编辑歌曲信息")),
        content: SizedBox(
          width: 460.0,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _lookupOnline,
                    icon: const Icon(Symbols.cloud_download),
                    label: Text(ui("联网查找信息与封面")),
                  ),
                ),
                const SizedBox(height: 14.0),
                _MetadataTextField(
                  controller: fileNameController,
                  enabled: !_busy,
                  label: ui("文件名"),
                  icon: Symbols.draft,
                ),
                const SizedBox(height: 12.0),
                _MetadataTextField(
                  controller: titleController,
                  enabled: !_busy,
                  label: ui("标题名"),
                  icon: Symbols.title,
                ),
                const SizedBox(height: 12.0),
                _MetadataTextField(
                  controller: artistController,
                  enabled: !_busy,
                  label: ui("艺术家名"),
                  icon: Symbols.artist,
                ),
                const SizedBox(height: 12.0),
                _MetadataTextField(
                  controller: albumController,
                  enabled: !_busy,
                  label: ui("专辑名"),
                  icon: Symbols.album,
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Container(
                      width: 64.0,
                      height: 64.0,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: AppShape.smallRadius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: imageFile != null && imageFile.existsSync()
                          ? ArtworkImage(
                              image: FileImage(imageFile),
                              size: 64,
                              errorBuilder: (_, __, ___) => Icon(Symbols.image,
                                  color: scheme.onSurfaceVariant),
                            )
                          : Icon(
                              Symbols.image,
                              color: scheme.onSurfaceVariant,
                            ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Text(
                        picturePath == null
                            ? ui("不更改专辑图片")
                            : path_util.basename(picturePath!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : pickPicture,
                      icon: const Icon(Symbols.upload),
                      label: Text(ui("上传图片")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Symbols.close),
            label: Text(ui("取消")),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : save,
            icon: saving
                ? const SizedBox(
                    width: 16.0,
                    height: 16.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  )
                : const Icon(Symbols.save),
            label: Text(saving ? ui("正在写入") : ui("保存")),
          ),
        ],
      ),
    );
  }
}

class _MetadataTextField extends StatelessWidget {
  const _MetadataTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return TextField(
      enabled: enabled,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: AppShape.inputBorder,
      ),
    );
  }
}
