import 'package:dan_player/page/page_scaffold.dart';
import 'package:dan_player/page/settings_page/about_brand.dart';
import 'package:dan_player/page/settings_page/artist_separator_editor.dart';
import 'package:dan_player/page/settings_page/check_update.dart';
import 'package:dan_player/page/settings_page/create_issue.dart';
import 'package:dan_player/page/settings_page/other_settings.dart';
import 'package:dan_player/page/settings_page/music_source_settings.dart';
import 'package:dan_player/page/settings_page/desktop_integration_settings.dart';
import 'package:dan_player/page/settings_page/desktop_lyric_settings.dart';
import 'package:dan_player/page/settings_page/grouped_settings.dart';
import 'package:dan_player/page/settings_page/lyric_experience_settings.dart';
import 'package:dan_player/page/settings_page/playback_settings.dart';
import 'package:dan_player/page/settings_page/shortcut_settings.dart';
import 'package:dan_player/page/settings_page/sidebar_layout_settings.dart';
import 'package:dan_player/page/settings_page/theme_settings.dart';
import 'package:flutter/material.dart';
import 'interface_settings.dart';
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
            const ArtistSeparatorEditor(),
            const RestoreSessionSwitch(),
            const PlaybackSettings(),
          ],
        ),
        SettingsSection(
          id: 'lyrics',
          title: ui("联网与歌词"),
          icon: Icons.lyrics_outlined,
          children: [
            const MusicSourceSettings(),
            const DefaultLyricSourceControl(),
            const LyricApiEditor(),
          ],
        ),
        SettingsSection(
          id: 'appearance',
          title: ui("外观与背景"),
          icon: Icons.palette_outlined,
          children: [
            const InterfaceSettings(),
            const WindowBackdropInfo(),
            const DynamicThemeSwitch(),
            const UseSystemThemeSwitch(),
            const ThemeSelector(),
            const UseSystemThemeModeSwitch(),
            const ThemeModeControl(),
            const SelectFontCombobox(),
            const LyricExperienceSettings(),
            const SidebarLayoutSettings(),
            const DesktopLyricSettings(),
          ],
        ),
        SettingsSection(
          id: 'desktop',
          title: ui("桌面与快捷键"),
          icon: Icons.desktop_windows_outlined,
          children: [
            const DesktopIntegrationSettings(),
            const ShortcutSettings(),
          ],
        ),
        SettingsSection(
          id: 'about',
          title: ui("更新与关于"),
          icon: Icons.info_outline,
          children: [
            const CheckForUpdate(),
            const CreateIssueTile(),
            const AboutBrand()
          ],
        ),
      ]),
    );
  }
}
