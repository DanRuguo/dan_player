import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onChanged,
    this.busy = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final bool busy;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
        onFocusChange: HotkeysHelper.onFocusChanges,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: ui('搜索本地曲库和联网音乐'),
            border: AppShape.inputBorder,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.text.isNotEmpty)
                  IconButton(
                    tooltip: ui('清除搜索'),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                    icon: const Icon(Symbols.close),
                  ),
                if (busy)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: ui('正在搜索'),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: ui('搜索'),
                    onPressed: controller.text.trim().isEmpty
                        ? null
                        : () => onSubmitted(controller.text),
                    icon: const Icon(Symbols.search),
                  ),
              ],
            ),
          ),
        ),
      );
}
