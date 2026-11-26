import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/lyric/english_phonetic_preferences.dart';
import 'package:dan_player/lyric/japanese_reading_preferences.dart';
import 'package:dan_player/page/settings_page/english_phonetic_batch_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/japanese_online_reading_settings.dart';
import 'package:dan_player/page/settings_page/japanese_reading_batch_settings.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

const _annotationDivider = Padding(
  padding: EdgeInsets.symmetric(vertical: 12),
  child: Divider(height: 1),
);

/// Unified surface consolidating Japanese Furigana and English IPA Phonetics
/// switches, display style, online credentials, and offline/batch tools.
class LyricAnnotationSettings extends StatefulWidget {
  const LyricAnnotationSettings({
    super.key,
    this.appearance,
    this.japaneseReadings,
    this.englishPhonetics,
    this.persist,
  });

  final ValueNotifier<DesktopLyricAppearance>? appearance;
  final ValueNotifier<JapaneseReadingPreferences>? japaneseReadings;
  final ValueNotifier<EnglishPhoneticPreferences>? englishPhonetics;
  final Future<void> Function()? persist;

  @override
  State<LyricAnnotationSettings> createState() =>
      _LyricAnnotationSettingsState();
}

class _LyricAnnotationSettingsState extends State<LyricAnnotationSettings> {
  int _saveRevision = 0;
  bool _saveFailed = false;
  int? _japaneseReadingPointer;
  bool _japaneseReadingPointerCancelling = false;
  int? _englishPhoneticPointer;
  bool _englishPhoneticPointerCancelling = false;

