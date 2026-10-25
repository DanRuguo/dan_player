import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/component/settings_section_visibility.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// Changing preferences does not construct a decoder or acquire a device.
class PlaybackTransitionSettings extends StatefulWidget {
  const PlaybackTransitionSettings({super.key, this.preferences, this.persist});
  final ValueNotifier<PlaybackTransitionPreferences>? preferences;
  final Future<void> Function()? persist;
  @override
  State<PlaybackTransitionSettings> createState() =>
      _PlaybackTransitionSettingsState();
}

class _PlaybackTransitionSettingsState extends State<PlaybackTransitionSettings>
    with WidgetsBindingObserver {
  int _revision = 0;
  bool _saveFailed = false;
  double? _crossfadeDraft;
  int? _crossfadePointer;
  bool _pointerCycle = false, _ignoreCycle = false;
  PlaybackTransitionPreferences? _crossfadeBase;
  ValueNotifier<PlaybackTransitionPreferences>? _crossfadeOwner;
  bool _sectionVisible = true;
  ValueNotifier<PlaybackTransitionPreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.playbackTransitions;

  void _discardDraft({bool releasePointer = false}) {
    _crossfadeDraft = null;
    _crossfadeBase = null;
    _crossfadeOwner = null;
    // Invalidating a draft does not end the physical gesture that owns it.
    // Its original up/cancel must arrive before another cycle can commit.
    if (releasePointer) {
      _crossfadePointer = null;
    }
    _pointerCycle = _ignoreCycle = false;
  }

  bool get _draftCurrent =>
      identical(_crossfadeOwner, _preferences) &&
      _crossfadeBase == _preferences.value;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sectionVisible = SettingsSectionVisibility.isVisibleOf(context);
    if (!_sectionVisible || !TickerMode.valuesOf(context).enabled) {
      _discardDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PlaybackTransitionSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preferences, widget.preferences)) _discardDraft();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        state != AppLifecycleState.inactive) {
      setState(_discardDraft);
    }
  }

  @override
  void dispose() {
    _discardDraft(releasePointer: true);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _save() async {
    final revision = ++_revision;
    final preferences = _preferences;
    if (_saveFailed) setState(() => _saveFailed = false);
    try {
      await (widget.persist ??
          () => AppSettings.instance
              .saveSettings(throwOnError: true, captureWindowSize: false))();
    } catch (_) {
      if (mounted &&
          revision == _revision &&
          identical(preferences, _preferences)) {
        setState(() => _saveFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
        valueListenable: _preferences,
        builder: (context, preferences, _) => SettingsSurface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  SettingsTile(
                      surface: false,
                      description: ui('歌曲过渡'),
                      icon: Icons.compare_arrows_rounded,
                      subtitle: ui(
                          '下次加载歌曲生效。连续输出预先准备当前队列的下一首本地歌曲；手动切歌、定位、A–B 循环和停止目标沿用原行为。'),
                      action: AppSegmentedControl<PlaybackTransitionMode>(
                          key: const ValueKey('playback-transition-mode'),
                          value: preferences.mode,
                          maxWidth: 420,
                          wrapCompactLabel: true,
                          semanticLabel: ui('歌曲过渡'),
                          options: [
                            AppSegmentOption(
                                value: PlaybackTransitionMode.standard,
                                label: ui('常规切换'),
                                icon: Icons.skip_next_outlined),
                            AppSegmentOption(
                                value: PlaybackTransitionMode.gapless,
                                label: ui('连续输出'),
                                icon: Icons.link_outlined),
                            AppSegmentOption(
                                value: PlaybackTransitionMode.crossfade,
                                label: ui('交叉淡入淡出'),
                                icon: Icons.merge_outlined),
                          ],
                          onChanged: (mode) {
                            if (!_sectionVisible) return;
                            _discardDraft();
                            _preferences.value =
                                _preferences.value.copyWith(mode: mode);
                            unawaited(_save());
                          })),
                  ValueListenableBuilder(
                    valueListenable: AppSettings.instance.silenceSkipping,
                    builder: (context, silence, _) => silence.enabled &&
                            preferences.enabled
                        ? Padding(
                            key: const ValueKey(
                                'playback-transition-silence-conflict'),
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                ui(
                                    '已启用“跳过头尾静音”，自动过渡当前使用常规切换。此处选择会保留；关闭跳过静音后，后续歌曲可使用所选过渡。'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)))
                        : const SizedBox.shrink(),
                  ),
                  if (preferences.mode == PlaybackTransitionMode.crossfade) ...[
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1)),
                    SettingsSwitchTile(
                        controlKey:
                            const ValueKey('playback-same-album-gapless'),
                        surface: false,
                        contentPadding: EdgeInsets.zero,
                        icon: Icons.album_outlined,
                        title: Text(ui('同专辑保持连续输出')),
                        subtitle: Text(ui(
                            '自动播放同一专辑时保留曲目衔接，跨专辑仍淡入淡出。专辑名或艺术家信息不完整时沿用淡入淡出。')),
                        value: preferences.skipSameAlbumCrossfade,
                        onChanged: (skip) {
                          if (!_sectionVisible) return;
                          _discardDraft();
                          _preferences.value = _preferences.value
                              .copyWith(skipSameAlbumCrossfade: skip);
                          unawaited(_save());
                        }),
                    const SizedBox(height: 16),
                    SettingsHeader(
                        icon: Icons.timer_outlined,
                        title: ui('淡入淡出时长：{0} 秒', [
                          (_draftCurrent
                                  ? _crossfadeDraft ??
                                      preferences.crossfadeSeconds
                                  : preferences.crossfadeSeconds)
                              .toStringAsFixed(1)
                        ])),
                    const SizedBox(height: 10),
                    Listener(
                        onPointerDown: (event) {
                          if (_sectionVisible) {
                            _crossfadePointer ??= event.pointer;
                          }
                        },
                        onPointerUp: (event) {
                          if (_crossfadePointer == event.pointer) {
                            _crossfadePointer = null;
                          }
                        },
                        onPointerCancel: (event) {
                          if (_crossfadePointer == event.pointer) {
                            setState(() => _discardDraft(releasePointer: true));
                          }
                        },
                        child: Slider(
                            key: const ValueKey('playback-crossfade-seconds'),
                            min: 0.5,
                            max: 12,
                            divisions: 23,
                            value: PlaybackTransitionPreferences.safeSeconds(
                                _draftCurrent
                                    ? _crossfadeDraft ??
                                        preferences.crossfadeSeconds
                                    : preferences.crossfadeSeconds),
                            onChangeStart: (_) {
                              if (!_sectionVisible) return;
                              if (_pointerCycle) {
                                _ignoreCycle = true;
                                return;
                              }
                              _pointerCycle = _crossfadePointer != null;
                              _crossfadeOwner = _preferences;
                              _crossfadeBase = preferences;
                            },
                            onChanged: (seconds) {
                              if (_sectionVisible &&
                                  _draftCurrent &&
                                  !_ignoreCycle) {
                                setState(() => _crossfadeDraft = seconds);
                              }
                            },
                            onChangeEnd: (seconds) {
                              if (_ignoreCycle) {
                                _ignoreCycle = false;
                                return;
                              }
                              // Slider also ends interactions when the parent
                              // scroll view wins its gesture arena. A semantic
                              // action can finish before the physical drag has
                              // even started. Neither may commit or release the
                              // still-held primary pointer.
                              if (_crossfadePointer != null) {
                                setState(_discardDraft);
                                return;
                              }
                              _pointerCycle = false;
                              if (!_sectionVisible ||
                                  !_draftCurrent ||
                                  !TickerMode.valuesOf(context).enabled) {
                                setState(_discardDraft);
                                return;
                              }
                              final owner = _preferences;
                              setState(_discardDraft);
                              owner.value = owner.value
                                  .copyWith(crossfadeSeconds: seconds);
                              unawaited(_save());
                            })),
                    const SizedBox(height: 8),
                    Text(ui('仅共享输出混合两曲；独占输出使用连续接续。短曲自动缩短过渡，在线音频、CUE 分轨或未能预备的歌曲使用常规切换。'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                  if (_saveFailed) ...[
                    const SizedBox(height: 12),
                    Text(ui('设置保存失败，请重试'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                    TextButton(onPressed: _save, child: Text(ui('重试保存'))),
                  ],
                ])));
  }
}
