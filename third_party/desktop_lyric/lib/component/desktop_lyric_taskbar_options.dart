import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// One options UI for both the player settings and the helper's palette.
/// Storage/native geometry remain owned by the respective caller.
class DesktopLyricTaskbarOptions extends StatelessWidget {
  const DesktopLyricTaskbarOptions(
      {super.key,
      required this.appearance,
      required this.onChanged,
      this.primaryColor,
      this.foregroundColor});
  final DesktopLyricAppearance appearance;
  final ValueChanged<DesktopLyricAppearance> onChanged;
  final Color? primaryColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final primary = primaryColor ?? scheme.primary;
    final foreground = foregroundColor ?? scheme.onSurface;
    Widget toggle(
            {required String id,
            required String title,
            required bool enabled,
            required ValueChanged<bool> onChanged,
            String? subtitle}) =>
        SwitchListTile.adaptive(
          key: ValueKey(id),
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: TextStyle(color: foreground)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle,
                  style: TextStyle(color: foreground.withValues(alpha: .72))),
          activeThumbColor: primary,
          activeTrackColor: primary.withValues(alpha: .35),
          inactiveThumbColor: foreground.withValues(alpha: .6),
          inactiveTrackColor: foreground.withValues(alpha: .12),
          value: enabled,
          onChanged: onChanged,
        );
    Widget slider(
            {required String id,
            required String label,
            required double current,
            required double min,
            required double max,
            required ValueChanged<double> onChanged}) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label  ${current.round()}',
              style: TextStyle(color: foreground)),
          SliderTheme(
              data: SliderThemeData(
                activeTrackColor: primary,
                inactiveTrackColor: primary.withValues(alpha: .15),
                thumbColor: primary,
                overlayColor: primary.withValues(alpha: .08),
                valueIndicatorColor: primary,
                valueIndicatorTextStyle: TextStyle(
                    color: primary.computeLuminance() > .45
                        ? Colors.black
                        : Colors.white),
              ),
              child: Slider(
                  key: ValueKey(id),
                  value: current,
                  min: min,
                  max: max,
                  divisions: (max - min).round(),
                  label: '${current.round()}',
                  onChanged: onChanged)),
        ]);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      toggle(
          id: 'desktop-taskbar-mode',
          title: ui("任务栏上方单行歌词"),
          enabled: appearance.taskbarMode,
          onChanged: (value) =>
              onChanged(appearance.copyWith(taskbarMode: value))),
      if (appearance.taskbarMode) ...[
        slider(
            id: 'desktop-taskbar-gap',
            label: ui("任务栏上方间距"),
            current: appearance.taskbarGap,
            min: 0,
            max: 48,
            onChanged: (value) =>
                onChanged(appearance.copyWith(taskbarGap: value))),
        slider(
            id: 'desktop-taskbar-height',
            label: ui("单行高度"),
            current: appearance.taskbarHeight,
            min: 48,
            max: 96,
            onChanged: (value) =>
                onChanged(appearance.copyWith(taskbarHeight: value))),
        slider(
            id: 'desktop-taskbar-minimum-font',
            label: ui("最小字号"),
            current: appearance.taskbarMinimumFontSize,
            min: 12,
            max: 24,
            onChanged: (value) =>
                onChanged(appearance.copyWith(taskbarMinimumFontSize: value))),
        toggle(
            id: 'desktop-taskbar-translation',
            title: ui("优先显示译文"),
            subtitle: ui("无译文时显示原文"),
            enabled: appearance.taskbarTranslation,
            onChanged: (value) =>
                onChanged(appearance.copyWith(taskbarTranslation: value))),
      ],
    ]);
  }
}
