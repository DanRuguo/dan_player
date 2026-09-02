import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/settings_tile.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Declarative provider capabilities and search switches. Building the settings
/// or changing a switch does not search, probe, log in, or touch saved music.
class MusicSourceSettings extends StatefulWidget {
  const MusicSourceSettings(
      {super.key, this.preferences, this.lrclibEnabled, this.persist});

  final ValueNotifier<OnlineSourcePreferences>? preferences;
  final ValueNotifier<bool>? lrclibEnabled;
  final Future<void> Function()? persist;

  @override
  State<MusicSourceSettings> createState() => _MusicSourceSettingsState();
}

class _MusicSourceSettingsState extends State<MusicSourceSettings> {
  int _saveRevision = 0;
  String? _saveError;

  ValueNotifier<OnlineSourcePreferences> get _preferences =>
      widget.preferences ?? AppSettings.instance.onlineSources;

  ValueNotifier<bool> get _lrclibEnabled =>
      widget.lrclibEnabled ?? AppSettings.instance.lrclibEnabled;

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

  Future<void> _changeLrclib(bool enabled) async {
    final notifier = _lrclibEnabled;
    if (notifier.value == enabled) return;
    final revision = ++_saveRevision;
    setState(() => _saveError = null);
    notifier.value = enabled;
    try {
      await (widget.persist ??
          () => AppSettings.instance.saveSettings(throwOnError: true))();
    } catch (_) {
      if (!mounted ||
          revision != _saveRevision ||
          !identical(notifier, _lrclibEnabled)) {
        return;
      }
      setState(() => _saveError = ui('保存歌源设置失败；当前选择仍对本次会话生效。'));
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_preferences, _lrclibEnabled]),
      builder: (context, _) {
        final preferences = _preferences.value;
        final enabledCount =
            preferences.enabledSources.length + (_lrclibEnabled.value ? 1 : 0);
        final scheme = Theme.of(context).colorScheme;
        return Column(
          key: const ValueKey('music-source-settings'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSurface(
                child: SettingsHeader(
                    title: ui('平台直连与公开 API'),
                    icon: Icons.cloud_outlined,
                    subtitle:
                        ui('按标注能力启用联网请求。关闭不会删除收藏、歌单或队列；已有平台歌曲的播放不受搜索开关影响。'))),
            const SizedBox(height: 8),
            Text(
              ui('名称、接口和能力由播放器维护。平台域名不代表官方开放接口、下载授权或长期可用承诺。'),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final source in OnlineMusicSource.values) ...[
              _SourceCard(
                source: source,
                enabled: preferences.isEnabled(source),
                onChanged: (value) => unawaited(_change(source, value)),
              ),
              const SizedBox(height: 10),
            ],
            _LrclibSourceCard(
              enabled: _lrclibEnabled.value,
              onChanged: (value) => unawaited(_changeLrclib(value)),
            ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                enabledCount == 0
                    ? ui('此类来源均已停用')
                    : ui('已启用 {0} 个此类来源；各项按已标注能力参与联网请求。', [enabledCount]),
                key: const ValueKey('music-source-status'),
                style: TextStyle(
                    color: enabledCount == 0
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

class _LrclibSourceCard extends StatelessWidget {
  const _LrclibSourceCard({required this.enabled, required this.onChanged});
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
            icon: Icons.lyrics_outlined,
            controlKey: const ValueKey('online-source-lrclib'),
            value: enabled,
            onChanged: onChanged,
            title: const Text('LRCLIB'),
            subtitle: Text(enabled ? ui('参与歌词匹配') : ui('不参与歌词匹配')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Capability(
                    icon: Icons.link, text: ui('接口域名（只读）：{0}', ['lrclib.net'])),
                const SizedBox(height: 10),
                const _SourceCapability(
                    icon: Icons.lyrics_outlined, label: '歌词'),
                const SizedBox(height: 10),
                Text(ui('通过 LRCLIB 公开 API 匹配歌词；不提供歌曲播放或下载。'),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
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
                  icon: Icons.link,
                  text: ui('接口域名（只读）：{0}', [
                    source == OnlineMusicSource.qq
                        ? 'u.y.qq.com · c.y.qq.com'
                        : 'music.163.com',
                  ]),
                ),
                const SizedBox(height: 10),
                const Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    _SourceCapability(icon: Icons.search, label: '搜索'),
                    _SourceCapability(icon: Icons.info_outline, label: '歌曲信息'),
                    _SourceCapability(icon: Icons.image_outlined, label: '封面'),
                    _SourceCapability(icon: Icons.lyrics_outlined, label: '歌词'),
                    _SourceCapability(
                        icon: Icons.play_circle_outline, label: '播放'),
                    _SourceCapability(
                        icon: Icons.download_outlined, label: '下载'),
                    _SourceCapability(
                        icon: Icons.comment_outlined, label: '评论'),
                  ],
                ),
                const SizedBox(height: 10),
                _Capability(
                    icon: Icons.manage_search,
                    text: ui("歌曲搜索；公开可用音源播放；歌词和封面（来源提供时）。")),
                const SizedBox(height: 8),
                _Capability(
                    icon: Icons.file_download_outlined,
                    text: ui('下载按接口实际返回执行，需登录或受限时会提示。')),
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

class _SourceCapability extends StatelessWidget {
  const _SourceCapability({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Flexible(
              child: Text(ui(label),
                  style: Theme.of(context).textTheme.bodySmall)),
        ],
      );
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
