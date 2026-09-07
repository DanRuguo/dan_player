import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Shared appearance editor for the player settings and the desktop palette.
/// Its owner handles persistence and supplies a scrollable parent when needed.
class DesktopLyricAppearanceOptions extends StatelessWidget {
  const DesktopLyricAppearanceOptions(
      {super.key,
      required this.appearance,
      required this.onChanged,
      this.primaryColor,
      this.foregroundColor});

  final DesktopLyricAppearance appearance;
  final ValueChanged<DesktopLyricAppearance> onChanged;
  final Color? primaryColor;
  final Color? foregroundColor;

  void _change(DesktopLyricAppearance next) {
    if (next != appearance) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final primary = primaryColor ?? scheme.primary;
    final foreground = foregroundColor ?? scheme.onSurface;
    final followingTheme = appearance.customColor == null;
    Widget slider(
            {required String id,
            required String label,
            required double value,
            required double min,
            required double max,
            required ValueChanged<double> onChanged,
            int? divisions,
            bool percentage = false}) =>
        _ValueSlider(
            id: id,
            label: label,
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            valueLabel: percentage
                ? '${(value * 100).round()}%'
                : value == value.roundToDouble()
                    ? '${value.round()}'
                    : value.toStringAsFixed(1),
            primary: primary,
            foreground: foreground,
            onChanged: onChanged);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        slider(
            id: 'desktop-lyric-font-size',
            label: ui("原文字号"),
            value: appearance.lyricFontSize,
            min: 18,
            max: 64,
            divisions: 46,
            onChanged: (value) =>
                _change(appearance.copyWith(lyricFontSize: value))),
        const SizedBox(height: 8),
        slider(
            id: 'desktop-translation-font-size',
            label: ui("译文字号"),
            value: appearance.translationFontSize,
            min: 14,
            max: 60,
            divisions: 46,
            onChanged: (value) =>
                _change(appearance.copyWith(translationFontSize: value))),
        const SizedBox(height: 8),
        slider(
            id: 'desktop-text-opacity',
            label: ui("文字不透明度"),
            value: appearance.textOpacity,
            min: .2,
            max: 1,
            percentage: true,
            onChanged: (value) =>
                _change(appearance.copyWith(textOpacity: value))),
        const SizedBox(height: 8),
        slider(
            id: 'desktop-background-opacity',
            label: ui("背景不透明度"),
            value: appearance.backgroundOpacity,
            min: 0,
            max: 1,
            percentage: true,
            onChanged: (value) =>
                _change(appearance.copyWith(backgroundOpacity: value))),
        SwitchListTile.adaptive(
          key: const ValueKey('desktop-lyric-stroke'),
          contentPadding: EdgeInsets.zero,
          title: Text(ui("文字描边"), style: TextStyle(color: foreground)),
          subtitle: Text(ui("在复杂背景上增加字形对比"),
              style: TextStyle(color: foreground.withValues(alpha: .72))),
          activeThumbColor: primary,
          activeTrackColor: primary.withValues(alpha: .35),
          inactiveThumbColor: foreground.withValues(alpha: .6),
          inactiveTrackColor: foreground.withValues(alpha: .12),
          value: appearance.strokeEnabled,
          onChanged: (value) =>
              _change(appearance.copyWith(strokeEnabled: value)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            key: const ValueKey('desktop-color-follow-theme'),
            onPressed: () => _change(appearance.copyWith(followTheme: true)),
            style: FilledButton.styleFrom(
              backgroundColor: primary.withValues(alpha: .13),
              foregroundColor: primary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(followingTheme ? Symbols.check : Symbols.palette),
            label: Text(followingTheme ? ui("正在跟随播放器主题") : ui("跟随播放器主题"),
                textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 12),
        Text(ui("文字颜色"),
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
        if (!followingTheme)
          Text(_colorLabel(appearance.customColor!),
              key: const ValueKey('desktop-custom-color-value'),
              style: TextStyle(color: foreground.withValues(alpha: .72))),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final color in Colors.primaries)
            _ColorChoice(
              color: color,
              selected: appearance.customColor == color.toARGB32(),
              primary: primary,
              foreground: foreground,
              onTap: () =>
                  _change(appearance.copyWith(customColor: color.toARGB32())),
            ),
        ]),
      ],
    );
  }
}

String _colorLabel(int color) =>
    '#${color.toRadixString(16).padLeft(8, '0').toUpperCase()}';

class _ValueSlider extends StatelessWidget {
  const _ValueSlider(
      {required this.id,
      required this.label,
      required this.valueLabel,
      required this.value,
      required this.min,
      required this.max,
      required this.primary,
      required this.foreground,
      required this.onChanged,
      this.divisions});
  final String id;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final Color primary;
  final Color foreground;
  final ValueChanged<double> onChanged;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: foreground))),
        const SizedBox(width: 8),
        Text(valueLabel,
            key: ValueKey('$id-value'),
            style: TextStyle(color: foreground.withValues(alpha: .72))),
      ]),
      Semantics(
        label: label,
        child: SliderTheme(
          data: SliderThemeData(
            thumbColor: primary,
            overlayColor: primary.withValues(alpha: .08),
            activeTrackColor: primary,
            inactiveTrackColor: primary.withValues(alpha: .15),
            valueIndicatorColor: primary,
            valueIndicatorTextStyle: TextStyle(
                color: ThemeData.estimateBrightnessForColor(primary) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            trackHeight: 4,
          ),
          child: Slider(
            key: ValueKey(id),
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            value: value,
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }
}

class _ColorChoice extends StatelessWidget {
  const _ColorChoice(
      {required this.color,
      required this.selected,
      required this.primary,
      required this.foreground,
      required this.onTap});
  final Color color;
  final bool selected;
  final Color primary;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Semantics(
      button: true,
      selected: selected,
      label: ui("文字颜色 {0}", [_colorLabel(color.toARGB32())]),
      child: Tooltip(
        message: _colorLabel(color.toARGB32()),
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key:
                ValueKey('desktop-color-${color.toARGB32().toRadixString(16)}'),
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: AppMotion.quick,
                  width: 30,
                  height: 30,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: selected
                            ? primary
                            : foreground.withValues(alpha: .24),
                        width: selected ? 2 : 1),
                  ),
                  child: DecoratedBox(
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: color),
                    child: selected
                        ? Icon(Symbols.check,
                            color:
                                ThemeData.estimateBrightnessForColor(color) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                            size: 16)
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
