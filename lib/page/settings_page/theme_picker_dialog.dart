import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_dialog_actions.dart';
import 'package:dan_player/component/app_dialog_title.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    final swatchDuration = AppMotion.duration(
      context,
      MotionKind.feedback,
      AppMotion.quick,
    );
    return Theme(
      data: theme.copyWith(colorScheme: scheme),
      child: AlertDialog(
        scrollable: true,
        backgroundColor: scheme.surface,
        title: AppDialogTitle(
          ui("主题选择器"),
          leading: Icon(Symbols.palette, color: scheme.primary),
          style: theme.textTheme.titleLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: 384,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                key: const ValueKey('theme-color-preview'),
                duration: swatchDuration,
                curve: AppMotion.standardCurve,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppShape.cardRadius,
                  border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .46)),
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14)),
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
                              fontWeight: FontWeight.w700)),
                      Text(ui('主题预览'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  )),
                  const SizedBox(width: 8),
                  Icon(Symbols.play_circle, color: scheme.primary, size: 32),
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
                  wheelSquareBorderRadius: 12,
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: scheme.outlineVariant)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            BorderSide(color: scheme.primary, width: 1.8)),
                    errorText: _invalidHex ? ui('请输入 #RRGGBB 格式的颜色') : null,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(ui('快速选色'),
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
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
                        borderRadius: AppShape.pillRadius,
                        onTap: () => _chooseColor(color),
                        child: AnimatedContainer(
                          duration: swatchDuration,
                          curve: AppMotion.standardCurve,
                          width: 38,
                          height: 38,
                          padding: const EdgeInsets.all(3.5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                width: 2,
                                color: selectedColor == color
                                    ? scheme.primary
                                    : scheme.outlineVariant
                                        .withValues(alpha: .35)),
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                            child: selectedColor == color
                                ? Icon(Icons.check_rounded,
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
