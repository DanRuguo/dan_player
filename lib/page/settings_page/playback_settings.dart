import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/playback_pitch_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// The live adapter does not initialize audio when settings are opened first.
class PlaybackSettings extends StatefulWidget {
  const PlaybackSettings({super.key});

  @override
  State<PlaybackSettings> createState() => _PlaybackSettingsState();
}

class _PlaybackSettingsState extends State<PlaybackSettings> {
  int _saveGeneration = 0;
  String? _saveError;

  Future<void> _save() async {
    final generation = ++_saveGeneration;
    if (mounted) setState(() => _saveError = null);
    try {
      await AppSettings.instance
          .saveSettings(throwOnError: true, captureWindowSize: false);
    } catch (error) {
      if (mounted && generation == _saveGeneration) {
        setState(() => _saveError = ui("当前会话已应用，但设置保存失败：{0}", [error]));
      }
    }
  }

  void _rate(double value) {
    if (PlayService.playbackReady.value) {
      if (!PlayService.instance.playbackService.setPlaybackRate(value)) return;
    } else {
      AppSettings.instance.experience.value =
          AppSettings.instance.experience.value.copyWith(playbackRate: value);
    }
    unawaited(_save());
  }

  void _exclusive(bool value) {
    if (PlayService.playbackReady.value) {
      // Mode switching owns its async transaction and persists only on success.
      PlayService.instance.playbackService.useExclusiveMode(value);
    } else {
      AppSettings.instance.experience.value = AppSettings
          .instance.experience.value
          .copyWith(exclusiveOutput: value);
      unawaited(_save());
    }
  }

  void _pitch(double value) {
    if (PlayService.playbackReady.value) {
      if (!PlayService.instance.playbackService.setPlaybackPitch(value)) return;
    } else {
      AppSettings.instance.experience.value =
          AppSettings.instance.experience.value.copyWith(playbackPitch: value);
    }
    unawaited(_save());
  }

  Widget _panel({required PlayerExperiencePreferences preferences}) {
    final ready = PlayService.playbackReady.value;
    final playback = ready ? PlayService.instance.playbackService : null;
    return PlaybackSettingsPanel(
      playbackRate: playback?.playbackRate.value ?? preferences.playbackRate,
      playbackPitch: playback?.playbackPitch.value ?? preferences.playbackPitch,
      pitchAvailable: playback?.supportsPlaybackPitch ?? true,
      onPitchChanged: _pitch,
      exclusive: playback?.wasapiExclusive.value ?? preferences.exclusiveOutput,
      changingOutput: playback?.isChangingOutput.value ?? false,
      rateAvailable: playback?.supportsPlaybackRate ?? true,
      unavailableReason: playback?.tempoUnavailableReason,
      deferred: !ready || playback?.nowPlaying == null,
      error: _saveError,
      onRateChanged: _rate,
      onExclusiveChanged: _exclusive,
      onRetrySave: () => unawaited(_save()),
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: AppSettings.instance.experience,
      builder: (context, preferences, _) => PlaybackReadyBuilder(
        waitingBuilder: (_) => _panel(preferences: preferences),
        readyBuilder: (_) {
          final playback = PlayService.instance.playbackService;
          return ListenableBuilder(
            listenable: Listenable.merge([
              playback,
              playback.playbackRate,
              playback.playbackPitch,
              playback.wasapiExclusive,
              playback.isChangingOutput,
            ]),
            builder: (_, __) => _panel(preferences: preferences),
          );
        },
      ),
    );
  }
}

/// Pure view for small/large text and capability/error-state regression tests.
class PlaybackSettingsPanel extends StatelessWidget {
  const PlaybackSettingsPanel({
    super.key,
    required this.playbackRate,
    required this.exclusive,
    required this.onRateChanged,
    required this.onExclusiveChanged,
    this.changingOutput = false,
    this.rateAvailable = true,
    this.deferred = false,
    this.unavailableReason,
    this.error,
    this.onRetrySave,
    this.playbackPitch = 0,
    this.pitchAvailable = true,
    this.onPitchChanged,
  });

  final double playbackRate;
  final bool exclusive;
  final ValueChanged<double> onRateChanged;
  final ValueChanged<bool> onExclusiveChanged;
  final bool changingOutput;
  final bool rateAvailable;
  final bool deferred;
  final String? unavailableReason;
  final String? error;
  final VoidCallback? onRetrySave;
  final double playbackPitch;
  final bool pitchAvailable;
  final ValueChanged<double>? onPitchChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final theme = Theme.of(context);
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsHeader(
              title: ui("播放速度"),
              icon: Icons.speed,
              subtitle: rateAvailable
                  ? ui("保音高变速；歌词跟随歌曲进度，听歌时长仍按实际时间统计。")
                  : unavailableReason ?? ui("当前安装缺少倍速组件，仍可正常以 1× 播放。")),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rate in PlaybackRate.presets)
                ChoiceChip(
                  label: Text(PlaybackRate.label(rate)),
                  selected: (playbackRate - rate).abs() < .001,
                  onSelected: rateAvailable ? (_) => onRateChanged(rate) : null,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (onPitchChanged != null) ...[
            SettingsHeader(
                title: ui('升降调'),
                icon: Icons.music_note_outlined,
                subtitle: ui(pitchAvailable
                    ? '独立调整音高，速度和歌词时间不变；选择原调可恢复。'
                    : '当前安装缺少升降调组件，仍可正常播放。')),
            const SizedBox(height: 12),
            PlaybackPitchControl(
                pitch: playbackPitch,
                enabled: pitchAvailable && !changingOutput,
                onChanged: onPitchChanged!),
            const SizedBox(height: 16),
          ],
          SettingsSwitchTile(
            surface: false,
            icon: Icons.speaker_outlined,
            contentPadding: SettingsSurface.embeddedRowPadding,
            title: Text(ui("WASAPI 独占输出")),
            subtitle: Text(changingOutput
                ? ui("正在切换输出模式…")
                : ui("启用后设备可能无法同时播放其他应用的声音；独占不等于一定无重采样。切换失败会尝试恢复原模式。")),
            value: exclusive,
            onChanged: changingOutput ? null : onExclusiveChanged,
          ),
          if (deferred) ...[
            const SizedBox(height: 8),
            Text(ui("尚未播放歌曲，以上设置将在开始播放时应用。")),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: TextStyle(color: theme.colorScheme.error)),
            TextButton(onPressed: onRetrySave, child: Text(ui("重试保存"))),
          ],
        ],
      ),
    );
  }
}

