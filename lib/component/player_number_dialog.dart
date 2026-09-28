import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// Small explicit-entry form shared by everyday playback controls.
class PlayerNumberDialog extends StatefulWidget {
  const PlayerNumberDialog(
      {super.key,
      required this.title,
      required this.label,
      required this.value,
      required this.minimum,
      required this.maximum});
  final String title, label;
  final int value, minimum, maximum;

  @override
  State<PlayerNumberDialog> createState() => _PlayerNumberDialogState();
}

class _PlayerNumberDialogState extends State<PlayerNumberDialog> {
  late final _controller = TextEditingController(text: '${widget.value}');
  String? _error;

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < widget.minimum || value > widget.maximum) {
      setState(() =>
          _error = ui('请输入 {0} 到 {1} 之间的整数', [widget.minimum, widget.maximum]));
      return;
    }
    Navigator.pop(context, value);
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
              key: const ValueKey('player-number-input'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              autocorrect: false,
              maxLength: 8,
              decoration: InputDecoration(
                  labelText: widget.label,
                  helperText: '${widget.minimum} – ${widget.maximum}',
                  errorText: _error,
                  errorMaxLines: 3,
                  counterText: ''),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          )),
      actions: [
        AppDialogActions(children: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(ui('取消'))),
          FilledButton(onPressed: _submit, child: Text(ui('确定'))),
        ])
      ],
    );
  }
}
