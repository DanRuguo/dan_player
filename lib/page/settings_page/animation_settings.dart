import 'package:dan_player/app_settings.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

const animationLabels = <MotionKind, (String, String, IconData)>{
  MotionKind.startup: ('开屏动画', '启动时的品牌展示与淡入淡出。', Icons.start),
  MotionKind.nextTrack: ('下一首动画', '添加下一首时，封面飞向播放队列。', Icons.skip_next),
  MotionKind.tracking: ('封面追踪', '切换歌单视图和进入分类详情时，封面移动并改变形状。', Icons.open_with),
  MotionKind.entrance: ('页面浮现', '页面项目首次出现时渐显、上浮或展开。', Icons.auto_awesome),
  MotionKind.transitions: ('页面切换', '页面、内容区与引导步骤之间的过渡。', Icons.swap_horiz),
  MotionKind.layout: (
    '布局与文字动画',
    '封面尺寸、排序、自动填充及标题显隐的过渡。',
    Icons.dashboard_customize_outlined
  ),
  MotionKind.lyrics: ('歌词动画', '歌词滚动与逐字变化；关闭后仍更新当前歌词。', Icons.lyrics_outlined),
  MotionKind.feedback: (
    '交互反馈动画',
    '悬停光效、水波纹、按钮和控件的状态过渡。',
    Icons.touch_app_outlined
  ),
  MotionKind.theme: ('主题与封面渐变', '主题、语言和封面更新时的渐变过渡。', Icons.palette_outlined),
};

class AnimationSettings extends StatefulWidget {
  const AnimationSettings({super.key, this.persist});
  final Future<void> Function()? persist;
  @override
  State<AnimationSettings> createState() => _AnimationSettingsState();
}

class _AnimationSettingsState extends State<AnimationSettings> {
  bool _failed = false;
  int _revision = 0;
  Future<void> _all(bool enabled) async {
    final settings = AppSettings.instance;
    settings.rendering.value = settings.rendering.value
        .copyWith(lyricSpectrum: enabled, compactSpectrum: enabled);
    var backgrounds = settings.backgrounds.value;
    for (final scene in BackgroundScene.values) {
      backgrounds = backgrounds.withScene(
          scene, backgrounds.forScene(scene).copyWith(motion: enabled));
    }
    settings.backgrounds.value = backgrounds;
    settings.experience.value =
        settings.experience.value.copyWith(springLyrics: enabled);
    await _change(settings.rendering.value.animations.all(enabled));
  }

  Future<void> _change(MotionPreferences next) async {
    final revision = ++_revision;
    final preferences = AppSettings.instance.rendering;
    preferences.value = preferences.value.copyWith(animations: next);
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
    return ValueListenableBuilder<RenderingPreferences>(
        valueListenable: AppSettings.instance.rendering,
        builder: (context, rendering, _) {
          final value = rendering.animations;
          return SettingsSurface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                SettingsHeader(
                    icon: Icons.animation,
                    title: ui('动画管理'),
                    subtitle: ui('独立控制每类动画。关闭动画不影响播放、点击、拖动和实时进度。')),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                      key: const ValueKey('animations-all-on'),
                      onPressed: () => _all(true),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(ui('全部开启'))),
                  OutlinedButton.icon(
                      key: const ValueKey('animations-all-off'),
                      onPressed: () => _all(false),
                      icon: const Icon(Icons.pause),
                      label: Text(ui('全部关闭'))),
                ]),
                const SizedBox(height: 8),
                for (final entry in animationLabels.entries)
                  SettingsSwitchTile(
                      surface: false,
                      controlKey: ValueKey('animation-${entry.key.name}'),
                      icon: entry.value.$3,
                      title: Text(ui(entry.value.$1)),
                      subtitle: Text(ui(entry.value.$2)),
                      value: value.allows(entry.key),
                      onChanged: (enabled) =>
                          _change(value.withKind(entry.key, enabled))),
                if (_failed)
                  Text(ui('保存界面设置失败；本次会话仍然有效。'),
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]));
        });
  }
}
