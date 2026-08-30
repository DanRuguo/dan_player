import 'package:dan_player/component/app_presentation.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
  String confirmLabel = '创建',
}) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => PlaylistNameDialog(
        title: title,
        initialName: initialName,
        confirmLabel: confirmLabel,
      ),
    );

/// One validated, keyboard-accessible name form for root and nested playlists.
class PlaylistNameDialog extends StatefulWidget {
  const PlaylistNameDialog({
    super.key,
    required this.title,
    this.initialName = '',
    this.confirmLabel = '创建',
  });

  final String title;
  final String initialName;
  final String confirmLabel;

  @override
  State<PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<PlaylistNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _error;

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = ui("请输入歌单名称"));
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return AlertDialog(
      scrollable: true,
      title: AppDialogTitle(widget.title),
      content: SizedBox(
        width: 360,
        child: Focus(
          onFocusChange: HotkeysHelper.onFocusChanges,
          child: TextField(
            key: const ValueKey('playlist-name-input'),
            controller: _controller,
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ui("取消")),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
