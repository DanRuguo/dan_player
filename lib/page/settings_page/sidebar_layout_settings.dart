import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/window_layout_controller.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

class SidebarLayoutSettings extends StatefulWidget {
  const SidebarLayoutSettings({
    super.key,
    this.preferences,
    this.persist,
  });

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<SidebarLayoutSettings> createState() => _SidebarLayoutSettingsState();
}

class _SidebarLayoutSettingsState extends State<SidebarLayoutSettings> {
  String? _error;
  int _revision = 0;

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;

  Future<void> _persist() async {
    final revision = ++_revision;
    setState(() => _error = null);
    try {
      await (widget.persist ??
          () => AppSettings.instance.saveSettings(throwOnError: true))();
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(() => _error = ui("保存侧栏布局失败；当前选择仍对本次会话生效。"));
      }
    }
  }

  void _setWidth(double value, {required bool persist}) {
    final preferences = _preferences;
    final next = preferences.value.copyWith(sidebarWidth: value);
    if (next != preferences.value) preferences.value = next;
    if (persist) unawaited(_persist());
  }

  void _setLocked(bool value) {
    final preferences = _preferences;
    preferences.value = preferences.value.copyWith(sidebarLocked: value);
    unawaited(_persist());
  }

  void _setWindowSizeLocked(bool value) {
    final preferences = _preferences;
    preferences.value = preferences.value.copyWith(windowSizeLocked: value);
    unawaited(_persist());
  }

  void _setWindowAspectRatioLocked(bool value) {
    final preferences = _preferences;
    preferences.value = preferences.value.copyWith(
      windowAspectRatioLocked: value,
      // Capture the live normal-window ratio each time this is enabled.
      windowAspectRatio: value ? 0 : preferences.value.windowAspectRatio,
    );
    unawaited(_persist());
  }

  void _retryWindowLayout() {
    unawaited(WindowLayoutController.instance.apply().catchError(
      (Object error, StackTrace _) {
        if (mounted) setState(() => _error = ui("应用窗口约束失败：{0}", [error]));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<PlayerExperiencePreferences>(
      valueListenable: _preferences,
      builder: (context, preferences, _) => Column(
        key: const ValueKey('sidebar-layout-settings'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsTile(
                  surface: false,
                  description: ui("侧栏宽度"),
                  icon: Symbols.left_panel_open,
                  subtitle: preferences.sidebarWidth <=
                          PlayerExperiencePreferences.compactSidebarThreshold
                      ? ui("图标模式 · {0} px", [preferences.sidebarWidth.round()])
                      : ui("展开模式 · {0} px", [preferences.sidebarWidth.round()]),
                  action: IconButton(
                    key: const ValueKey('sidebar-width-reset'),
                    tooltip: ui("恢复默认侧栏宽度"),
                    onPressed: preferences.sidebarLocked
                        ? null
                        : () => _setWidth(
                              PlayerExperiencePreferences.defaultSidebarWidth,
                              persist: true,
                            ),
                    icon: const Icon(Symbols.restart_alt),
                  ),
                ),
                Slider(
                  key: const ValueKey('sidebar-width-setting'),
                  value: preferences.sidebarWidth,
                  min: PlayerExperiencePreferences.minSidebarWidth,
                  max: PlayerExperiencePreferences.maxSidebarWidth,
                  label: '${preferences.sidebarWidth.round()} px',
                  onChanged: preferences.sidebarLocked
                      ? null
                      : (value) => _setWidth(value, persist: false),
                  onChangeEnd: preferences.sidebarLocked
                      ? null
                      : (value) => _setWidth(value, persist: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('sidebar-width-lock-setting'),
            icon: Symbols.lock,
            value: preferences.sidebarLocked,
            onChanged: _setLocked,
            title: Text(ui("锁定侧栏宽度")),
            subtitle: Text(ui("锁定后关闭主窗口中的拖动调整；窗口缩小时仍会临时收窄，避免遮住主内容。")),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('window-size-lock-setting'),
            icon: Symbols.lock,
            value: preferences.windowSizeLocked,
            onChanged: _setWindowSizeLocked,
            title: Text(ui("锁定窗口大小")),
            subtitle: Text(ui("阻止鼠标改变完整播放器的宽度和高度；迷你播放器切换仍可正常恢复。")),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('window-aspect-ratio-lock-setting'),
            icon: Symbols.aspect_ratio,
            value: preferences.windowAspectRatioLocked,
            onChanged: preferences.windowSizeLocked
                ? null
                : _setWindowAspectRatioLocked,
            title: Text(ui("锁定窗口纵横比")),
            subtitle: Text(preferences.windowSizeLocked
                ? ui("固定窗口大小开启时不能同时锁定纵横比；请先关闭固定大小。")
                : preferences.windowAspectRatioLocked &&
                        preferences.windowAspectRatio > 0
                    ? ui("拖动窗口时保持 {0} : 1。",
                        [preferences.windowAspectRatio.toStringAsFixed(3)])
                    : ui("开启时以当前完整播放器的宽高比为准。")),
          ),
          ListenableBuilder(
            listenable: WindowLayoutController.instance,
            builder: (context, _) {
              final controller = WindowLayoutController.instance;
              if (controller.lastError == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        ui("窗口约束暂未应用，请重试。"),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    TextButton.icon(
                      onPressed:
                          controller.isApplying ? null : _retryWindowLayout,
                      icon: const Icon(Symbols.refresh),
                      label: Text(ui("重试")),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        ],
      ),
    );
  }
}
