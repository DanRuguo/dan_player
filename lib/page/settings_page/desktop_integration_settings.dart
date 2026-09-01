import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class DesktopIntegrationSettings extends StatefulWidget {
  const DesktopIntegrationSettings(
      {super.key, this.preferences, this.persist, this.integration});

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;
  final DesktopIntegration? integration;

  @override
  State<DesktopIntegrationSettings> createState() =>
      _DesktopIntegrationSettingsState();
}

class _DesktopIntegrationSettingsState
    extends State<DesktopIntegrationSettings> {
  int _saveRevision = 0;
  String? _saveError;
  double? _blurDraft;

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;

  Future<void> _change(PlayerExperiencePreferences next) async {
    final preferences = _preferences;
    if (next == preferences.value) return;
    final revision = ++_saveRevision;
    setState(() => _saveError = null);
    preferences.value = next;
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted &&
          revision == _saveRevision &&
          identical(preferences, _preferences)) {
        setState(() => _saveError = ui("保存桌面设置失败；当前选择仍对本次会话生效。"));
      }
    }
  }

  void _commitBlur(double radius) {
    setState(() => _blurDraft = null);
    // Keep dragging local; persist once on pointer/key/semantics commit. Read
    // the latest model so unrelated changes during the gesture are preserved.
    unawaited(_change(_preferences.value.copyWith(trayMenuBlurRadius: radius)));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final integration = widget.integration ?? DesktopIntegration.instance;
    return ValueListenableBuilder<PlayerExperiencePreferences>(
      valueListenable: _preferences,
      builder: (context, preferences, _) => Column(
        key: const ValueKey('desktop-integration-settings'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSwitchTile(
            controlKey: const ValueKey('close-to-tray-setting'),
            icon: Icons.system_update_alt,
            value: preferences.closeToTray,
            onChanged: (value) =>
                unawaited(_change(preferences.copyWith(closeToTray: value))),
            title: Text(ui("关闭窗口后在后台继续播放")),
            subtitle: Text(ui("隐藏到系统托盘；可从托盘恢复主窗、迷你播放器或真正退出。托盘不可用时正常退出。")),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('taskbar-controls-setting'),
            icon: Icons.skip_next_outlined,
            value: preferences.taskbarControls,
            onChanged: (value) => unawaited(
                _change(preferences.copyWith(taskbarControls: value))),
            title: Text(ui("任务栏缩略图播放控制")),
            subtitle: Text(ui("悬停任务栏图标时显示上一首、播放/暂停和下一首。不在任务栏显示歌词。")),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('taskbar-song-preview-setting'),
            icon: Icons.preview_outlined,
            value: preferences.taskbarSongPreview,
            onChanged: (value) => unawaited(
                _change(preferences.copyWith(taskbarSongPreview: value))),
            title: Text(ui("任务栏歌曲预览")),
            subtitle: Text(ui("小预览显示歌曲卡片；桌面 Peek 按窗口大小放大显示，保持比例。关闭后恢复系统窗口预览。")),
          ),
          const SizedBox(height: 12),
          SettingsSurface(
            child: Builder(builder: (context) {
              final theme = Theme.of(context);
              final radius = _blurDraft ??
                  PlayerExperiencePreferences.safeTrayMenuBlurRadius(
                      preferences.trayMenuBlurRadius);
              final radiusLabel = radius == 0
                  ? ui('关闭')
                  : ui('模糊半径：{0} 逻辑像素', [radius.toStringAsFixed(0)]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsHeader(title: ui('托盘菜单高斯模糊'), icon: Icons.blur_on),
                  const SizedBox(height: 4),
                  Text(radiusLabel,
                      key: const ValueKey('tray-menu-blur-value')),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: theme.colorScheme.primary,
                      thumbColor: theme.colorScheme.primary,
                      valueIndicatorColor: theme.colorScheme.primary,
                      valueIndicatorTextStyle: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onPrimary),
                    ),
                    child: Slider(
                      key: const ValueKey('tray-menu-blur-radius-setting'),
                      value: radius,
                      min: 0,
                      max: PlayerExperiencePreferences.maxTrayMenuBlurRadius,
                      divisions: 24,
                      label: radius.toStringAsFixed(0),
                      semanticFormatterCallback: (_) => radiusLabel,
                      onChanged: (value) => setState(() => _blurDraft = value),
                      onChangeEnd: _commitBlur,
                    ),
                  ),
                  Text(ui('调整真实高斯模糊半径，不改变透明度。0 表示关闭；下次打开菜单时生效。'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(ui('仅使用打开菜单时该菜单范围内的静态背景，关闭即释放，不保存图像。高对比度、透明效果关闭、节能或不可用时自动使用纯色。'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              );
            }),
          ),
          AnimatedBuilder(
            animation: integration,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                integration.previewError != null
                    ? ui(integration.previewError!)
                    : integration.lastError != null
                        ? ui(integration.lastError!)
                        : integration.isAvailable
                            ? ui("系统托盘已就绪；隐藏或最小化时停止非必要界面动画，音乐继续播放。")
                            : ui("系统托盘尚未就绪；不会将播放器隐藏到无法恢复的状态。"),
                key: const ValueKey('desktop-integration-status'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(
                liveRegion: true,
                child: Text(_saveError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        ],
      ),
    );
  }
}
