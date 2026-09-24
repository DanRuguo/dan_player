import 'package:dan_player/page/settings_page/lyric_cache_batch_settings.dart';
import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/settings_page/about_brand.dart';
import 'package:dan_player/page/settings_page/artist_separator_editor.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:dan_player/page/settings_page/performance_preset_settings.dart';
import 'package:dan_player/page/settings_page/create_issue.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/music_source_settings.dart';
import 'package:dan_player/page/settings_page/network_proxy_settings.dart';
import 'package:dan_player/page/settings_page/custom_music_source_settings.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/page/settings_page/desktop_lyric_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/page/settings_page/library_watch_settings.dart';
import 'package:dan_player/page/settings_page/library_health_settings.dart';
import 'package:dan_player/page/settings_page/replay_gain_settings.dart';
import 'package:dan_player/page/settings_page/track_resume_settings.dart';
import 'package:dan_player/page/settings_page/shortcut_settings.dart';
import 'package:dan_player/page/settings_page/sidebar_layout_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:dan_player/page/settings_page/uninstall_settings.dart';
import 'package:flutter/material.dart';
import 'interface_settings.dart';
import 'rendering_settings.dart';
import 'animation_settings.dart';
import 'package:desktop_lyric/ui_language.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.initialSection, this.initialSetting});
  final String? initialSection, initialSetting;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PageScaffold(
      title: ui("设置"),
      actions: const [],
      body: GroupedSettings(
          initialSection: initialSection,
          initialSetting: initialSetting,
          sections: [
            SettingsSection(
              id: 'library',
              title: ui("曲库与播放"),
              icon: Icons.library_music_outlined,
              children: [
                const AudioLibraryEditor(
                  key: ValueKey('setting-folders'),
                ),
                const RefreshAudioLibraryTile(
                  key: ValueKey('setting-refresh'),
                ),
                const RestoreSessionSwitch(
                  key: ValueKey('setting-session'),
                ),
                const PlaybackSettings(
                  key: ValueKey('setting-playback'),
                ),
                const TrackResumeSettings(
                  key: ValueKey('setting-resume'),
                ),
                const ReplayGainSettings(
                  key: ValueKey('setting-gain'),
                ),
                const PreventSleepSwitch(
                  key: ValueKey('setting-sleep'),
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
              ],
            ),
            SettingsSection(
              id: 'lyrics',
              title: ui("联网与歌词"),
              icon: Icons.lyrics_outlined,
              children: [
                const AutomaticOnlineLyricsSwitch(
                  key: ValueKey('setting-automatic'),
                ),
                const DefaultLyricSourceControl(
                  key: ValueKey('setting-source'),
                ),
                const LyricCacheBatchSettings(
                  key: ValueKey('setting-batch'),
                ),
                const LyricExperienceSettings(
                  key: ValueKey('setting-experience'),
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
                const InterfaceSettings(
                    key: ValueKey('setting-language'),
                    group: InterfaceSettingsGroup.language),
                const ThemeAppearanceSettings(
                  key: ValueKey('setting-theme'),
                ),
                const SelectFontCombobox(
                  key: ValueKey('setting-font'),
                ),
                const InterfaceSettings(
                    key: ValueKey('setting-layout'),
                    group: InterfaceSettingsGroup.layout),
                const SidebarLayoutSettings(
                  key: ValueKey('setting-sidebar'),
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
              children: [
                const DesktopLyricSettings(
                  key: ValueKey('setting-desktop-lyrics'),
                ),
                const DesktopIntegrationSettings(
                  key: ValueKey('setting-integration'),
                ),
                const ShortcutSettings(
                  key: ValueKey('setting-shortcuts'),
                ),
              ],
            ),
            SettingsSection(
              id: 'backup',
              title: ui("备份与恢复"),
              icon: Icons.settings_backup_restore_outlined,
              children: const [
                CacheBackupSettings(
                  key: ValueKey('setting-backup'),
                ),
                PerformancePresetSettings(
                  key: ValueKey('setting-performance'),
                ),
              ],
            ),
            SettingsSection(
              id: 'about',
              title: ui("更新与关于"),
              icon: Icons.info_outline,
              children: [
                const CheckForUpdate(
                  key: ValueKey('setting-updates'),
                ),
                const NetworkProxySettings(
                  key: ValueKey('setting-network-proxy'),
                ),
                const UninstallSettings(
                  key: ValueKey('setting-uninstall'),
                ),
                const CreateIssueTile(
                  key: ValueKey('setting-issues'),
                ),
                const AboutBrand(
                  key: ValueKey('setting-about'),
                )
              ],
            ),
          ]),
    );
  }
}