  ValueNotifier<DesktopLyricAppearance> get _appearance =>
      widget.appearance ?? AppSettings.instance.desktopLyricAppearance;
  ValueNotifier<JapaneseReadingPreferences> get _japaneseReadings =>
      widget.japaneseReadings ?? AppSettings.instance.japaneseReadings;
  ValueNotifier<EnglishPhoneticPreferences> get _englishPhonetics =>
      widget.englishPhonetics ?? AppSettings.instance.englishPhonetics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pointer = _japaneseReadingPointer;
    if (!SettingsSectionVisibility.isVisibleOf(context) &&
        pointer != null &&
        !_japaneseReadingPointerCancelling) {
      _japaneseReadingPointerCancelling = true;
      WidgetsBinding.instance.cancelPointer(pointer);
    }
    final enPointer = _englishPhoneticPointer;
    if (!SettingsSectionVisibility.isVisibleOf(context) &&
        enPointer != null &&
        !_englishPhoneticPointerCancelling) {
      _englishPhoneticPointerCancelling = true;
      WidgetsBinding.instance.cancelPointer(enPointer);
    }
  }

  @override
  void dispose() {
    _japaneseReadingPointer = null;
    _japaneseReadingPointerCancelling = false;
    _englishPhoneticPointer = null;
    _englishPhoneticPointerCancelling = false;
    super.dispose();
  }

  Future<void> _save() async {
    final revision = ++_saveRevision;
    final appearance = _appearance;
    final readings = _japaneseReadings;
    final phonetics = _englishPhonetics;
    setState(() => _saveFailed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(appearance, _appearance) ||
          !identical(readings, _japaneseReadings) ||
          !identical(phonetics, _englishPhonetics)) {
        return;
      }
      setState(() => _saveFailed = true);
    }
  }

  Widget _languageSubPanel({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String badge,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.controlRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      key: const ValueKey('lyric-annotation-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsHeader(
                title: ui('歌词注音与音标'),
                icon: Icons.translate_outlined,
                subtitle: ui('集中管理日语假名与英语音标的自动注音、显示样式、联网凭据与批量生成。'),
              ),
              const SizedBox(height: 16),
              _languageSubPanel(
                context: context,
                icon: Icons.translate_outlined,
                title: ui('日语假名注音'),
                badge: ui('联网 + 离线词典'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<JapaneseReadingPreferences>(
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
                            icon: Icons.auto_awesome_outlined,
                            controlKey:
                                const ValueKey('japanese-reading-auto-switch'),
                            title: Text(ui('自动生成日语假名')),
                            subtitle: ValueListenableBuilder<bool>(
                              valueListenable:
                                  AppSettings.instance.automaticOnlineLyrics,
                              builder: (context, automatic, _) => Text(
                                '${ui('优先显示已缓存的假名；未缓存时，自动联网开启则优先联网并在失败时回退离线，关闭则使用离线字典。保留已有注音和原歌词。')}'
                                '${readings.enabled && !automatic ? '\n\n${ui('自动联网已关闭，可在阅读工具勾选显示日语假名；联网生成与字典安装请使用下方设置。')}' : ''}',
                              ),
                            ),
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
                                enabled: value,
                              );
                              unawaited(_save());
                            },
                          ),
                        );
                      },
                    ),
                    _annotationDivider,
                    SettingsTargetAnchor(
                      settingId: 'japanese-online',
                      child: JapaneseOnlineReadingSettings(
                        key: const ValueKey('setting-japanese-online'),
                        surface: false,
                        preferences: _japaneseReadings,
                        persist: widget.persist,
                      ),
                    ),
                    _annotationDivider,
                    SettingsTargetAnchor(
                      settingId: 'japanese-batch',
                      child: JapaneseReadingBatchSettings(
                        key: const ValueKey('setting-japanese-batch'),
                        surface: false,
                        preferences: _japaneseReadings,
                        persist: widget.persist,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _languageSubPanel(
                context: context,
                icon: Icons.spellcheck_outlined,
                title: ui('英语单词音标'),
                badge: ui('内置离线词库'),
                child: ValueListenableBuilder<EnglishPhoneticPreferences>(
                  valueListenable: _englishPhonetics,
                  builder: (context, phonetics, _) {
                    final visible =
                        SettingsSectionVisibility.isVisibleOf(context);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Listener(
                          onPointerDown: (event) {
                            if (_englishPhoneticPointer == null) {
                              _englishPhoneticPointer = event.pointer;
                              _englishPhoneticPointerCancelling = false;
                            }
                          },
                          onPointerUp: (event) {
                            if (event.pointer == _englishPhoneticPointer) {
                              _englishPhoneticPointer = null;
                              _englishPhoneticPointerCancelling = false;
                            }
                          },
                          onPointerCancel: (event) {
                            if (event.pointer == _englishPhoneticPointer) {
                              _englishPhoneticPointer = null;
                              _englishPhoneticPointerCancelling = false;
                            }
                          },
                          child: SettingsSwitchTile(
                            surface: false,
                            contentPadding: EdgeInsets.zero,
                            icon: Icons.spellcheck_outlined,
                            controlKey:
                                const ValueKey('english-phonetics-auto-switch'),
                            title: Text(ui('自动生成英语音标')),
                            subtitle: Text(
                              ui('离线匹配英语单词音标并显示在歌词上方，支持词形变化与常见缩写；保留已有注音和原歌词。'),
                            ),
                            value: phonetics.enabled,
                            onChanged: (value) {
                              if (!mounted ||
                                  !visible ||
                                  _englishPhoneticPointer != null ||
                                  !SettingsSectionVisibility.isVisibleOf(
                                      context)) {
                                return;
                              }
                              setEnglishPhoneticGeneration(
                                preferences: _englishPhonetics,
                                appearance: _appearance,
                                enabled: value,
                              );
                              unawaited(_save());
                            },
                          ),
                        ),
                        _annotationDivider,
                        SettingsTile(
                          surface: false,
                          description: ui('英语音标样式'),
                          subtitle: ui('切换音标显示边框样式，切换后立即生效且无需重新生成缓存。'),
                          icon: Icons.text_format_outlined,
                          action: AppSegmentedControl<EnglishPhoneticStyle>(
                            key: const ValueKey('english-phonetics-style'),
                            value: phonetics.style,
                            semanticLabel: ui('英语音标样式'),
                            options: [
                              AppSegmentOption(
                                value: EnglishPhoneticStyle.plain,
                                label: ui('纯音标'),
                                icon: Icons.short_text_outlined,
                              ),
                              AppSegmentOption(
                                value: EnglishPhoneticStyle.slashes,
                                label: ui('斜线 /…/'),
                                icon: Icons.code_outlined,
                              ),
                              AppSegmentOption(
                                value: EnglishPhoneticStyle.brackets,
                                label: ui('方括号 […]'),
                                icon: Icons.data_array_outlined,
                              ),
                            ],
                            onChanged: (value) {
                              final next = _englishPhonetics.value
                                  .copyWith(style: value);
                              if (next == _englishPhonetics.value) return;
                              _englishPhonetics.value = next;
                              unawaited(_save());
                            },
                          ),
                        ),
                        _annotationDivider,
                        const SettingsTargetAnchor(
                          settingId: 'english-batch',
                          child: EnglishPhoneticBatchSettings(
                            key: ValueKey('setting-english-batch'),
                            surface: false,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (_saveFailed) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              ui('歌词设置保存失败；当前选择仍在本次会话生效。'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('lyric-annotation-retry'),
              onPressed: () => unawaited(_save()),
              child: Text(ui('重试保存')),
            ),
          ),
        ],
      ],
    );
  }
}
