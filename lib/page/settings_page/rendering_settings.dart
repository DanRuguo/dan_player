import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:desktop_lyric/frame_pacing.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// Owns visual-preference persistence separately from language and layout.
class VisualEffectsSettings extends StatefulWidget {
  const VisualEffectsSettings({super.key, this.persist});
  final Future<void> Function()? persist;

  @override
  State<VisualEffectsSettings> createState() => _VisualEffectsSettingsState();
}

class _VisualEffectsSettingsState extends State<VisualEffectsSettings> {
  bool _failed = false;
  int _revision = 0;

  Future<void> _save() async {
    final revision = ++_revision;
    setState(() => _failed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ValueListenableBuilder<RenderingPreferences>(
        valueListenable: AppSettings.instance.rendering,
        builder: (context, value, _) => RenderingSettings(
          value: value,
          latestValue: () => AppSettings.instance.rendering.value,
          onChanged: (next) {
            AppSettings.instance.rendering.value = next;
            unawaited(_save());
          },
        ),
      ),
      if (_failed) ...[
        const SizedBox(height: 8),
        Text(ui('保存界面设置失败；本次会话仍然有效。'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _save, child: Text(ui('重试')))),
      ],
    ]);
  }
}

class RenderingSettings extends StatelessWidget {
  const RenderingSettings({
    super.key,
    required this.value,
    required this.onChanged,
    this.latestValue,
  });

  final RenderingPreferences value;
  final ValueChanged<RenderingPreferences> onChanged;

  /// Reads the live model before combining rapid changes in the same frame.
  final RenderingPreferences Function()? latestValue;

