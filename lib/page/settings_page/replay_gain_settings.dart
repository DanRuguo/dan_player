import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class ReplayGainSettings extends StatefulWidget {
  const ReplayGainSettings({super.key});

  @override
  State<ReplayGainSettings> createState() => _ReplayGainSettingsState();
}

class _ReplayGainSettingsState extends State<ReplayGainSettings> {
  String? _error;
  bool _saveFailed = false;
  int _saveGeneration = 0;

  Future<void> _save() async {
    final generation = ++_saveGeneration;
    try {
      await AppSettings.instance.saveSettings(throwOnError: true);
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = null;
          _saveFailed = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = ui('当前会话已应用，但设置保存失败：{0}', [error]);
          _saveFailed = true;
        });
      }
    }
  }

  void _change(ReplayGainPreferences next) {
    ++_saveGeneration;
    if (PlayService.playbackReady.value &&
        !PlayService.instance.playbackService.configureReplayGain(next)) {
      setState(() {
        _error = ui('音量均衡暂时无法应用，原设置已保留。');
        _saveFailed = false;
      });
      return;
    }
    setState(() {
      _error = null;
      _saveFailed = false;
    });
    AppSettings.instance.replayGain.value = next;
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ReplayGainPreferences>(
          valueListenable: AppSettings.instance.replayGain,
          builder: (context, preferences, _) => ReplayGainSettingsPanel(
              preferences: preferences,
              onChanged: _change,
              error: _error,
              onRetrySave: _saveFailed ? () => unawaited(_save()) : null));
}

/// Pure presentation: opening settings does not start a decoder or scan files.
class ReplayGainSettingsPanel extends StatelessWidget {
  const ReplayGainSettingsPanel(
      {super.key,
      required this.preferences,
      required this.onChanged,
      this.error,
      this.onRetrySave});
  final ReplayGainPreferences preferences;
  final ValueChanged<ReplayGainPreferences>? onChanged;
  final String? error;
  final VoidCallback? onRetrySave;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsHeader(
          title: ui('ReplayGain 音量均衡'),
          icon: Icons.graphic_eq,
          subtitle: ui('读取歌曲已有的响度标签，不修改音乐文件；没有标签时保持原音量。')),
      const SizedBox(height: 12),
      AppSegmentedControl<ReplayGainMode>(
          key: const ValueKey('replay-gain-mode'),
          semanticLabel: ui('ReplayGain 音量均衡'),
          value: preferences.mode,
          onChanged: onChanged == null
              ? null
              : (mode) => onChanged!(preferences.copyWith(mode: mode)),
          options: [
            AppSegmentOption(
                value: ReplayGainMode.off,
                label: ui('关闭'),
                icon: Icons.volume_off_outlined),
            AppSegmentOption(
                value: ReplayGainMode.track,
                label: ui('曲目均衡'),
                icon: Icons.music_note_outlined),
            AppSegmentOption(
                value: ReplayGainMode.album,
                label: ui('专辑均衡'),
                icon: Icons.album_outlined),
          ]),
      const SizedBox(height: 8),
      Text(ui('曲目模式平衡歌曲之间的音量；专辑模式保留专辑内部的强弱关系，缺少专辑标签时使用曲目标签。')),
      SettingsSwitchTile(
          surface: false,
          controlKey: const ValueKey('replay-gain-prevent-clipping'),
          contentPadding: SettingsSurface.embeddedRowPadding,
          icon: Icons.multitrack_audio,
          title: Text(ui('依据标签峰值限制增益')),
          subtitle: Text(ui('无峰值标签时不额外放大；此选项不限制均衡器等其他处理产生的峰值。')),
          value: preferences.preventClipping,
          onChanged: onChanged == null || preferences.mode == ReplayGainMode.off
              ? null
              : (value) =>
                  onChanged!(preferences.copyWith(preventClipping: value))),
      if (error != null) ...[
        Text(error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (onRetrySave != null)
          TextButton(onPressed: onRetrySave, child: Text(ui('重试保存'))),
      ],
    ]));
  }
}
