import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class SimplePlaybackBarPlaylistSettings extends StatefulWidget {
  const SimplePlaybackBarPlaylistSettings({
    super.key,
    this.preferences,
    this.persist,
  });

  final ValueNotifier<UiLayoutPreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<SimplePlaybackBarPlaylistSettings> createState() =>
      _SimplePlaybackBarPlaylistSettingsState();
}

class _SimplePlaybackBarPlaylistSettingsState
    extends State<SimplePlaybackBarPlaylistSettings> {
  bool _failed = false;
  int _revision = 0;

  ValueNotifier<UiLayoutPreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.uiLayout;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<UiLayoutPreferences>(
          valueListenable: _preferences,
          builder: (context, preferences, _) => SettingsSwitchTile(
            controlKey: const ValueKey('simple-playback-bar-playlist'),
            icon: Icons.queue_music,
            title: Text(ui('简易播放条播放列表')),
            subtitle: Text(ui('从播放条向上展开歌曲封面和文件名，滚动浏览，点击播放后收回。')),
            value: preferences.simplePlaybackBarPlaylist,
            onChanged: (enabled) {
              _preferences.value = _preferences.value
                  .copyWith(simplePlaybackBarPlaylist: enabled);
              unawaited(_save());
            },
          ),
        ),
        if (_failed) SettingsSaveFeedback(onRetry: _save),
      ],
    );
  }
}
