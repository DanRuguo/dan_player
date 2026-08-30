import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class ThemePickerDialog extends StatefulWidget {
  const ThemePickerDialog({super.key});

  @override
  State<ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<ThemePickerDialog> {
  var selectedColor = Color(AppSettings.instance.defaultTheme);
  late final rgbHexTextEditingController = TextEditingController(
    text: selectedColor.toRGBHexString(),
  );

  @override
  void dispose() {
    rgbHexTextEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      // Keep actions visible when the content panel or a notification leaves
      // little vertical room. The color wheel retains its usable touch size.
      scrollable: true,
      title: AppDialogTitle(
        ui("主题选择器"),
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: 350.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Focus(
              onFocusChange: HotkeysHelper.onFocusChanges,
              child: TextField(
                key: const ValueKey('theme-hex-input'),
                autofocus: true,
                controller: rgbHexTextEditingController,
                onChanged: (value) {
                  final c = fromRGBHexString(value);
                  if (c != null) {
                    setState(() {
                      selectedColor = c;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: "Hex RGB",
                  border: AppShape.inputBorder,
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            SizedBox(
              key: const ValueKey('theme-color-wheel'),
              height: 400,
              child: ColorWheelPicker(
                color: selectedColor,
                onChanged: (color) {
                  setState(() {
                    selectedColor = color;
                  });
                  rgbHexTextEditingController.text = color.toRGBHexString();
                },
                onWheel: (isWheel) {},
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ui("取消")),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, selectedColor),
          child: Text(ui("确定")),
        ),
      ],
    );
  }
}
