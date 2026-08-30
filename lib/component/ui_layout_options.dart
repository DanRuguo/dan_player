import 'package:dan_player/ui_layout_preferences.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// The caller owns persistence and settings navigation.
class UiLayoutOptions extends StatelessWidget {
  const UiLayoutOptions(
      {super.key, required this.value, required this.onChanged});
  final UiLayoutPreferences value;
  final ValueChanged<UiLayoutPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSurface(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(
                title: ui("音乐列表样式"),
                icon: Icons.view_column_outlined,
                subtitle: ui("分栏显示歌名、作曲家与专辑；窗口较窄时自动使用经典列表。")),
            const SizedBox(height: 8),
            AppSegmentedControl<LibraryRowLayout>(
              value: value.libraryRowLayout,
              semanticLabel: ui('音乐列表样式'),
              options: [
                for (final layout in LibraryRowLayout.values)
                  AppSegmentOption(
                    value: layout,
                    icon: layout == LibraryRowLayout.classic
                        ? Icons.view_list_outlined
                        : Icons.view_column_outlined,
                    label: layout == LibraryRowLayout.classic
                        ? ui('经典列表')
                        : ui('资源管理器分栏'),
                  ),
              ],
              onChanged: (layout) =>
                  onChanged(value.copyWith(libraryRowLayout: layout)),
            ),
          ],
        )),
        const SizedBox(height: 12),
        SettingsSwitchTile(
          icon: Icons.view_compact_outlined,
          title: Text(ui("紧凑歌单")),
          subtitle: Text(ui("收紧歌单标题与卡片间距，保留所有播放、菜单和排序操作。")),
          value: value.compactPlaylists,
          onChanged: (enabled) =>
              onChanged(value.copyWith(compactPlaylists: enabled)),
        ),
      ],
    );
  }
}
