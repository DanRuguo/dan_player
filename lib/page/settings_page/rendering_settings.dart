import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class RenderingSettings extends StatelessWidget {
  const RenderingSettings({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RenderingPreferences value;
  final ValueChanged<RenderingPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSwitchTile(
          controlKey: const ValueKey('lyric-spectrum'),
          icon: Icons.graphic_eq,
          title: Text(ui('歌词页实时频谱')),
          subtitle: Text(ui('在歌词详情页播放条上显示频谱音柱；关闭后保留进度条。')),
          value: value.lyricSpectrum,
          onChanged: (v) => onChanged(value.copyWith(lyricSpectrum: v))),
      const SizedBox(height: 16),
      SettingsSwitchTile(
        controlKey: const ValueKey('pause-hidden-visuals'),
        icon: Icons.visibility_off_outlined,
        title: Text(ui('不可见时暂停视觉更新')),
        subtitle: Text(
            ui('暂停隐藏窗口和已打开但不可见页面的歌词视觉、频谱与背景动效；不影响播放。关闭后继续更新已挂载视图，可能增加后台开销。')),
        value: value.pauseWhenHidden,
        onChanged: (enabled) =>
            onChanged(value.copyWith(pauseWhenHidden: enabled)),
      )
    ]);
  }
}
