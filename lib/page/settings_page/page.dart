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
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return PageScaffold(
      title: ui("设置"),
      actions: const [],
      body: GroupedSettings(sections: [
        SettingsSection(
          id: 'library',
          title: ui("曲库与播放"),
          icon: Icons.library_music_outlined,
          children: [
            const AudioLibraryEditor(),
            const RefreshAudioLibraryTile(),
            const RestoreSessionSwitch(),
            const PlaybackSettings(),
            const TrackResumeSettings(),
            const ReplayGainSettings(),
            const PreventSleepSwitch(),
            const LibraryWatchSettings(),
            const ArtistSeparatorEditor(),
            const LibraryHealthSettings(),
          ],
        ),
        SettingsSection(
          id: 'lyrics',
          title: ui("联网与歌词"),
          icon: Icons.lyrics_outlined,
          children: [
            const AutomaticOnlineLyricsSwitch(),
            const DefaultLyricSourceControl(),
            const LyricCacheBatchSettings(),
            const LyricExperienceSettings(),
            const MusicSourceSettings(),
            const CustomMusicSourceSettings(),
          ],
        ),
        SettingsSection(
          id: 'appearance',
          title: ui("界面与主题"),
          icon: Icons.palette_outlined,
          children: [
            const InterfaceSettings(group: InterfaceSettingsGroup.language),
            const ThemeAppearanceSettings(),
            const SelectFontCombobox(),
            const InterfaceSettings(group: InterfaceSettingsGroup.layout),
            const SidebarLayoutSettings(),
          ],
        ),
        SettingsSection(
          id: 'effects',
          title: ui("背景与动效"),
          icon: Icons.blur_on,
          children: const [
            WindowBackdropInfo(),
            VisualEffectsSettings(),
            AnimationSettings(),
          ],
        ),
        SettingsSection(
          id: 'desktop',
          title: ui("桌面与快捷键"),
          icon: Icons.desktop_windows_outlined,
          children: [
            const DesktopLyricSettings(),
            const DesktopIntegrationSettings(),
            const ShortcutSettings(),
          ],
        ),
        SettingsSection(
          id: 'backup',
          title: ui("备份与恢复"),
          icon: Icons.settings_backup_restore_outlined,
          children: const [
            CacheBackupSettings(),
            PerformancePresetSettings(),
          ],
        ),
        SettingsSection(
          id: 'about',
          title: ui("更新与关于"),
          icon: Icons.info_outline,
          children: [
            const CheckForUpdate(),
            const UninstallSettings(),
            const CreateIssueTile(),
            const AboutBrand()
          ],
        ),
      ]),
    );
  }
}