  void _update(RenderingPreferences Function(RenderingPreferences) transform) =>
      onChanged(transform(latestValue?.call() ?? value));

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SettingsSwitchTile(
        controlKey: const ValueKey('surface-blur'),
        icon: Icons.blur_on,
        title: Text(ui('界面面板毛玻璃')),
        subtitle: Text(ui('控制播放条、右键及选项菜单等面板的模糊效果；窗口背景单独设置。')),
        value: value.surfaceBlur,
        onChanged: (v) =>
            _update((current) => current.copyWith(surfaceBlur: v)),
      ),
      const SizedBox(height: 16),
      SettingsSwitchTile(
        controlKey: const ValueKey('animated-artwork'),
        icon: Icons.gif_box_outlined,
        title: Text(ui('动态 GIF 封面')),
        subtitle: Text(ui('播放已导入的 GIF 封面；减少动画或关闭封面动画时显示首帧。')),
        value: value.animatedArtwork,
        onChanged: (v) =>
            _update((current) => current.copyWith(animatedArtwork: v)),
      ),
      if (value.animatedArtwork && !value.animations.allows(MotionKind.theme))
        Padding(
          key: const ValueKey('animated-artwork-motion-conflict'),
          padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
          child: Text(
            ui('当前已关闭“主题与封面渐变”，动态 GIF 封面暂时显示首帧；此处开关会保留，重新开启后恢复。'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      const SizedBox(height: 16),
      SettingsSwitchTile(
        controlKey: const ValueKey('cover-contour-glow'),
        icon: Icons.auto_awesome_outlined,
        title: Text(ui('封面轮廓辉光')),
        subtitle: Text(ui('播放页大封面随鼠标局部折射并亮起细线；与分类流光共用交互反馈动画开关，减少动画时停用。')),
        value: value.coverContourGlow,
        onChanged: (v) =>
            _update((current) => current.copyWith(coverContourGlow: v)),
      ),
      if (value.coverContourGlow &&
          !value.animations.allows(MotionKind.feedback))
        Padding(
          key: const ValueKey('cover-contour-glow-motion-conflict'),
          padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
          child: Text(
            ui('当前已关闭“交互反馈动画”，封面轮廓辉光与折射暂时停用；此处开关会保留，重新开启后恢复。'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      const SizedBox(height: 16),
      _FrameRateSettings(value: value, update: _update),
      const SizedBox(height: 16),
      SettingsSurface(
          padding: EdgeInsets.zero,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SettingsHeader(
                  icon: Icons.equalizer,
                  title: ui('频谱显示'),
                  subtitle: ui('分别控制歌词详情页与播放条的音柱，两项互不影响。')),
            ),
            const Divider(height: 1),
            SettingsSwitchTile(
                surface: false,
                controlKey: const ValueKey('lyric-spectrum'),
                icon: Icons.graphic_eq,
                title: Text(ui('歌词页实时频谱')),
                subtitle: Text(ui('音柱可显示在播放条上方或封面四周；关闭后保留进度条。')),
                value: value.lyricSpectrum,
                onChanged: (v) =>
                    _update((current) => current.copyWith(lyricSpectrum: v))),
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: LayoutBuilder(builder: (context, constraints) {
                  final labelStyle = Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      );
                  Widget labeledGroup(String caption, Widget control,
                          {bool stretch = false}) =>
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: stretch
                            ? CrossAxisAlignment.stretch
                            : CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 6),
                            child: Text(caption, style: labelStyle),
                          ),
                          control,
                        ],
                      );
                  final measureStyle = DefaultTextStyle.of(context)
                      .style
                      .merge(Theme.of(context).textTheme.labelLarge)
                      .copyWith(fontWeight: FontWeight.w700);
                  final painter = TextPainter(
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    maxLines: 1,
                  );
                  double measureGroup(
                      String caption, List<String> optionLabels) {
                    var sum = (optionLabels.length - 1) * 2.0 + 8.0;
                    for (final label in optionLabels) {
                      painter.text = TextSpan(text: label, style: measureStyle);
                      painter.layout();
                      sum += math.max(44.0, painter.width.ceilToDouble() + 60.0);
                    }
                    painter.text = TextSpan(text: caption, style: labelStyle);
                    painter.layout();
                    return math.max(sum, painter.width.ceilToDouble() + 8.0);
                  }

                  final placementLabels = [ui('播放条上方'), ui('封面四周')];
                  final styleLabels = [ui('圆头音柱'), ui('像素音柱')];
                  final densityLabels = [
                    for (final density in SpectrumDensity.values)
                      ui(switch (density) {
                        SpectrumDensity.low => '低',
                        SpectrumDensity.medium => '中',
                        SpectrumDensity.high => '高'
                      })
                  ];
                  final placementCaption = ui('频谱显示位置');
                  final styleCaption = ui('频谱样式');
                  final densityCaption = ui('频谱音柱数量');
                  final placementNeed =
                      measureGroup(placementCaption, placementLabels);
                  final styleNeed = measureGroup(styleCaption, styleLabels);
                  final densityNeed =
                      measureGroup(densityCaption, densityLabels);
                  painter.dispose();

                  final placementControl =
                      AppSegmentedControl<LyricSpectrumPlacement>(
                    key: const ValueKey('lyric-spectrum-placement'),
                    semanticLabel: placementCaption,
                    value: value.lyricSpectrumPlacement,
                    onChanged: value.lyricSpectrum
                        ? (placement) => _update((current) => current.copyWith(
                            lyricSpectrumPlacement: placement))
                        : null,
                    options: [
                      AppSegmentOption(
                        value: LyricSpectrumPlacement.progress,
                        label: placementLabels[0],
                        icon: Icons.align_vertical_bottom,
                      ),
                      AppSegmentOption(
                        value: LyricSpectrumPlacement.cover,
                        label: placementLabels[1],
                        icon: Icons.surround_sound_outlined,
                      ),
                    ],
                  );
                  final styleControl = AppSegmentedControl<SpectrumStyle>(
                    key: const ValueKey('spectrum-style'),
                    semanticLabel: styleCaption,
                    wrapCompactLabel: true,
                    value: value.spectrumStyle,
                    onChanged: value.lyricSpectrum
                        ? (style) => _update(
                            (current) => current.copyWith(spectrumStyle: style))
                        : null,
                    options: [
                      AppSegmentOption(
                        value: SpectrumStyle.rounded,
                        label: styleLabels[0],
                        icon: Icons.equalizer,
                      ),
                      AppSegmentOption(
                        value: SpectrumStyle.pixel,
                        label: styleLabels[1],
                        icon: Icons.grid_view,
                      ),
                    ],
                  );
                  final densityControl = AppSegmentedControl<SpectrumDensity>(
                    key: const ValueKey('spectrum-density'),
                    semanticLabel: densityCaption,
                    value: value.spectrumDensity,
                    onChanged: value.lyricSpectrum
                        ? (density) => _update((current) =>
                            current.copyWith(spectrumDensity: density))
                        : null,
                    options: [
                      for (var i = 0; i < SpectrumDensity.values.length; i++)
                        AppSegmentOption(
                          value: SpectrumDensity.values[i],
                          label: densityLabels[i],
                          icon: switch (SpectrumDensity.values[i]) {
                            SpectrumDensity.low =>
                              Icons.signal_cellular_alt_1_bar,
                            SpectrumDensity.medium =>
                              Icons.signal_cellular_alt_2_bar,
                            SpectrumDensity.high => Icons.signal_cellular_alt
                          },
                        ),
                    ],
                  );
                  final threeColumns = placementNeed +
                          styleNeed +
                          densityNeed +
                          24.0 <=
                      constraints.maxWidth;
                  final twoPlusOne = !threeColumns &&
                      placementNeed + styleNeed + 12.0 <= constraints.maxWidth;
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (threeColumns)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: math.max(1, placementNeed.round()),
                                child: labeledGroup(
                                  placementCaption,
                                  placementControl,
                                  stretch: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: math.max(1, styleNeed.round()),
                                child: labeledGroup(
                                  styleCaption,
                                  styleControl,
                                  stretch: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: math.max(1, densityNeed.round()),
                                child: labeledGroup(
                                  densityCaption,
                                  densityControl,
                                  stretch: true,
                                ),
                              ),
                            ],
                          )
                        else if (twoPlusOne) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: math.max(1, placementNeed.round()),
                                child: labeledGroup(
                                  placementCaption,
                                  placementControl,
                                  stretch: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: math.max(1, styleNeed.round()),
                                child: labeledGroup(
                                  styleCaption,
                                  styleControl,
                                  stretch: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          labeledGroup(
                            densityCaption,
                            densityControl,
                            stretch: true,
                          ),
                        ] else ...[
                          labeledGroup(
                            placementCaption,
                            placementControl,
                            stretch: true,
                          ),
                          const SizedBox(height: 10),
                          labeledGroup(
                            styleCaption,
                            styleControl,
                            stretch: true,
                          ),
                          const SizedBox(height: 10),
                          labeledGroup(
                            densityCaption,
                            densityControl,
                            stretch: true,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                            '${ui('样式同时用于播放条上方与封面四周。')} ${ui('低／中／高档最多显示 36／72／112 根音柱，实际数量随可用空间调整。档位越高通常越耗 CPU；降低档位时音柱变宽。')}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        if (value.lyricSpectrumPlacement ==
                            LyricSpectrumPlacement.cover) ...[
                          const SizedBox(height: 6),
                          Text(
                            ui('四周音柱会根据封面留白调整高度；窄窗口未显示封面时，改在播放条上方显示。'),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ],
                      ]);
                })),
            const Divider(height: 1),
            SettingsSwitchTile(
              surface: false,
              controlKey: const ValueKey('compact-spectrum'),
              icon: Icons.bar_chart,
              title: Text(ui('播放条七音频谱')),
              subtitle: Text(ui('关闭后停止播放条的频谱采样与绘制，保留播放控制。')),
              value: value.compactSpectrum,
              onChanged: (v) =>
                  _update((current) => current.copyWith(compactSpectrum: v)),
            ),
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
            _update((current) => current.copyWith(pauseWhenHidden: enabled)),
      ),
    ]);
  }
}

