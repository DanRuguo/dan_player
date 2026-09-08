import 'package:dan_player/component/app_shape.dart';
import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_segmented_control.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class TrackResumeSettings extends StatefulWidget {
  const TrackResumeSettings(
      {super.key, this.preferences, this.save, this.clear});
  final ValueNotifier<TrackResumePreferences>? preferences;
  final Future<void> Function()? save;
  final Future<void> Function()? clear;
  @override
  State<TrackResumeSettings> createState() => _TrackResumeSettingsState();
}

class _TrackResumeSettingsState extends State<TrackResumeSettings> {
  String? _error, _notice;
  bool _clearing = false, _saveFailed = false;
  int _saveGeneration = 0;
  ValueNotifier<TrackResumePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.trackResume;

  Future<void> _save() async {
    final generation = ++_saveGeneration;
    try {
      await (widget.save?.call() ??
          AppSettings.instance.saveSettings(throwOnError: true));
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = null;
          _saveFailed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _saveGeneration) {
        setState(() {
          _error = '续播偏好已在本次运行应用，但未能保存，请重试。';
          _saveFailed = true;
        });
      }
    }
  }

  void _change(TrackResumePreferences next) {
    _preferences.value = next;
    setState(() {
      _notice = null;
      _error = null;
      _saveFailed = false;
    });
    unawaited(_save());
  }

  Future<void> _clear() async {
    if (_clearing) return;
    setState(() {
      _clearing = true;
      _error = null;
      _notice = null;
    });
    try {
      if (widget.clear != null) {
        await widget.clear!();
      } else {
        await (await TrackResumeStore.instance).clear();
      }
      if (mounted) setState(() => _notice = '自动记忆位置已清除，手动书签不受影响。');
    } catch (_) {
      if (mounted) setState(() => _error = '无法清除自动记忆位置，请重试。');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TrackResumePreferences>(
        valueListenable: _preferences,
        builder: (context, preferences, _) => TrackResumeSettingsPanel(
          preferences: preferences,
          onChanged: _change,
          onClear: _clearing ? null : () => unawaited(_clear()),
          error: _error,
          notice: _notice,
          onRetrySave: _saveFailed ? () => unawaited(_save()) : null,
        ),
      );
}

/// Opening the controls never constructs a playback service or decoder.
class TrackResumeSettingsPanel extends StatelessWidget {
  const TrackResumeSettingsPanel(
      {super.key,
      required this.preferences,
      required this.onChanged,
      this.onClear,
      this.error,
      this.notice,
      this.onRetrySave});
  final TrackResumePreferences preferences;
  final ValueChanged<TrackResumePreferences>? onChanged;
  final VoidCallback? onClear, onRetrySave;
  final String? error, notice;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsHeader(
          title: ui('按曲记忆播放位置'),
          icon: Icons.history,
          subtitle: ui('再次点选本地音频时从上次位置继续；自动下一首与循环仍从头开始。')),
      const SizedBox(height: 12),
      AppSegmentedControl<TrackResumeMode>(
        key: const ValueKey('track-resume-mode'),
        semanticLabel: ui('按曲记忆播放位置'),
        value: preferences.mode,
        onChanged: onChanged == null
            ? null
            : (mode) => onChanged!(preferences.copyWith(mode: mode)),
        options: [
          AppSegmentOption(
              value: TrackResumeMode.off,
              label: ui('关闭'),
              icon: Icons.do_not_disturb_on_outlined),
          AppSegmentOption(
              value: TrackResumeMode.longAudio,
              label: ui('仅长音频'),
              icon: Icons.headphones_outlined),
          AppSegmentOption(
              value: TrackResumeMode.allLocal,
              label: ui('所有本地音频'),
              icon: Icons.library_music_outlined),
        ],
      ),
      if (preferences.mode == TrackResumeMode.longAudio) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          borderRadius: AppShape.controlRadius,
          elevation: 3,
          dropdownColor: Theme.of(context).colorScheme.surfaceContainerLow,
          key: const ValueKey('track-resume-minimum'),
          initialValue: preferences.minimumMinutes,
          isExpanded: true,
          decoration: InputDecoration(labelText: ui('长音频最短时长')),
          items: [
            for (final minutes in TrackResumePreferences.durationChoices)
              DropdownMenuItem(
                  value: minutes, child: Text(ui('{0} 分钟', [minutes])))
          ],
          onChanged: onChanged == null
              ? null
              : (value) {
                  if (value != null) {
                    onChanged!(preferences.copyWith(minimumMinutes: value));
                  }
                },
        ),
      ],
      const SizedBox(height: 12),
      Text(ui('默认关闭。会话恢复、手动定位和 A–B 循环优先；播完或距结尾不足 10 秒时不续播。')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          key: const ValueKey('track-resume-clear'),
          onPressed: onClear,
          icon: const Icon(Icons.history_toggle_off),
          label: Text(ui('清除自动记忆位置'))),
      if (error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(ui(error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (notice != null)
        Padding(
            padding: const EdgeInsets.only(top: 8), child: Text(ui(notice!))),
      if (onRetrySave != null)
        TextButton(onPressed: onRetrySave, child: Text(ui('重试'))),
    ]));
  }
}
