import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Declarative provider capabilities and search switches. Building the settings
/// or changing a switch does not search, probe, log in, or touch saved music.
class MusicSourceSettings extends StatefulWidget {
  const MusicSourceSettings({super.key, this.preferences, this.persist});

  final ValueNotifier<OnlineSourcePreferences>? preferences;
  final Future<void> Function()? persist;

  @override
  State<MusicSourceSettings> createState() => _MusicSourceSettingsState();
}

class _MusicSourceSettingsState extends State<MusicSourceSettings> {
  int _saveRevision = 0;
  String? _saveError;

  ValueNotifier<OnlineSourcePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.onlineSources;

  Future<void> _change(OnlineMusicSource source, bool enabled) async {
    final preferences = _preferences;
    final next = preferences.value.withEnabled(source, enabled);
    if (next == preferences.value) return;
    final revision = ++_saveRevision;
    setState(() => _saveError = null);
    preferences.value = next;
    try {
      await (widget.persist ??
          () => AppSettings.instance.saveSettings(throwOnError: true))();
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(preferences, _preferences)) {
        return;
      }
      setState(() => _saveError = ui("保存歌源设置失败；当前选择仍对本次会话生效。"));
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ValueListenableBuilder(
      valueListenable: _preferences,
      builder: (context, preferences, _) {
        final scheme = Theme.of(context).colorScheme;
        return Column(
          key: const ValueKey('music-source-settings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSurface(
                child: SettingsHeader(
                    title: ui("联网歌源"),
                    icon: Icons.cloud_outlined,
                    subtitle: ui("只影响新的联网搜索。关闭后，不会删除收藏、歌单或队列，也不会中断已有歌曲的播放。"))),
            const SizedBox(height: 12),
            for (final source in OnlineMusicSource.values) ...[
              _SourceCard(
                source: source,
                enabled: preferences.isEnabled(source),
                onChanged: (value) => unawaited(_change(source, value)),
              ),
              const SizedBox(height: 10),
            ],
            Semantics(
              liveRegion: true,
              child: Text(
                preferences.isEmpty
                    ? onlineSourcesDisabledMessage
                    : ui("已启用 {0} 个歌源；新搜索会同时查询已启用的来源。",
                        [preferences.enabledSources.length]),
                key: const ValueKey('music-source-status'),
                style: TextStyle(
                    color: preferences.isEmpty
                        ? scheme.error
                        : scheme.onSurfaceVariant),
              ),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Semantics(
                  liveRegion: true,
                  child:
                      Text(_saveError!, style: TextStyle(color: scheme.error))),
            ],
          ],
        );
      },
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard(
      {required this.source, required this.enabled, required this.onChanged});

  final OnlineMusicSource source;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return SettingsSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSwitchTile(
            surface: false,
            icon: Icons.cloud_queue,
            controlKey: ValueKey('online-source-${source.id}'),
            value: enabled,
            onChanged: onChanged,
            title: Text(ui(source.label)),
            subtitle: Text(enabled ? ui("参与新搜索") : ui("不参与新搜索；已有歌曲仍可播放")),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Capability(
                    icon: Icons.manage_search,
                    text: ui("歌曲搜索；公开可用音源播放；歌词和封面（来源提供时）。")),
                const SizedBox(height: 8),
                _Capability(
                    icon: Icons.file_download_off_outlined,
                    text: ui(
                        "下载未开放：{0}。", [ui(source.downloadUnavailableReason)])),
                const SizedBox(height: 8),
                _Capability(
                    icon: Icons.comment_outlined,
                    text: ui("只读公开评论：需有效平台歌曲 ID，接口可用性由平台决定。")),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}
