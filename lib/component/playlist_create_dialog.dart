import 'dart:async';

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playlist_song_picker.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

typedef PlaylistImagePicker = FutureOr<String?> Function();

String? pickPlaylistImage() => (OpenFilePicker()
      ..title = ui("选择歌单封面")
      ..filterSpecification = {
        ui("图片文件"): '*.jpg;*.jpeg;*.png;*.webp;*.bmp',
        ui("所有文件"): '*.*',
      })
    .getFile()
    ?.path;

class NewPlaylistDetails {
  const NewPlaylistDetails(this.name, this.imagePath, this.audios);

  final String name;
  final String? imagePath;
  final List<Audio> audios;
}

/// Creating an empty folder remains possible. Selecting songs and art here
/// retains the old collection creation workflow without a second data store.
class PlaylistCreateDialog extends StatefulWidget {
  const PlaylistCreateDialog({
    super.key,
    required this.title,
    this.library,
    this.pickImage,
  });

  final String title;
  final List<Audio>? library;
  final PlaylistImagePicker? pickImage;

  @override
  State<PlaylistCreateDialog> createState() => _PlaylistCreateDialogState();
}

class _PlaylistCreateDialogState extends State<PlaylistCreateDialog> {
  final _name = TextEditingController();
  String? _imagePath;
  String? _error;
  List<Audio> _selected = [];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = ui("请输入歌单名称"));
      return;
    }
    Navigator.of(context).pop(NewPlaylistDetails(name, _imagePath, _selected));
  }

  Future<void> _chooseImage() async {
    try {
      final path = await (widget.pickImage ?? pickPlaylistImage)();
      if (mounted && path != null) setState(() => _imagePath = path);
    } catch (_) {
      if (mounted) setState(() => _error = ui("无法打开图片选择器，请稍后重试"));
    }
  }

  Future<void> _chooseSongs() async {
    final selected = await showPlaylistSongPicker(
      context,
      existingPaths: const {},
      library: widget.library,
      selectedAudios: _selected,
      replaceSelection: true,
    );
    if (mounted && selected != null) setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      title: AppDialogTitle(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  key: const ValueKey('playlist-name-input'),
                  controller: _name,
                  autofocus: true,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  decoration: InputDecoration(
                    labelText: ui("歌单名称"),
                    border: AppShape.inputBorder,
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('playlist-create-cover'),
                    onPressed: _chooseImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_imagePath == null ? ui("选择封面") : ui("更换封面")),
                  ),
                  if (_imagePath != null)
                    TextButton(
                      onPressed: () => setState(() => _imagePath = null),
                      child: Text(ui("移除自定义封面")),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('playlist-create-songs'),
                    onPressed: _chooseSongs,
                    icon: const Icon(Icons.playlist_add_check),
                    label: Text(ui("选择歌曲（{0} 首）", [_selected.length])),
                  ),
                ],
              ),
              if (_imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_imagePath!,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              const SizedBox(height: 12),
              Text(ui("封面和歌曲可稍后添加；歌单中也可以继续创建子歌单。")),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ui("取消")),
        ),
        FilledButton(
          key: const ValueKey('playlist-confirm-create'),
          onPressed: _submit,
          child: Text(ui("创建")),
        ),
      ],
    );
  }
}
