import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_menu_anchor.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/app_toolbar_style.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/taskbar_lyrics_preferences.dart';
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
  DesktopIntegration? _layoutIntegration;
  bool _layoutRequested = false;

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;

  @override
  void initState() {
    super.initState();
    _watchLayout();
  }

  @override
  void didUpdateWidget(covariant DesktopIntegrationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.integration != widget.integration) _watchLayout();
  }

  void _watchLayout() {
    _layoutIntegration?.removeListener(_refreshLayoutIfReady);
    _layoutIntegration = widget.integration ?? DesktopIntegration.instance;
    _layoutRequested = false;
    _layoutIntegration!.addListener(_refreshLayoutIfReady);
    _refreshLayoutIfReady();
  }

  void _refreshLayoutIfReady() {
    final integration = _layoutIntegration;
    if (_layoutRequested || integration == null || !integration.isAvailable) {
      return;
    }
    _layoutRequested = true;
    // One passive read once the existing bridge is ready. Subsequent changes
    // arrive through its existing environment event; no polling is needed.
    unawaited(
        integration.refreshTaskbarLyricsLayout().catchError((Object _) {}));
  }

  @override
  void dispose() {
    _layoutIntegration?.removeListener(_refreshLayoutIfReady);
    super.dispose();
  }

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

  void _changeTaskbar(TaskbarLyricsPreferences next) =>
      unawaited(_change(_preferences.value.copyWith(taskbarAppearance: next)));

  Widget _taskbarChoice<T>(BuildContext context,
      {required String id,
      required double width,
      required String description,
      required T selected,
      required Iterable<(T, String)> options,
      required String Function(T) label,
      required ValueChanged<T> onSelected}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: AppMenuAnchor(
        crossAxisUnconstrained: false,
        style: MenuStyle(
          shape: const WidgetStatePropertyAll(AppShape.control),
          maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
        ),
        menuChildren: [
          for (final option in options)
            MenuItemButton(
              key: ValueKey('$id-${option.$2}'),
              autofocus: option.$1 == selected,
              trailingIcon: SizedBox.square(
                dimension: 20,
                child: option.$1 == selected
                    ? const Icon(Icons.check, size: 20)
                    : null,
              ),
              onPressed: () => onSelected(option.$1),
              child: Semantics(
                selected: option.$1 == selected,
                child: Text(label(option.$1)),
              ),
            ),
        ],
        builder: (context, controller, _) => Semantics(
          label: description,
          child: OutlinedButton(
            key: ValueKey(id),
            style: appToolbarControlStyle(context)
                .copyWith(fixedSize: const WidgetStatePropertyAll<Size?>(null)),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(label(selected), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              const Icon(Icons.expand_more, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _taskbarSettings(BuildContext context, DesktopIntegration integration,
      PlayerExperiencePreferences preferences) {
    return SettingsSurface(
      key: const ValueKey('taskbar-lyrics-options-group'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSwitchTile(
            surface: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            controlKey: const ValueKey('taskbar-lyrics-setting'),
            icon: Icons.subtitles_outlined,
            value: preferences.taskbarLyrics,
            onChanged: (value) => unawaited(
                _change(_preferences.value.copyWith(taskbarLyrics: value))),
            title: Text(ui('任务栏歌词')),
            subtitle: Text(ui('在主屏任务栏的空白区域显示当前歌词；开启后关闭桌面歌词，空间不足时自动隐藏。')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: AnimatedBuilder(
              animation: integration,
              builder: (context, _) {
                final areaCount = integration.taskbarLyricsAreaCount;
                final areaIndex = areaCount > 0
                    ? integration.taskbarLyricsAreaIndex.clamp(0, areaCount - 1)
                    : 0;
                String label(TaskbarLyricPosition position) =>
                    switch (position) {
                      TaskbarLyricPosition.auto => ui('自动'),
                      TaskbarLyricPosition.start =>
                        ui(integration.taskbarLyricsVertical ? '靠上' : '靠左'),
                      TaskbarLyricPosition.center => ui('居中'),
                      TaskbarLyricPosition.end =>
                        ui(integration.taskbarLyricsVertical ? '靠下' : '靠右'),
                    };
                return LayoutBuilder(builder: (context, constraints) {
                  final width = constraints.maxWidth.clamp(0.0, 260.0);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _taskbarChoiceRow(
                        context,
                        description: ui('任务栏歌词位置'),
                        icon: Icons.align_horizontal_center,
                        selectedLabel:
                            label(preferences.taskbarAppearance.position),
                        actionWidth: width,
                        action: _taskbarChoice<TaskbarLyricPosition>(
                          context,
                          id: 'taskbar-lyrics-position',
                          width: width,
                          description: ui('任务栏歌词位置'),
                          selected: preferences.taskbarAppearance.position,
                          options: [
                            for (final position in TaskbarLyricPosition.values)
                              (position, position.name),
                          ],
                          label: label,
                          onSelected: (position) => _changeTaskbar(_preferences
                              .value.taskbarAppearance
                              .copyWith(position: position)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(ui('在所选空区内对齐歌词，不遮挡任务栏图标。'),
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              areaCount > 0
                                  ? ui('可用空区：{0}；当前：{1}',
                                      [areaCount, areaIndex + 1])
                                  : preferences.taskbarLyrics
                                      ? ui('暂未检测到可用任务栏空区。')
                                      : ui('开启后检测任务栏空区。'),
                              key: const ValueKey('taskbar-lyrics-area-status'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ),
                          OutlinedButton.icon(
                            key: const ValueKey('taskbar-lyrics-next-area'),
                            style: appToolbarControlStyle(context).copyWith(
                                fixedSize:
                                    const WidgetStatePropertyAll<Size?>(null)),
                            onPressed:
                                preferences.taskbarLyrics && areaCount > 1
                                    ? () => _changeTaskbar(_preferences
                                        .value.taskbarAppearance
                                        .nextArea())
                                    : null,
                            icon: Icon(integration.taskbarLyricsVertical
                                ? Icons.swap_vert
                                : Icons.swap_horiz),
                            label:
                                Text(ui('切换空区'), textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    ],
                  );
                });
              },
            ),
          ),
          SettingsSwitchTile(
            surface: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            controlKey: const ValueKey('taskbar-lyrics-next-lyric'),
            icon: Icons.subject,
            title: Text(ui('显示下一句歌词')),
            value: preferences.taskbarAppearance.showNextLyric,
            onChanged: (value) => _changeTaskbar(_preferences
                .value.taskbarAppearance
                .copyWith(showNextLyric: value)),
          ),
          _taskbarAdvanced(context, preferences),
        ],
      ),
    );
  }

  Widget _taskbarChoiceRow(BuildContext context,
      {required String description,
      required IconData icon,
      required String selectedLabel,
      required double actionWidth,
      required Widget action}) {
    double textWidth(String text, TextStyle? style) {
      final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context))
        ..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final theme = Theme.of(context);
    // Match the existing header (24 + 12) and toolbar label (24 padding,
    // 20 chevron + 8 gap). Measure the current script and text scale rather
    // than forcing every sub-column through SettingsTile's page breakpoint.
    final labelWidth = textWidth(description, theme.textTheme.titleMedium) + 36;
    final buttonWidth =
        (textWidth(selectedLabel, theme.textTheme.labelLarge) + 52)
            .clamp(0.0, actionWidth);
    return LayoutBuilder(builder: (context, constraints) {
      final label = SettingsHeader(title: description, icon: icon);
      if (labelWidth + buttonWidth + 16 <= constraints.maxWidth) {
        return Row(children: [
          Expanded(child: label),
          const SizedBox(width: 16),
          action,
        ]);
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: action),
          ]);
    });
  }

  Widget _taskbarAdvanced(
      BuildContext context, PlayerExperiencePreferences preferences) {
    final reduced = appToolbarReduceMotion(context, kind: MotionKind.layout);
    const rowPadding = EdgeInsets.symmetric(vertical: 6);
    return ExpansionTile(
      key: const ValueKey('taskbar-lyrics-advanced'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expansionAnimationStyle: reduced
          ? AnimationStyle.noAnimation
          : const AnimationStyle(duration: AppMotion.standard),
      leading: Icon(Icons.tune, color: Theme.of(context).colorScheme.primary),
      title: Text(ui('更多任务栏歌词选项')),
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 916 &&
              MediaQuery.textScalerOf(context).scale(1) <= 1.3;
          final columnWidth = twoColumns
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(spacing: 16, runSpacing: 12, children: [
            SizedBox(
              width: columnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ui('外观'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _taskbarChoiceRow(
                    context,
                    description: ui('任务栏歌词配色'),
                    icon: Icons.palette_outlined,
                    selectedLabel: ui(
                        preferences.taskbarAppearance.colorScheme ==
                                TaskbarLyricColorScheme.player
                            ? '播放器配色'
                            : '跟随 Windows 任务栏'),
                    actionWidth: columnWidth.clamp(0.0, 260.0),
                    action: _taskbarChoice<TaskbarLyricColorScheme>(context,
                        id: 'taskbar-lyrics-color-scheme',
                        width: columnWidth.clamp(0.0, 260.0),
                        description: ui('任务栏歌词配色'),
                        selected: preferences.taskbarAppearance.colorScheme,
                        options: [
                          for (final color in TaskbarLyricColorScheme.values)
                            (color, color.name),
                        ],
                        label: (color) => ui(
                            color == TaskbarLyricColorScheme.player
                                ? '播放器配色'
                                : '跟随 Windows 任务栏'),
                        onSelected: (color) => _changeTaskbar(_preferences
                            .value.taskbarAppearance
                            .copyWith(colorScheme: color))),
                  ),
                  const SizedBox(height: 8),
                  SettingsSwitchTile(
                      surface: false,
                      contentPadding: rowPadding,
                      controlKey: const ValueKey('taskbar-lyrics-stroke'),
                      icon: Icons.format_color_text,
                      title: Text(ui('任务栏歌词描边')),
                      subtitle: Text(ui('独立设置，不影响桌面歌词。')),
                      value: preferences.taskbarAppearance.strokeEnabled,
                      onChanged: (value) => _changeTaskbar(_preferences
                          .value.taskbarAppearance
                          .copyWith(strokeEnabled: value))),
                  const SizedBox(height: 4),
                  Text(ui('字体沿用播放器。'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text(ui('显示内容'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SettingsSwitchTile(
                      surface: false,
                      contentPadding: rowPadding,
                      controlKey: const ValueKey('taskbar-lyrics-next-track'),
                      icon: Icons.queue_music,
                      title: Text(ui('下一首歌曲信息')),
                      subtitle: Text(ui('仅显示信息，点击穿透。')),
                      value: preferences.taskbarAppearance.showNextTrack,
                      onChanged: (value) => _changeTaskbar(_preferences
                          .value.taskbarAppearance
                          .copyWith(showNextTrack: value))),
                ],
              ),
            ),
            SizedBox(
              width: columnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ui('交互'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SettingsSwitchTile(
                      surface: false,
                      contentPadding: rowPadding,
                      controlKey:
                          const ValueKey('taskbar-lyrics-pause-indicator'),
                      icon: Icons.play_circle_outline,
                      title: Text(ui('播放/暂停按钮')),
                      subtitle: Text(ui('仅按钮可点击，歌词文字仍可点击穿透。')),
                      value: preferences.taskbarAppearance.showPauseIndicator,
                      onChanged: (value) => _changeTaskbar(_preferences
                          .value.taskbarAppearance
                          .copyWith(showPauseIndicator: value))),
                  SettingsSwitchTile(
                      surface: false,
                      contentPadding: rowPadding,
                      controlKey: const ValueKey('taskbar-lyrics-next-button'),
                      icon: Icons.skip_next,
                      title: Text(ui('下一首按钮')),
                      subtitle: Text(ui('仅按钮可点击，歌词文字仍可点击穿透。')),
                      value: preferences.taskbarAppearance.showNextButton,
                      onChanged: (value) => _changeTaskbar(_preferences
                          .value.taskbarAppearance
                          .copyWith(showNextButton: value))),
                ],
              ),
            ),
          ]);
        }),
      ],
    );
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
            controlKey: const ValueKey('taskbar-controls-setting'),
            icon: Icons.skip_next_outlined,
            value: preferences.taskbarControls,
            onChanged: (value) => unawaited(
                _change(_preferences.value.copyWith(taskbarControls: value))),
            title: Text(ui("任务栏缩略图播放控制")),
            subtitle: Text(ui("悬停任务栏图标时显示上一首、播放/暂停和下一首。")),
          ),
          const SizedBox(height: 12),
          _taskbarSettings(context, integration, preferences),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('taskbar-song-preview-setting'),
            icon: Icons.preview_outlined,
            value: preferences.taskbarSongPreview,
            onChanged: (value) => unawaited(_change(
                _preferences.value.copyWith(taskbarSongPreview: value))),
            title: Text(ui("任务栏歌曲预览")),
            subtitle: Text(ui("小预览显示歌曲卡片；桌面 Peek 按窗口大小放大显示，保持比例。关闭后恢复系统窗口预览。")),
          ),
          const SizedBox(height: 12),
          SettingsSwitchTile(
            controlKey: const ValueKey('taskbar-playback-progress-setting'),
            icon: Icons.linear_scale,
            value: preferences.taskbarPlaybackProgress,
            onChanged: (value) => unawaited(_change(
                _preferences.value.copyWith(taskbarPlaybackProgress: value))),
            title: Text(ui('任务栏播放进度')),
            subtitle: Text(ui('在任务栏图标上显示播放与暂停进度。关闭后仍显示下载、处理任务的进度及加载状态。')),
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
