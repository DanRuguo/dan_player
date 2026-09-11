import 'package:dan_player/component/app_segmented_control.dart';
import 'package:desktop_lyric/frame_pacing.dart';
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
      SettingsSurface(
          padding: EdgeInsets.zero,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SettingsSwitchTile(
                surface: false,
                controlKey: const ValueKey('lyric-spectrum'),
                icon: Icons.graphic_eq,
                title: Text(ui('歌词页实时频谱')),
                subtitle: Text(ui('在歌词详情页播放条上显示频谱音柱；关闭后保留进度条。')),
                value: value.lyricSpectrum,
                onChanged: (v) => onChanged(value.copyWith(lyricSpectrum: v))),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSegmentedControl<SpectrumDensity>(
                        key: const ValueKey('spectrum-density'),
                        semanticLabel: ui('频谱音柱数量'),
                        value: value.spectrumDensity,
                        onChanged: value.lyricSpectrum
                            ? (density) => onChanged(
                                value.copyWith(spectrumDensity: density))
                            : null,
                        options: [
                          for (final density in SpectrumDensity.values)
                            AppSegmentOption(
                              value: density,
                              label: ui(switch (density) {
                                SpectrumDensity.low => '低',
                                SpectrumDensity.medium => '中',
                                SpectrumDensity.high => '高'
                              }),
                              icon: switch (density) {
                                SpectrumDensity.low =>
                                  Icons.signal_cellular_alt_1_bar,
                                SpectrumDensity.medium =>
                                  Icons.signal_cellular_alt_2_bar,
                                SpectrumDensity.high =>
                                  Icons.signal_cellular_alt
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(ui('低／中／高档最多显示 36／72／112 根音柱，实际数量随窗口宽度调整。档位越高通常越耗 CPU；降低档位时音柱变宽，整体宽度不变。'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ])),
          ])),
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
      ),
      const SizedBox(height: 16),
      _FrameRateSettings(value: value, onChanged: onChanged),
    ]);
  }
}

class _FrameRateSettings extends StatelessWidget {
  const _FrameRateSettings({required this.value, required this.onChanged});
  final RenderingPreferences value;
  final ValueChanged<RenderingPreferences> onChanged;

  @override
  Widget build(BuildContext context) {
    // MediaQuery tracks engine metrics; the native notifier tracks cross-screen moves.
    MediaQuery.sizeOf(context);
    return ValueListenableBuilder<double?>(
      valueListenable: windowDisplayRate,
      builder: (context, nativeHz, _) {
        final hz =
            nativeHz ?? validDisplayRate(View.of(context).display.refreshRate);
        final ceiling = hz.floor();
        final choices = <int>{
          ...[30, 60, 90, 120, 144, 165, 240].where((n) => n <= ceiling),
          ceiling
        }.toList()
          ..sort();
        final preference = value.frameRate;
        final selected = preference.fps.clamp(15, ceiling);
        if (!choices.contains(selected)) {
          choices.add(selected);
          choices.sort();
        }
        void change(FrameRateMode mode, int fps) => onChanged(value.copyWith(
            frameRate: FrameRatePreference(mode: mode, fps: fps)));
        return SettingsSurface(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsHeader(
                icon: Icons.speed,
                title: ui('界面刷新率'),
                subtitle: ui('只控制界面绘制，不改变屏幕设置或音频播放速度。')),
            const SizedBox(height: 12),
            AppSegmentedControl<FrameRateMode>(
              key: const ValueKey('frame-rate-mode'),
              semanticLabel: ui('界面刷新率'),
              value: preference.mode,
              onChanged: (mode) => change(mode, preference.fps),
              options: [
                for (final mode in FrameRateMode.values)
                  AppSegmentOption(
                    value: mode,
                    key: ValueKey('frame-rate-${mode.name}'),
                    label: ui(switch (mode) {
                      FrameRateMode.display => '跟随屏幕',
                      FrameRateMode.adaptive => '自适应刷新',
                      FrameRateMode.fixed => '固定刷新率',
                    }),
                    icon: switch (mode) {
                      FrameRateMode.display => Icons.monitor,
                      FrameRateMode.adaptive => Icons.auto_mode,
                      FrameRateMode.fixed => Icons.speed
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(ui('当前窗口上限：{0} FPS',
                [hz.toStringAsFixed(hz == hz.roundToDouble() ? 0 : 2)])),
            if (preference.mode == FrameRateMode.fixed) ...[
              const SizedBox(height: 8),
              if (choices.length > 1)
                AppSegmentedControl<int>(
                  key: const ValueKey('frame-rate-fps'),
                  value: selected,
                  onChanged: (fps) => change(FrameRateMode.fixed, fps),
                  options: [
                    for (final fps in choices)
                      AppSegmentOption(
                          key: ValueKey('frame-rate-fps-$fps'),
                          value: fps,
                          label: '$fps FPS',
                          icon: Icons.speed)
                  ],
                )
              else
                Text('${choices.single} FPS'),
            ],
            const SizedBox(height: 8),
            Text(
                ui(switch (preference.mode) {
                  FrameRateMode.display => '有画面变化时跟随屏幕刷新，静止时不持续绘制。',
                  FrameRateMode.adaptive =>
                    '交互时跟随屏幕，交互结束后动画最高 48 FPS；静止时不持续绘制。',
                  FrameRateMode.fixed => '动画按所选目标刷新；跨屏时自动受所在屏幕限制。实际帧率也取决于系统负载。',
                }),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ));
      },
    );
  }
}