/// Compact shared control for the full player. Settings remain the place for
/// output-mode choices; this control exposes speed and independent pitch.
class PlaybackRateButton extends StatelessWidget {
  const PlaybackRateButton({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playback = PlayService.instance.playbackService;
    return ListenableBuilder(
      listenable: Listenable.merge([
        playback.playbackRate,
        playback.playbackPitch,
        playback.isChangingOutput,
      ]),
      builder: (context, _) => PlaybackRateMenu(
        rate: playback.playbackRate.value,
        pitch: playback.playbackPitch.value,
        pitchEnabled:
            playback.supportsPlaybackPitch && !playback.isChangingOutput.value,
        onPitchSelected: (value) async {
          if (!playback.setPlaybackPitch(value)) return;
          try {
            await AppSettings.instance
                .saveSettings(throwOnError: true, captureWindowSize: false);
          } catch (error) {
            showAppNotice(ui('音高已应用，但设置保存失败：{0}', [error]),
                kind: AppNoticeKind.error);
          }
        },
        enabled: playback.supportsPlaybackRate,
        onSelected: (value) async {
          if (!playback.setPlaybackRate(value)) return;
          try {
            await AppSettings.instance
                .saveSettings(throwOnError: true, captureWindowSize: false);
          } catch (error) {
            showAppNotice(ui("速度已应用，但设置保存失败：{0}", [error]),
                kind: AppNoticeKind.error);
          }
        },
      ),
    );
  }
}

/// A local overlay keeps playback adjustments off the navigator's transition
/// path. The menu has a stable check column and no per-item check animations.
class PlaybackRateMenu extends StatelessWidget {
  const PlaybackRateMenu(
      {super.key,
      required this.rate,
      required this.onSelected,
      this.pitch = 0,
      this.pitchEnabled = true,
      this.onPitchSelected,
      this.enabled = true});
  final double rate;
  final ValueChanged<double> onSelected;
  final bool enabled;
  final double pitch;
  final bool pitchEnabled;
  final ValueChanged<double>? onPitchSelected;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return MenuAnchor(
      style: const MenuStyle(shape: WidgetStatePropertyAll(AppShape.control)),
      menuChildren: [
        for (final value in PlaybackRate.presets)
          MenuItemButton(
            key: ValueKey(('playback-rate', value)),
            onPressed: () => onSelected(value),
            leadingIcon: SizedBox(
                width: 20,
                height: 20,
                child:
                    value == rate ? const Icon(Icons.check, size: 20) : null),
            child: Semantics(
                selected: value == rate,
                child: Text(PlaybackRate.label(value))),
          ),
        if (onPitchSelected != null) ...[
          const Divider(),
          SubmenuButton(
            key: const ValueKey('playback-pitch-submenu'),
            leadingIcon: const Icon(Icons.music_note_outlined),
            menuChildren: pitchEnabled
                ? playbackPitchMenuItems(
                    context: context,
                    pitch: pitch,
                    onSelected: onPitchSelected!)
                : const [],
            child: Text('${ui('升降调')} · ${playbackPitchLabel(pitch)}'),
          ),
        ],
      ],
      builder: (context, controller, _) => Tooltip(
        message: onPitchSelected == null
            ? ui("播放速度（保音高）")
            : '${ui('播放速度与升降调')} · ${playbackPitchLabel(pitch)}',
        child: SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            key: const ValueKey('playback-rate-menu'),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              fixedSize: const Size.square(44),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: enabled
                ? () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  }
                : null,
            icon: PlaybackRateLabel(rate: rate),
          ),
        ),
      ),
    );
  }
}

/// Kept presentation-only so the selected rate remains legible in every
/// generated theme without constructing the native playback service in tests.
class PlaybackRateLabel extends StatelessWidget {
  const PlaybackRateLabel({
    super.key,
    required this.rate,
    this.scheme,
  });

  final double rate;
  final ColorScheme? scheme;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final colors = scheme ?? Theme.of(context).colorScheme;
    return Text(
      PlaybackRate.label(rate),
      style: TextStyle(
        // This control is painted directly on the album-derived player scene.
        // Primary follows the cover/theme; onSurface often collapses to an
        // almost-black neutral and made 1× look unrelated to every icon.
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
