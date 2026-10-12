import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_control.dart';
import 'package:desktop_lyric/component/lyric_letter_spacing_preview.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:material_symbols_icons/symbols.dart';

const _lyricSettingsDivider = Padding(
    padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1));

/// Pure preference UI: opening these controls never constructs a player or
/// starts the desktop lyric process. An existing process observes the change.
class LyricExperienceSettings extends StatefulWidget {
  const LyricExperienceSettings(
      {super.key,
      this.preferences,
      this.persist,
      this.appearance,
      this.japaneseReadings});

  final ValueNotifier<PlayerExperiencePreferences>? preferences;
  final Future<void> Function()? persist;
  final ValueNotifier<DesktopLyricAppearance>? appearance;
  final ValueNotifier<JapaneseReadingPreferences>? japaneseReadings;

  @override
  State<LyricExperienceSettings> createState() =>
      _LyricExperienceSettingsState();
}

class _LyricExperienceSettingsState extends State<LyricExperienceSettings> {
  int _saveRevision = 0;
  bool _saveFailed = false;
  int? _japaneseReadingPointer;
  bool _japaneseReadingPointerCancelling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pointer = _japaneseReadingPointer;
    if (!SettingsSectionVisibility.isVisibleOf(context) &&
        pointer != null &&
        !_japaneseReadingPointerCancelling) {
      _japaneseReadingPointerCancelling = true;
      // GestureBinding queues cancellation after this build. Disabling a
      // held Material Switch here would synchronously cancel its recognizer
      // and make the SDK's reaction callback call setState during build.
      WidgetsBinding.instance.cancelPointer(pointer);
    }
  }

  @override
  void dispose() {
    _japaneseReadingPointer = null;
    _japaneseReadingPointerCancelling = false;
    super.dispose();
  }

  ValueNotifier<PlayerExperiencePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.experience;
  ValueNotifier<DesktopLyricAppearance> get _appearance =>
      widget.appearance ?? AppSettings.instance.desktopLyricAppearance;
  ValueNotifier<JapaneseReadingPreferences> get _japaneseReadings =>
      widget.japaneseReadings ?? AppSettings.instance.japaneseReadings;

  Future<void> _save() async {
    final revision = ++_saveRevision;
    final preferences = _preferences;
    final appearance = _appearance;
    final readings = _japaneseReadings;
    setState(() => _saveFailed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(preferences, _preferences) ||
          !identical(appearance, _appearance) ||
          !identical(readings, _japaneseReadings)) {
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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsHeader(
                      title: ui("歌词体验"), icon: Icons.lyrics_outlined),
                  const SizedBox(height: 16),
                  SettingsSwitchTile(
                    surface: false,
                    contentPadding: EdgeInsets.zero,
                    icon: Icons.waves_outlined,
                    controlKey: const ValueKey('spring-lyrics-switch'),
                    title: Text(ui("歌词弹性滚动")),
                    subtitle: Text(ui("逐句跟随时轻微回弹；跳转保持平稳。系统减少动画时不启用。")),
                    value: preferences.springLyrics,
                    onChanged: (value) => _change(
                        _preferences.value.copyWith(springLyrics: value)),
                  ),
                  _lyricSettingsDivider,
                  SettingsSwitchTile(
                    surface: false,
                    contentPadding: EdgeInsets.zero,
                    icon: Icons.vertical_split_outlined,
                    controlKey: const ValueKey('desktop-lyric-vertical-switch'),
                    title: Text(ui("桌面歌词竖排")),
                    subtitle: Text(ui("文字从上到下排列，译文分列；仅改变桌面歌词，不会自动打开歌词窗口。")),
                    value: preferences.desktopLyricVertical,
                    onChanged: (value) => _change(_preferences.value
                        .copyWith(desktopLyricVertical: value)),
                  ),
                  _lyricSettingsDivider,
                  ValueListenableBuilder(
                    valueListenable: _appearance,
                    builder: (context, appearance, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LyricLetterSpacingControl(
                          id: 'settings-lyric-letter-spacing',
                          visible:
                              SettingsSectionVisibility.isVisibleOf(context),
                          value: appearance.lyricLetterSpacing,
                          heading: SettingsHeader(
                              title: ui('歌词字间距'),
                              icon: Symbols.format_letter_spacing,
                              subtitle: ui('增加主歌词、桌面歌词和任务栏歌词的自然字距；0 保持原样。')),
                          previewBuilder: (context, value) =>
                              LyricLetterSpacingPreview(
                                  value: value,
                                  text: ui('音乐伴每一天'),
                                  visible:
                                      SettingsSectionVisibility.isVisibleOf(
                                          context)),
                          onChanged: (value) {
                            final next = _appearance.value
                                .copyWith(lyricLetterSpacing: value);
                            if (next == _appearance.value) return;
                            _appearance.value = next;
                            unawaited(_save());
                          },
                        ),
                      ],
                    ),
                  ),
                  _lyricSettingsDivider,
                  ValueListenableBuilder(
                    valueListenable: _japaneseReadings,
                    builder: (context, readings, _) {
                      final visible =
                          SettingsSectionVisibility.isVisibleOf(context);
                      return Listener(
                        onPointerDown: (event) {
                          if (_japaneseReadingPointer == null) {
                            _japaneseReadingPointer = event.pointer;
                            _japaneseReadingPointerCancelling = false;
                          }
                        },
                        onPointerUp: (event) {
                          if (event.pointer == _japaneseReadingPointer) {
                            _japaneseReadingPointer = null;
                            _japaneseReadingPointerCancelling = false;
                          }
                        },
                        onPointerCancel: (event) {
                          if (event.pointer == _japaneseReadingPointer) {
                            _japaneseReadingPointer = null;
                            _japaneseReadingPointerCancelling = false;
                          }
                        },
                        child: SettingsSwitchTile(
                          surface: false,
                          contentPadding: EdgeInsets.zero,
                          icon: Icons.translate_outlined,
                          controlKey:
                              const ValueKey('japanese-reading-auto-switch'),
                          title: Text(ui('自动生成日语假名')),
                          subtitle: ValueListenableBuilder<bool>(
                              valueListenable:
                                  AppSettings.instance.automaticOnlineLyrics,
                              builder: (context, automatic, _) => Text(
                                  '${ui('优先显示已缓存的假名；未缓存时，自动联网开启则优先联网并在失败时回退离线，关闭则使用离线字典。保留已有注音和原歌词。')}'
                                  '${readings.enabled && !automatic ? '\n\n${ui('自动联网已关闭，可在阅读工具勾选显示日语假名；联网生成与字典安装请使用下方设置。')}' : ''}')),
                          value: readings.enabled,
                          onChanged: (value) {
                            if (!mounted ||
                                !visible ||
                                _japaneseReadingPointer != null ||
                                !SettingsSectionVisibility.isVisibleOf(
                                    context)) {
                              return;
                            }
                            setJapaneseReadingGeneration(
                                preferences: _japaneseReadings,
                                appearance: _appearance,
                                enabled: value);
                            unawaited(_save());
                          },
                        ),
                      );
                    },
                  ),
                  _lyricSettingsDivider,
                  SettingsTile(
                    surface: false,
                    description: ui('本地歌词多轨顺序'),
                    subtitle:
                        '${ui('LDDC 可自定义导出顺序。默认保留首行原文及其他译文；选择明确顺序后，下次加载分离注音。已编辑或锁定的歌词不变。')}\n\n${ui('支持本地 TTML 行与逐字歌词；译文和注音按文件中的明确角色读取。')}',
                    icon: Icons.sort_outlined,
                    action: AppSegmentedControl<LocalLyricLineOrder>(
                      key: const ValueKey('local-lyric-line-order'),
                      maxWidth: 280,
                      value: AppSettings.instance.localLyricLineOrder,
                      semanticLabel: ui('本地歌词多轨顺序'),
                      options: [
                        AppSegmentOption(
                            value: LocalLyricLineOrder.automatic,
                            label: ui('自动 · 原文/译文'),
                            icon: Icons.auto_awesome_outlined),
                        AppSegmentOption(
                            value: LocalLyricLineOrder
                                .originalTranslationRomanization,
                            label: ui('原文/译文/注音'),
                            icon: Icons.notes_outlined),
                        AppSegmentOption(
                            value: LocalLyricLineOrder
                                .romanizationOriginalTranslation,
                            label: ui('注音/原文/译文'),
                            icon: Icons.text_fields_outlined),
                      ],
                      onChanged: (value) {
                        setState(() =>
                            AppSettings.instance.localLyricLineOrder = value);
                        unawaited(_save());
                      },
                    ),
                  ),
                  _lyricSettingsDivider,
                  ValueListenableBuilder(
                    valueListenable:
                        AppSettings.instance.nowPlayingProgressStyle,
                    builder: (context, style, _) => Column(children: [
                      SettingsTile(
                        surface: false,
                        description: ui('歌词页进度条'),
                        subtitle: ui('分析当前本地歌曲的振幅，未就绪时显示普通进度条。'),
                        icon: Icons.graphic_eq_outlined,
                        action: AppSegmentedControl<NowPlayingProgressStyle>(
                          key: const ValueKey('now-playing-progress-style'),
                          maxWidth: 280,
                          value: style,
                          semanticLabel: ui('歌词页进度条'),
                          options: [
                            AppSegmentOption(
                                value: NowPlayingProgressStyle.standard,
                                label: ui('默认样式'),
                                icon: Icons.linear_scale),
                            AppSegmentOption(
                                value: NowPlayingProgressStyle.waveform,
                                label: ui('音频波形'),
                                icon: Icons.graphic_eq),
                          ],
                          onChanged: (value) {
                            AppSettings.instance.nowPlayingProgressStyle.value =
                                value;
                            unawaited(_save());
                          },
                        ),
                      ),
                      if (style == NowPlayingProgressStyle.waveform) ...[
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        ValueListenableBuilder(
                          valueListenable:
                              AppSettings.instance.waveformBarDensity,
                          builder: (context, density, _) => SettingsTile(
                            surface: false,
                            description: ui('波形音柱密度'),
                            subtitle: ui(
                                '自适应保持音柱宽度；少量、中等、密集分别显示 48、96、192 根音柱，随进度条宽度缩放。'),
                            icon: Icons.view_week_outlined,
                            action: AppSegmentedControl<WaveformBarDensity>(
                              key: const ValueKey('waveform-bar-density'),
                              maxWidth: 280,
                              value: density,
                              semanticLabel: ui('波形音柱密度'),
                              options: [
                                AppSegmentOption(
                                    value: WaveformBarDensity.automatic,
                                    label: ui('自适应'),
                                    icon: Icons.fit_screen_outlined),
                                AppSegmentOption(
                                    value: WaveformBarDensity.sparse,
                                    label: ui('少量'),
                                    icon: Icons.view_column_outlined),
                                AppSegmentOption(
                                    value: WaveformBarDensity.medium,
                                    label: ui('中等'),
                                    icon: Icons.view_week_outlined),
                                AppSegmentOption(
                                    value: WaveformBarDensity.dense,
                                    label: ui('密集'),
                                    icon: Icons.density_small_outlined),
                              ],
                              onChanged: (value) {
                                AppSettings.instance.waveformBarDensity.value =
                                    value;
                                unawaited(_save());
                              },
                            ),
                          ),
                        ),
                      ],
                    ]),
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
