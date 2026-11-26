import 'package:dan_player/component/player_feature_guide.dart';
import 'package:dan_player/component/process_resource_monitor.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/settings_page/about_brand.dart';
import 'package:dan_player/page/settings_page/animation_settings.dart';
import 'package:dan_player/page/settings_page/artist_separator_editor.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/page/settings_page/close_behavior_settings.dart';
import 'package:dan_player/page/settings_page/create_issue.dart';
import 'package:dan_player/page/settings_page/custom_music_source_settings.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/page/settings_page/desktop_lyric_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/interface_settings.dart';
import 'package:dan_player/page/settings_page/library_health_settings.dart';
import 'package:dan_player/page/settings_page/library_watch_settings.dart';
import 'package:dan_player/page/settings_page/lyric_annotation_settings.dart';
import 'package:dan_player/page/settings_page/lyric_cache_batch_settings.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/page/settings_page/music_source_settings.dart';
import 'package:dan_player/page/settings_page/network_proxy_settings.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/performance_preset_settings.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/page/settings_page/playback_transition_settings.dart';
import 'package:dan_player/page/settings_page/queue_display_settings.dart';
import 'package:dan_player/page/settings_page/rendering_settings.dart';
import 'package:dan_player/page/settings_page/replay_gain_settings.dart';
import 'package:dan_player/page/settings_page/shortcut_settings.dart';
import 'package:dan_player/page/settings_page/sidebar_layout_settings.dart';
import 'package:dan_player/page/settings_page/silence_skip_settings.dart';
import 'package:dan_player/page/settings_page/simple_playback_bar_playlist_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/page/settings_page/track_resume_settings.dart';
import 'package:dan_player/page/settings_page/uninstall_settings.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.initialSection,
    this.initialSetting,
    this.openIssueDialogOnMount = false,
  });

  final String? initialSection, initialSetting;
  final bool openIssueDialogOnMount;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _openedInitialIssueDialog = false;

  @override
  void initState() {
    super.initState();
    _scheduleIssueDialogIfNeeded();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openIssueDialogOnMount && !oldWidget.openIssueDialogOnMount) {
      _openedInitialIssueDialog = false;
      _scheduleIssueDialogIfNeeded();
    }
  }

  void _scheduleIssueDialogIfNeeded() {
    if (!widget.openIssueDialogOnMount || _openedInitialIssueDialog) return;
    _openedInitialIssueDialog = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showReportIssueDialog(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PageScaffold(
      title: ui("设置"),
      actions: const [],
      body: GroupedSettings(
          initialSection: widget.initialSection,
          initialSetting: widget.initialSetting,
          sections: [
            SettingsSection(
              id: 'library',
              title: ui("曲库与播放"),
              icon: Icons.library_music_outlined,
              children: [
                SettingsSubgroupHeader(
                  title: ui('曲库目录与同步'),
                  icon: Icons.folder_copy_outlined,
                ),
                const AudioLibraryEditor(
                  key: ValueKey('setting-folders'),
                ),
                const RefreshAudioLibraryTile(
                  key: ValueKey('setting-refresh'),
                ),
                const LibraryWatchSettings(
                  key: ValueKey('setting-watch'),
                ),
                const ArtistSeparatorEditor(
                  key: ValueKey('setting-artists'),
                ),
                const LibraryHealthSettings(
                  key: ValueKey('setting-health'),
                ),
                SettingsSubgroupHeader(
                  title: ui('音频输出与听感'),
                  icon: Icons.equalizer_rounded,
                ),
                const PlaybackSettings(
                  key: ValueKey('setting-playback'),
                ),
                const PlaybackTransitionSettings(
                  key: ValueKey('setting-transition'),
                ),
                const SilenceSkipSettings(
                  key: ValueKey('setting-silence'),
                ),
                const ReplayGainSettings(
                  key: ValueKey('setting-gain'),
                ),
                SettingsSubgroupHeader(
                  title: ui('会话与续播习惯'),
                  icon: Icons.history_toggle_off_rounded,
                ),
                const RestoreSessionSwitch(
                  key: ValueKey('setting-session'),
                ),
                const TrackResumeSettings(
                  key: ValueKey('setting-resume'),
                ),
                const PreventSleepSwitch(
                  key: ValueKey('setting-sleep'),
                ),
              ],
            ),
            SettingsSection(
              id: 'lyrics',
              title: ui("联网与歌词"),
              icon: Icons.lyrics_outlined,
              children: [
                SettingsSubgroupHeader(
                  title: ui('歌词获取与缓存'),
                  icon: Icons.cloud_download_outlined,
                ),
                const AutomaticOnlineLyricsSwitch(
                  key: ValueKey('setting-automatic'),
                ),
                const DefaultLyricSourceControl(
                  key: ValueKey('setting-source'),
                ),
                const LyricCacheBatchSettings(
                  key: ValueKey('setting-batch'),
                ),
                SettingsSubgroupHeader(
                  title: ui('日语假名与英语音标'),
                  icon: Icons.translate_outlined,
                ),
                const LyricAnnotationSettings(
                  key: ValueKey('setting-annotations'),
                ),
                SettingsSubgroupHeader(
                  title: ui('歌词排版与进度样式'),
                  icon: Icons.lyrics_outlined,
                ),
                const LyricExperienceSettings(
                  key: ValueKey('setting-experience'),
                  includeAnnotations: false,
                ),
                SettingsSubgroupHeader(
                  title: ui('在线音源与接口'),
                  icon: Icons.public_outlined,
                ),
                const MusicSourceSettings(
                  key: ValueKey('setting-platforms'),
                ),
                const CustomMusicSourceSettings(
                  key: ValueKey('setting-custom'),
                ),
              ],
            ),
            SettingsSection(
              id: 'appearance',
              title: ui("界面与主题"),
              icon: Icons.palette_outlined,
              children: [
                SettingsSubgroupHeader(
                  title: ui('语言、配色与字体'),
                  icon: Icons.color_lens_outlined,
                ),
                const InterfaceSettings(
                    key: ValueKey('setting-language'),
                    group: InterfaceSettingsGroup.language),
                const ThemeAppearanceSettings(
                  key: ValueKey('setting-theme'),
                ),
                const SelectFontCombobox(
                  key: ValueKey('setting-font'),
                ),
                SettingsSubgroupHeader(
                  title: ui('界面布局与队列展示'),
                  icon: Icons.dashboard_customize_outlined,
                ),
                const InterfaceSettings(
                    key: ValueKey('setting-layout'),
                    group: InterfaceSettingsGroup.layout),
                const SidebarLayoutSettings(
                  key: ValueKey('setting-sidebar'),
                ),
                const SimplePlaybackBarPlaylistSettings(
                  key: ValueKey('setting-simple-playback-bar-playlist'),
                ),
                const QueueDisplaySettings(
                  key: ValueKey('setting-queue-upcoming'),
                ),
              ],
            ),
            SettingsSection(
              id: 'effects',
              title: ui("背景与动效"),
              icon: Icons.blur_on,
              children: const [
                WindowBackdropInfo(
                  key: ValueKey('setting-background'),
                ),
                VisualEffectsSettings(
                  key: ValueKey('setting-rendering'),
                ),
                AnimationSettings(
                  key: ValueKey('setting-animation'),
                ),
              ],
            ),
            SettingsSection(
              id: 'desktop',
              title: ui("桌面与快捷键"),
              icon: Icons.desktop_windows_outlined,
              children: const [
                DesktopLyricSettings(
                  key: ValueKey('setting-desktop-lyrics'),
                ),
                DesktopIntegrationSettings(
                  key: ValueKey('setting-integration'),
                ),
                ShortcutSettings(
                  key: ValueKey('setting-shortcuts'),
                ),
              ],
            ),
            SettingsSection(
              id: 'backup',
              title: ui("备份与恢复"),
              icon: Icons.settings_backup_restore_outlined,
              children: [
                SettingsSubgroupHeader(
                  title: ui('数据备份与窗口行为'),
                  icon: Icons.settings_backup_restore_outlined,
                ),
                const CacheBackupSettings(
                  key: ValueKey('setting-backup'),
                ),
                const CloseBehaviorSettings(
                  key: ValueKey('setting-close-behavior'),
                ),
                SettingsSubgroupHeader(
                  title: ui('性能预设、指南与监控'),
                  icon: Icons.speed_rounded,
                ),
                const PerformancePresetSettings(
                  key: ValueKey('setting-performance'),
                ),
                const PlayerFeatureGuideSettings(
                  key: ValueKey('setting-feature-guide'),
                ),
                const ProcessResourceMonitor(
                  key: ValueKey('setting-process-resources'),
                ),
              ],
            ),
            SettingsSection(
              id: 'about',
              title: ui("更新与关于"),
              icon: Icons.info_outline,
              children: const [
                CheckForUpdate(
                  key: ValueKey('setting-updates'),
                ),
                NetworkProxySettings(
                  key: ValueKey('setting-network-proxy'),
                ),
                UninstallSettings(
                  key: ValueKey('setting-uninstall'),
                ),
                CreateIssueTile(
                  key: ValueKey('setting-issues'),
                ),
                AboutBrand(
                  key: ValueKey('setting-about'),
                )
              ],
            ),
          ]),
    );
  }
}
