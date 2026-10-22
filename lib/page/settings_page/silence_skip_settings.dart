import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/play_service/silence_skip_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class SilenceSkipSettings extends StatefulWidget {
  const SilenceSkipSettings({super.key, this.preferences, this.persist});
  final ValueNotifier<SilenceSkipPreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<SilenceSkipSettings> createState() => _SilenceSkipSettingsState();
}

class _SilenceSkipSettingsState extends State<SilenceSkipSettings> {
  ValueNotifier<SilenceSkipPreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.silenceSkipping;
  int _revision = 0;
  bool _failed = false;

  Future<void> _save() async {
    final revision = ++_revision;
    final owner = _preferences;
    if (_failed) setState(() => _failed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted && revision == _revision && identical(owner, _preferences)) {
        setState(() => _failed = true);
      }
    }
  }

  void _change(SilenceSkipPreferences value) {
    if (!SettingsSectionVisibility.isVisibleOf(context)) return;
    _preferences.value = value;
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: _preferences,
      builder: (context, preferences, _) => SettingsSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SettingsSwitchTile(
              controlKey: const ValueKey('silence-skip-enabled'),
              surface: false,
              contentPadding: EdgeInsets.zero,
              icon: Icons.skip_next_outlined,
              title: Text(ui('跳过头尾静音')),
              subtitle: Text(ui('下次加载本地歌曲生效；仅分析头尾，保留声音边缘，不改原文件或总时长。')),
              value: preferences.enabled,
              onChanged: (enabled) =>
                  _change(preferences.copyWith(enabled: enabled))),
          if (preferences.enabled) ...[
            const SizedBox(height: 12),
            SettingsTile(
                surface: false,
                description: ui('静音阈值'),
                icon: Icons.graphic_eq,
                action: DropdownButton<double>(
                    key: const ValueKey('silence-skip-threshold'),
                    value: SilenceSkipPreferences.safeThreshold(
                        preferences.thresholdDb),
                    items: [
                      for (final value in <double>{
                        -70,
                        -60,
                        -50,
                        -40,
                        -30,
                        SilenceSkipPreferences.safeThreshold(
                            preferences.thresholdDb)
                      })
                        DropdownMenuItem(
                            value: value,
                            child: Text('${value.toStringAsFixed(0)} dB'))
                    ],
                    onChanged: (value) {
                      if (value != null)
                        _change(
                            _preferences.value.copyWith(thresholdDb: value));
                    })),
            const SizedBox(height: 12),
            SettingsTile(
                surface: false,
                description: ui('每端最多分析'),
                icon: Icons.timer_outlined,
                action: DropdownButton<double>(
                    key: const ValueKey('silence-skip-limit'),
                    value: SilenceSkipPreferences.safeScanSeconds(
                        preferences.scanSeconds),
                    items: [
                      for (final value in <double>{
                        2,
                        5,
                        10,
                        20,
                        30,
                        SilenceSkipPreferences.safeScanSeconds(
                            preferences.scanSeconds)
                      })
                        DropdownMenuItem(
                            value: value,
                            child:
                                Text(ui('{0} 秒', [value.toStringAsFixed(0)])))
                    ],
                    onChanged: (value) {
                      if (value != null)
                        _change(
                            _preferences.value.copyWith(scanSeconds: value));
                    })),
            const SizedBox(height: 12),
            Text(ui('手动定位、A–B 练习或切换输出后，本曲恢复完整范围。在线音频、CUE、短曲、无法精确定位的格式和无法确认的静音边界保持原样；分析超时会回退。启用时自动过渡采用常规切换。'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          if (_failed) SettingsSaveFeedback(onRetry: _save),
        ]),
      ),
    );
  }
}
