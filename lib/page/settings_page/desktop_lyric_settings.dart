import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:desktop_lyric/component/desktop_lyric_taskbar_options.dart';
import 'package:desktop_lyric/component/desktop_lyric_appearance_options.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Uses the same immutable preference and options widget as the lyric window.
/// Opening settings never starts playback or creates another helper process.
class DesktopLyricSettings extends StatefulWidget {
  const DesktopLyricSettings(
      {super.key, this.preferences, this.experience, this.persist});
  final ValueNotifier<DesktopLyricAppearance>? preferences;
  final ValueNotifier<PlayerExperiencePreferences>? experience;
  final Future<void> Function()? persist;
  @override
  State<DesktopLyricSettings> createState() => _DesktopLyricSettingsState();
}

class _DesktopLyricSettingsState extends State<DesktopLyricSettings> {
  Timer? _saveTimer;
  String? _error;
  int _revision = 0;
  ValueNotifier<DesktopLyricAppearance> get _preferences =>
      widget.preferences ?? AppSettings.instance.desktopLyricAppearance;
  ValueNotifier<PlayerExperiencePreferences> get _experience =>
      widget.experience ?? AppSettings.instance.experience;

  void _change(DesktopLyricAppearance next) {
    if (!SettingsSectionVisibility.isVisibleOf(context)) return;
    if (next == _preferences.value) return;
    _preferences.value = next;
    ++_revision;
    setState(() => _error = null);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  void _changeVertical(bool vertical) {
    if (!SettingsSectionVisibility.isVisibleOf(context)) return;
    final next = _experience.value.copyWith(desktopLyricVertical: vertical);
    if (next == _experience.value) return;
    _experience.value = next;
    ++_revision;
    setState(() => _error = null);
    unawaited(_save());
  }

  Future<void> _save() async {
    final revision = _revision;
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(captureWindowSize: false, throwOnError: true))();
      if (mounted && revision == _revision) setState(() => _error = null);
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = ui("桌面歌词设置保存失败；本次会话仍然生效。"));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
      child: ValueListenableBuilder(
          valueListenable: _preferences,
          builder: (context, appearance, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsHeader(
                      title: ui("桌面歌词显示"),
                      icon: Icons.subtitles_outlined,
                      subtitle: ui(
                          "对已打开的桌面歌词即时生效；未打开时记住选择，不会自动启动歌词窗口。单行模式停靠当前屏幕工作区底部，不嵌入任务栏；侧边任务栏时仍在屏幕底部显示。")),
                  ValueListenableBuilder<PlayerExperiencePreferences>(
                    valueListenable: _experience,
                    builder: (context, experience, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (experience.taskbarLyrics)
                          Padding(
                            key: const ValueKey(
                                'desktop-lyric-taskbar-conflict'),
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              ui(
                                  '已开启任务栏歌词，桌面歌词与任务栏歌词互斥；此处外观设置会保留，打开桌面歌词时会自动切换。'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SettingsSwitchTile(
                          surface: false,
                          contentPadding: EdgeInsets.zero,
                          icon: Icons.vertical_split_outlined,
                          controlKey: const ValueKey(
                              'desktop-lyric-settings-vertical-switch'),
                          title: Text(ui("桌面歌词竖排")),
                          subtitle: Text(ui(
                              "文字从上到下排列，译文分列；仅改变桌面歌词，不会自动打开歌词窗口。")),
                          value: experience.desktopLyricVertical,
                          onChanged: _changeVertical,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  DesktopLyricAppearanceOptions(
                      appearance: appearance, onChanged: _change),
                  const Divider(height: 32),
                  DesktopLyricTaskbarOptions(
                      appearance: appearance, onChanged: _change),
                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    TextButton.icon(
                        onPressed: () => unawaited(_save()),
                        icon: const Icon(Icons.refresh),
                        label: Text(ui("重试保存"))),
                  ],
                ],
              )),
    );
  }

  @override
  void dispose() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
      unawaited(_save());
    }
    super.dispose();
  }
}
