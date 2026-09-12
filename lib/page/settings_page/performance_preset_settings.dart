import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/performance_preset.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class PerformancePresetSettings extends StatefulWidget {
  const PerformancePresetSettings({super.key, this.controller});
  final PerformancePresetController? controller;
  @override
  State<PerformancePresetSettings> createState() =>
      _PerformancePresetSettingsState();
}

class _PerformancePresetSettingsState extends State<PerformancePresetSettings> {
  bool _busy = false, _failed = false;
  PerformancePresetController get controller =>
      widget.controller ?? AppSettings.instance.performancePresets;
  Future<void> _select(PerformanceMode mode) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await controller.select(mode);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (widget.controller == null)
        ThemeProvider.instance.syncDynamicThemeSetting();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder<PerformancePresetState>(
      valueListenable: controller,
      builder: (context, state, _) => SettingsSurface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsHeader(
              icon: Icons.tune,
              title: ui('性能快捷设置'),
              subtitle: ui('启用前保存原设置；选择“恢复原设置”即可关闭模式并还原。切换模式不会覆盖原设置。')),
          const SizedBox(height: 16),
          AppSegmentedControl<PerformanceMode>(
            key: const ValueKey('performance-preset'),
            value: state.mode,
            semanticLabel: ui('性能快捷设置'),
            onChanged: _busy ? null : _select,
            options: [
              AppSegmentOption(
                  value: PerformanceMode.custom,
                  label: ui('恢复原设置'),
                  icon: Icons.settings_backup_restore),
              AppSegmentOption(
                  value: PerformanceMode.economy,
                  label: ui('一键省电'),
                  icon: Icons.energy_savings_leaf_outlined),
              AppSegmentOption(
                  value: PerformanceMode.performance,
                  label: ui('一键高性能'),
                  icon: Icons.speed),
            ],
          ),
          const SizedBox(height: 12),
          Text(
              ui(switch (state.mode) {
                PerformanceMode.custom => '使用自己的设置。音频播放、文件和联网选项不受快捷模式影响。',
                PerformanceMode.economy =>
                  '最高 30 FPS；关闭频谱、毛玻璃、背景动效、动态配色、歌词回弹和任务栏歌曲预览。隐藏时暂停绘制。',
                PerformanceMode.performance =>
                  '跟随屏幕刷新；启用高档频谱、毛玻璃、背景动效、动态配色、歌词回弹和任务栏歌曲预览。可能增加功耗。',
              }),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (state.mode != PerformanceMode.custom) ...[
            const SizedBox(height: 8),
            Text(ui('模式启用期间仍可手动调整；恢复时会还原这些项目启用前的值。'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_failed)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(ui('设置保存失败，已撤回本次切换；请重试。'),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      )),
    );
  }
}
