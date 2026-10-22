import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class QueueDisplaySettings extends StatefulWidget {
  const QueueDisplaySettings({super.key, this.preferences, this.persist});

  final ValueNotifier<bool>? preferences;
  final Future<void> Function()? persist;

  @override
  State<QueueDisplaySettings> createState() => _QueueDisplaySettingsState();
}

class _QueueDisplaySettingsState extends State<QueueDisplaySettings> {
  bool _failed = false;
  int _revision = 0;
  Future<void> _pendingSave = Future.value();

  ValueNotifier<bool> get _preferences =>
      widget.preferences ?? AppPreference.instance.showQueueUpcoming;

  Future<void> _save() {
    final revision = ++_revision;
    final persist =
        widget.persist ?? () => AppPreference.instance.save(throwOnError: true);
    setState(() => _failed = false);
    // Preserve the order of rapid toggles, including retry after an I/O error.
    return _pendingSave = _pendingSave.then((_) async {
      try {
        await persist();
      } catch (_) {
        if (mounted && revision == _revision) {
          setState(() => _failed = true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _preferences,
          builder: (context, enabled, _) => SettingsSwitchTile(
            controlKey: const ValueKey('queue-upcoming-enabled'),
            icon: Icons.playlist_play_rounded,
            title: Text(ui('显示待播预览')),
            subtitle: Text(ui('在歌词页的队列上方显示接下来播放的歌曲，可展开查看最多 10 项。播放条弹出列表不显示。')),
            value: enabled,
            onChanged: (value) {
              _preferences.value = value;
              unawaited(_save());
            },
          ),
        ),
        if (_failed) SettingsSaveFeedback(onRetry: _save),
      ],
    );
  }
}
