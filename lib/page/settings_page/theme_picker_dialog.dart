import 'dart:math' as math;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class ThemePickerDialog extends StatefulWidget {
  const ThemePickerDialog({super.key});
  @override
  State<ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<ThemePickerDialog> {
  final _originalColor = Color(AppSettings.instance.defaultTheme);
  late Color selectedColor = _originalColor;
  bool _invalidHex = false, _updateWheel = false;
  late final rgbHexTextEditingController = TextEditingController(
    text: selectedColor.toRGBHexString(),
  );

  void _chooseColor(Color color, {bool fromWheel = false}) {
    setState(() {
      selectedColor = color;
      _invalidHex = false;
      _updateWheel = !fromWheel;
      rgbHexTextEditingController.text = color.toRGBHexString();
    });
  }

  @override
  void dispose() {
    rgbHexTextEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
        seedColor: selectedColor, brightness: theme.brightness);
    final wheelSize = math.min(
        264.0, math.max(120.0, MediaQuery.sizeOf(context).width - 128));
    final presets = <Color>{
      _originalColor,
      const Color(0xff287b84),
      const Color(0xff4169a8),
      const Color(0xff7862a8),
      const Color(0xffad607c),
      const Color(0xffb56b45),
      const Color(0xff7a893f),
    };
    return Theme(
      data: theme.copyWith(colorScheme: scheme),
      child: AlertDialog(
        scrollable: true,
        backgroundColor: scheme.surface,
        title: AppDialogTitle(
          ui("主题选择器"),
          leading: Icon(Symbols.palette, color: scheme.primary),
          style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        ),
        content: SizedBox(
          width: 376,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                key: const ValueKey('theme-color-preview'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppShape.controlRadius,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: AppShape.smallRadius),
                    child: Icon(Symbols.music_note,
                        color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dan Player',
                          style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600)),
                      Text(ui('主题预览'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  )),
                  const SizedBox(width: 8),
                  Icon(Symbols.play_circle, color: scheme.primary, size: 30),
                ]),
              ),
              const SizedBox(height: 14),
              Center(
                  child: SizedBox.square(
                key: const ValueKey('theme-color-wheel'),
                dimension: wheelSize,
                child: ColorWheelPicker(
                  color: selectedColor,
                  shouldUpdate: _updateWheel,
                  wheelWidth: 14,
                  wheelSquarePadding: 8,
                  wheelSquareBorderRadius: 8,
                  onChanged: (color) => _chooseColor(color, fromWheel: true),
                  onWheel: (_) {},
                ),
              )),
              const SizedBox(height: 14),
              Focus(
                onFocusChange: HotkeysHelper.onFocusChanges,
                child: TextField(
                  key: const ValueKey('theme-hex-input'),
                  controller: rgbHexTextEditingController,
                  style: TextStyle(color: scheme.onSurface),
                  cursorColor: scheme.primary,
                  onChanged: (value) {
                    final valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);
                    setState(() {
                      _invalidHex = !valid;
                      if (valid) {
                        selectedColor = fromRGBHexString(value)!;
                        _updateWheel = true;
                      }
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Hex RGB',
                    hintText: '#RRGGBB',
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    labelStyle: TextStyle(color: scheme.onSurfaceVariant),
                    floatingLabelStyle: TextStyle(color: scheme.primary),
                    prefixIcon: Icon(Symbols.tag, color: scheme.primary),
                    border: AppShape.inputBorder,
                    enabledBorder: OutlineInputBorder(
                        borderRadius: AppShape.controlRadius,
                        borderSide: BorderSide(color: scheme.outlineVariant)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: AppShape.controlRadius,
                        borderSide:
                            BorderSide(color: scheme.primary, width: 2)),
                    errorText: _invalidHex ? ui('请输入 #RRGGBB 格式的颜色') : null,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(ui('快速选色'),
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final color in presets)
                  Tooltip(
                    message: color == _originalColor
                        ? ui('原主题颜色')
                        : color.toRGBHexString(),
                    child: Semantics(
                      button: true,
                      selected: selectedColor == color,
                      label: color == _originalColor
                          ? ui('原主题颜色')
                          : color.toRGBHexString(),
                      child: InkWell(
                        key: ValueKey('theme-preset-${color.toARGB32()}'),
                        borderRadius: AppShape.smallRadius,
                        onTap: () => _chooseColor(color),
                        child: Container(
                          width: 36,
                          height: 36,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: AppShape.smallRadius,
                            border: Border.all(
                                width: 2,
                                color: selectedColor == color
                                    ? scheme.primary
                                    : Colors.transparent),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(5)),
                            child: selectedColor == color
                                ? Icon(Icons.check,
                                    size: 18,
                                    color: ThemeData.estimateBrightnessForColor(
                                                color) ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
        ),
        actions: [
          AppDialogActions(children: [
            TextButton(
                style: TextButton.styleFrom(foregroundColor: scheme.primary),
                onPressed: () => Navigator.pop(context),
                child: Text(ui('取消'))),
            FilledButton.icon(
                key: const ValueKey('theme-confirm'),
                style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary),
                onPressed: _invalidHex
                    ? null
                    : () => Navigator.pop(context, selectedColor),
                icon: const Icon(Symbols.check, size: 18),
                label: Text(ui('确定'))),
          ])
        ],
      ),
    );
  }
}