class _FrameRateSettings extends StatelessWidget {
  const _FrameRateSettings({required this.value, required this.update});
  final RenderingPreferences value;
  final void Function(RenderingPreferences Function(RenderingPreferences))
      update;

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
        void changeMode(FrameRateMode mode) => update((current) =>
            current.copyWith(
                frameRate: FrameRatePreference(
                    mode: mode, fps: current.frameRate.fps)));
        void changeFps(int fps) => update((current) => current.copyWith(
            frameRate:
                FrameRatePreference(mode: FrameRateMode.fixed, fps: fps)));
        final scheme = Theme.of(context).colorScheme;
        final ceilingBadge = DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              ui('当前窗口上限：{0} FPS',
                  [hz.toStringAsFixed(hz == hz.roundToDouble() ? 0 : 2)]),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        );
        return SettingsSurface(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final header = SettingsHeader(
                  icon: Icons.speed,
                  title: ui('界面刷新率'),
                  subtitle: ui('只控制界面绘制，不改变屏幕设置或音频播放速度。'));
              final scale = MediaQuery.textScalerOf(context).scale(1);
              if (constraints.maxWidth >= 480 * scale) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: 12),
                    ceilingBadge,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 8),
                  ceilingBadge,
                ],
              );
            }),
            const SizedBox(height: 12),
            AppSegmentedControl<FrameRateMode>(
              key: const ValueKey('frame-rate-mode'),
              semanticLabel: ui('界面刷新率'),
              value: preference.mode,
              onChanged: changeMode,
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
            if (preference.mode == FrameRateMode.fixed) ...[
              const SizedBox(height: 10),
              if (choices.length > 1)
                AppSegmentedControl<int>(
                  key: const ValueKey('frame-rate-fps'),
                  value: selected,
                  onChanged: changeFps,
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
            const SizedBox(height: 10),
            Text(
                ui(switch (preference.mode) {
                  FrameRateMode.display => '有画面变化时跟随屏幕刷新，静止时不持续绘制。',
                  FrameRateMode.adaptive =>
                    '交互时跟随屏幕，交互结束后动画最高 48 FPS；静止时不持续绘制。',
                  FrameRateMode.fixed => '动画按所选目标刷新；跨屏时自动受所在屏幕限制。实际帧率也取决于系统负载。',
                }),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ));
      },
    );
  }
}
