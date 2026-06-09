import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/utils.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as path_util;

Future<bool> showEditAudioMetadataDialog(
  BuildContext context,
  Audio audio,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => _AudioMetadataDialog(audio: audio),
  );
  return result == true;
}

class _AudioMetadataDialog extends StatefulWidget {
  const _AudioMetadataDialog({required this.audio});

  final Audio audio;

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
  bool saving = false;

  @override
  void dispose() {
    fileNameController.dispose();
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    super.dispose();
  }

  Future<void> pickPicture() async {
    final picker = OpenFilePicker();
    picker
      ..title = "选择专辑图片"
      ..filterSpecification = {
        "图片文件": "*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.gif;*.tif;*.tiff",
        "所有文件": "*.*",
      };

    final file = picker.getFile();
    if (file == null) return;
    setState(() {
      picturePath = file.path;
    });
  }

  Future<void> save() async {
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
      await applyAudioMetadataEdit(
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
      showTextOnSnackBar("更新歌曲信息失败：$err");
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final imageFile = picturePath == null ? null : File(picturePath!);

    return AlertDialog(
      title: const Text("编辑歌曲信息"),
      content: SizedBox(
        width: 460.0,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MetadataTextField(
                controller: fileNameController,
                label: "文件名",
                icon: Symbols.draft,
              ),
              const SizedBox(height: 12.0),
              _MetadataTextField(
                controller: titleController,
                label: "标题名",
                icon: Symbols.title,
              ),
              const SizedBox(height: 12.0),
              _MetadataTextField(
                controller: artistController,
                label: "艺术家名",
                icon: Symbols.artist,
              ),
              const SizedBox(height: 12.0),
              _MetadataTextField(
                controller: albumController,
                label: "专辑名",
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
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: imageFile != null && imageFile.existsSync()
                        ? Image.file(imageFile, fit: BoxFit.cover)
                        : Icon(
                            Symbols.image,
                            color: scheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      picturePath == null
                          ? "不更改专辑图片"
                          : path_util.basename(picturePath!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: saving ? null : pickPicture,
                    icon: const Icon(Symbols.upload),
                    label: const Text("上传图片"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: saving ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Symbols.close),
          label: const Text("取消"),
        ),
        FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 16.0,
                  height: 16.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Icon(Symbols.save),
          label: Text(saving ? "正在写入" : "保存"),
        ),
      ],
    );
  }
}

class _MetadataTextField extends StatelessWidget {
  const _MetadataTextField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
