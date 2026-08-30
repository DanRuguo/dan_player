import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Pure preference UI: opening these controls never constructs a player or
/// starts the desktop lyric process. An existing process observes the change.
class LyricExperienceSettings extends StatefulWidget {
  const LyricExperienceSettings({super.key, this.preferences, this.persist});

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<LyricExperienceSettings> createState() =>
      _LyricExperienceSettingsState();
}

class _LyricExperienceSettingsState extends State<LyricExperienceSettings> {
  int _saveRevision = 0;
  bool _saveFailed = false;

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;

  Future<void> _save() async {
    final revision = ++_saveRevision;
    final preferences = _preferences;
    setState(() => _saveFailed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance.saveSettings(throwOnError: true))();
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(preferences, _preferences)) {
        return;
      }
      setState(() => _saveFailed = true);
    }
  }

  void _change(PlayerExperiencePreferences value) {
    if (value == _preferences.value) return;
    _preferences.value = value;
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: _preferences,
      builder: (context, preferences, _) => Column(
        key: const ValueKey('lyric-experience-settings'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSurface(
            padding: EdgeInsets.zero,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: SettingsHeader(
                      title: ui("歌词体验"), icon: Icons.lyrics_outlined)),
              SettingsSwitchTile(
                surface: false,
                icon: Icons.waves_outlined,
                controlKey: const ValueKey('spring-lyrics-switch'),
                title: Text(ui("歌词弹性滚动")),
                subtitle: Text(ui("逐句跟随时轻微回弹；跳转保持平稳。系统减少动画时不启用。")),
                value: preferences.springLyrics,
                onChanged: (value) =>
                    _change(_preferences.value.copyWith(springLyrics: value)),
              ),
              const Divider(height: 1),
              SettingsSwitchTile(
                surface: false,
                icon: Icons.vertical_split_outlined,
                controlKey: const ValueKey('desktop-lyric-vertical-switch'),
                title: Text(ui("桌面歌词竖排")),
                subtitle: Text(ui("文字从上到下排列，译文分列；仅改变桌面歌词，不会自动打开歌词窗口。")),
                value: preferences.desktopLyricVertical,
                onChanged: (value) => _change(
                    _preferences.value.copyWith(desktopLyricVertical: value)),
              ),
            ]),
          ),
          if (_saveFailed) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(ui("歌词设置保存失败；当前选择仍在本次会话生效。"),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            TextButton(
              key: const ValueKey('lyric-experience-retry'),
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                visualDensity: VisualDensity.standard,
              ),
              onPressed: () => unawaited(_save()),
              child: Text(ui("重试保存")),
            ),
          ],
        ],
      ),
    );
  }
}
