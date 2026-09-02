import 'dart:convert';
import 'dart:io';

import 'package:dan_player/data/app_data_location.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/online_source_preferences.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/player_shortcut_preferences.dart';
import 'package:dan_player/src/rust/api/system_theme.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_geometry.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:dan_player/ui_layout_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/theme_mode_preference.dart';
import 'package:dan_player/update/update_channel_preference.dart';
import 'package:flutter/material.dart';
import 'package:github/github.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// 把旧的 app data 目录（如果存在）复制到新的目录
/// 只在新 app data 目录没有数据时进行
/// 兼容旧的 Documents\dan_player 和 AppData\Roaming\Dan_Ruguo.Inc\dan_player。
Future<void> migrateAppData() async {
  // An explicitly isolated data directory must not import the user's library.
  if (Platform.environment['DAN_PLAYER_DATA_DIR']?.trim().isNotEmpty == true) {
    return;
  }
  try {
    final newAppDataDir = await getAppDataDir();
    if (newAppDataDir.listSync().isNotEmpty) return;

    final documentsDir = await getApplicationDocumentsDirectory();
    final oldDocumentsDir = Directory(
      path.join(documentsDir.path, "dan_player"),
    );
    if (oldDocumentsDir.existsSync()) {
      _copyDirectoryContents(oldDocumentsDir, newAppDataDir);
      return;
    }

    final oldAppDataDir = await getApplicationSupportDirectory();

    if (oldAppDataDir.existsSync()) {
      _copyDirectoryContents(oldAppDataDir, newAppDataDir);
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

void _copyDirectoryContents(Directory source, Directory target) {
  target.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final targetPath = path.join(target.path, path.basename(entity.path));
    if (entity is File) {
      entity.copySync(targetPath);
    } else if (entity is Directory) {
      _copyDirectoryContents(entity, Directory(targetPath));
    }
  }
}

Future<Directory>? _processAppDataDirectory;

Future<File> _appDataLocationFile() async {
  final support = await getApplicationSupportDirectory();
  return File(path.join(support.path, 'data_location.json'));
}

Future<Directory> _resolveDefaultAppDataDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final fallback = path.join(documents.path, AppSettings.appDataDirectoryName);
  final selected = await AppDataLocationStore(await _appDataLocationFile())
      .activatePendingOrReadActive();
  return Directory(selected ?? fallback).create(recursive: true);
}

Future<Directory> getAppDataDir() async {
  final override = Platform.environment['DAN_PLAYER_DATA_DIR']?.trim();
  if (override != null && override.isNotEmpty) {
    if (!path.isAbsolute(override)) {
      throw const FormatException(
          'DAN_PLAYER_DATA_DIR must be an absolute path');
    }
    return Directory(path.normalize(override)).create(recursive: true);
  }
  // `flutter test` changes the mocked path-provider directory between test
  // cases in the same process. Do not let one fixture pin every later case to
  // a directory that its tear-down has already removed. Packaged builds never
  // set this runner-only environment variable and retain the process freeze.
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return _resolveDefaultAppDataDir();
  }
  // Freeze the chosen path for this process. A restored backup can safely
  // schedule another path without live stores starting to split their writes.
  return _processAppDataDirectory ??= _resolveDefaultAppDataDir();
}

/// Makes [directory] the data root on the next launch. Existing services keep
/// using their boot-time path until then, which prevents late shutdown saves
/// from overwriting newly restored data.
Future<void> scheduleAppDataDirectorySwitch(
  Directory directory, {
  required Directory stagedDirectory,
}) async {
  final next = path.normalize(directory.absolute.path);
  if (!path.isAbsolute(next)) {
    throw const FormatException('App data directory must be absolute');
  }
  final current = await getAppDataDir();
  await AppDataLocationStore(await _appDataLocationFile()).schedule(
    nextPath: next,
    currentPath: current.absolute.path,
    stagedPath: stagedDirectory.absolute.path,
  );
}

class AppSettings {
  static final github = GitHub();
  static const String version = "26.0.4-snapshot.3";
  static const String appDisplayName = "Dan Player";
  static const String appDataDirectoryName = "Dan Player";
  static const String githubOwner = "DanRuguo";
  static const String githubRepository = "dan_player";
  static RepositorySlug get githubRepositorySlug => RepositorySlug(
        githubOwner,
        githubRepository,
      );

  /// A single explicit light/dark/system preference; not a startup snapshot.
  ThemeMode themeMode = ThemeMode.system;

  /// 启动时 / 封面主题色不适合当主题时的主题
  int defaultTheme = getWindowsTheme();

  /// 跟随歌曲封面的动态主题
  bool dynamicTheme = true;

  /// Independent, live appearance preferences; old settings use safe defaults.
  final backgrounds = ValueNotifier(const BackgroundPreferences());

  /// Controls new search requests only; saved online tracks remain usable.
  final onlineSources = ValueNotifier(const OnlineSourcePreferences());

  /// User-managed HTTP providers. Profiles remain isolated from the built-in
  /// source toggles and declare only the capabilities they actually expose.
  final customMusicSources =
      ValueNotifier<List<CustomMusicSourceProfile>>(const []);

  /// Desktop controls and playback/lyric presentation; independent of data.
  final experience = ValueNotifier(const PlayerExperiencePreferences());

  /// Shared with the lyric helper over its pipe; only this process saves it.
  final desktopLyricAppearance = ValueNotifier(DesktopLyricAppearance.defaults);

  final uiLayout = ValueNotifier(const UiLayoutPreferences());
  final rendering = ValueNotifier(const RenderingPreferences());

  /// App-local keyboard bindings. Older settings keep the documented defaults.
  final shortcuts = ValueNotifier(ShortcutPreferences.defaults());

  List artistSeparator = ["/", "、"];

  /// 歌词来源：true，本地优先；false，在线优先
  bool localLyricFirst = true;

  /// Backwards-compatible view of the old single custom lyric endpoint.
  ///
  /// New code should use [customMusicSources]. Updating this property only
  /// replaces the fixed legacy profile and never removes other custom sources.
  String? get lyricApiUrl {
    for (final profile in customMusicSources.value) {
      if (!profile.isLegacyLyricProfile) continue;
      return profile
          .endpointFor(CustomMusicSourceCapability.lyrics)
          ?.toString();
    }
    return null;
  }

  set lyricApiUrl(String? value) {
    final profiles = <CustomMusicSourceProfile>[
      for (final profile in customMusicSources.value)
        if (!profile.isLegacyLyricProfile) profile,
    ];
    final legacy = CustomMusicSourceProfile.legacyLyric(value);
    if (value != null && value.trim().isNotEmpty && legacy == null) return;
    if (legacy != null) profiles.add(legacy);
    customMusicSources.value = List.unmodifiable(profiles);
  }

  bool restoreLastSession = true;

  /// 每 24 小时最多自动检查一次所选通道；不自动下载。
  bool autoCheckUpdates = true;

  UpdateChannelPreference updateChannel = const UpdateChannelPreference();
  bool get receivePreviewUpdates => updateChannel.includesPreviewsFor(version);
  set receivePreviewUpdates(bool value) {
    updateChannel = UpdateChannelPreference(receivePreviews: value);
  }

  /// 用户在自动提示中选择忽略的版本；手动检查仍会显示该版本。
  String? ignoredUpdateVersion;

  DateTime? lastUpdateCheckAt;

  Size windowSize = const Size(1280, 756);
  bool isWindowMaximized = false;

  String? fontFamily;
  String? fontPath;

  late String artistSplitPattern = artistSeparator.join("|");

  static final AppSettings _instance = AppSettings._();

  static AppSettings get instance => _instance;

  static int getWindowsTheme() {
    try {
      final systemTheme = SystemTheme.getSystemTheme();
      return Color.fromARGB(
        systemTheme.accent.$1,
        systemTheme.accent.$2,
        systemTheme.accent.$3,
        systemTheme.accent.$4,
      ).toARGB32();
    } catch (_) {
      return Colors.amber.toARGB32();
    }
  }

  AppSettings._();

  int _saveRevision = 0;

  /// Reads the old independent system-accent switch once, then converges on
  /// one persisted seed color. The light/dark/system choice is handled solely
  /// by [themeMode] and is intentionally independent from this migration.
  static void _readThemeSeed(Map settingsMap) {
    final legacySystemAccent = settingsMap["UseSystemTheme"];
    final followsSystem = legacySystemAccent == true || legacySystemAccent == 1;
    if (legacySystemAccent != null && followsSystem) {
      _instance.defaultTheme = getWindowsTheme();
      return;
    }
    final saved = settingsMap["DefaultTheme"];
    if (saved is int) _instance.defaultTheme = saved;
  }

  static void _readWindowGeometry(Map settingsMap) {
    final restored = WindowGeometryPolicy.restore(settingsMap);
    _instance.windowSize = Size(restored.size.width, restored.size.height);
    _instance.isWindowMaximized = restored.isMaximized;
  }

  static Future<void> _readFromJson_old(Map settingsMap) async {
    _instance.themeMode = ThemeModePreference.decode(settingsMap);
    _readThemeSeed(settingsMap);

    _instance.dynamicTheme = settingsMap["DynamicTheme"] == 1 ? true : false;
    _instance.artistSeparator = settingsMap["ArtistSeparator"];
    _instance.artistSplitPattern = _instance.artistSeparator.join("|");

    final llf = settingsMap["LocalLyricFirst"];
    if (llf != null) {
      _instance.localLyricFirst = llf == 1 ? true : false;
    }

    _readCustomMusicSources(settingsMap);

    final restoreLastSession = settingsMap["RestoreLastSession"];
    if (restoreLastSession != null) {
      _instance.restoreLastSession = restoreLastSession is bool
          ? restoreLastSession
          : restoreLastSession == 1;
    }

    _readWindowGeometry(settingsMap);

    _readUpdatePreferences(settingsMap);
  }

  static void _readUpdatePreferences(Map settingsMap) {
    _instance.backgrounds.value =
        BackgroundPreferences.fromMap(settingsMap['Backgrounds']);
    _instance.onlineSources.value =
        OnlineSourcePreferences.fromJson(settingsMap['OnlineSources']);
    _instance.experience.value =
        PlayerExperiencePreferences.fromMap(settingsMap['PlayerExperience']);
    _instance.desktopLyricAppearance.value =
        DesktopLyricAppearance.fromJson(settingsMap['DesktopLyricAppearance']);
    uiLanguage.value = UiLanguage.parse(settingsMap['UiLanguage']);
    _instance.uiLayout.value =
        UiLayoutPreferences.fromMap(settingsMap['UiLayout']);
    _instance.rendering.value =
        RenderingPreferences.fromMap(settingsMap['Rendering']);
    _instance.shortcuts.value =
        ShortcutPreferences.fromMap(settingsMap['PlayerShortcuts']);
    final autoCheck = settingsMap["AutoCheckUpdates"];
    if (autoCheck != null) {
      _instance.autoCheckUpdates =
          autoCheck is bool ? autoCheck : autoCheck == 1;
    }

    final ignoredVersion = settingsMap["IgnoredUpdateVersion"];
    _instance.updateChannel = UpdateChannelPreference.fromMap(settingsMap);
    _instance.ignoredUpdateVersion =
        ignoredVersion is String && ignoredVersion.trim().isNotEmpty
            ? ignoredVersion.trim()
            : null;

    final lastCheck = settingsMap["LastUpdateCheckAt"];
    _instance.lastUpdateCheckAt =
        lastCheck is String ? DateTime.tryParse(lastCheck) : null;
  }

  static void _readCustomMusicSources(Map settingsMap) {
    final legacyValue = settingsMap['LyricApiUrl'];
    final legacyUrl = legacyValue is String && legacyValue.trim().isNotEmpty
        ? legacyValue.trim()
        : null;
    _instance.customMusicSources.value =
        CustomMusicSourceProfileCodec.decodeSettings(
      settingsMap['CustomMusicSources'],
      legacyLyricApiUrl: legacyUrl,
      fallback: _instance.customMusicSources.value,
    );
  }

  static Future<void> readFromJson() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final settingsPath = "$supportPath\\settings.json";

      final settingsStr = File(settingsPath).readAsStringSync();
      Map settingsMap = json.decode(settingsStr);

      if (settingsMap["Version"] == null) {
        await _readFromJson_old(settingsMap);
        return;
      }

      _instance.themeMode = ThemeModePreference.decode(settingsMap);
      _readThemeSeed(settingsMap);

      final dt = settingsMap["DynamicTheme"];
      if (dt != null) {
        _instance.dynamicTheme = dt;
      }

      final as = settingsMap["ArtistSeparator"];
      if (as != null) {
        _instance.artistSeparator = as;
        _instance.artistSplitPattern = _instance.artistSeparator.join("|");
      }

      final llf = settingsMap["LocalLyricFirst"];
      if (llf != null) {
        _instance.localLyricFirst = llf;
      }

      _readCustomMusicSources(settingsMap);

      final restoreLastSession = settingsMap["RestoreLastSession"];
      if (restoreLastSession != null) {
        _instance.restoreLastSession = restoreLastSession is bool
            ? restoreLastSession
            : restoreLastSession == 1;
      }

      _readWindowGeometry(settingsMap);

      final ff = settingsMap["FontFamily"];
      final fp = settingsMap["FontPath"];
      if (ff != null) {
        _instance.fontFamily = ff;
        _instance.fontPath = fp;
      }

      _readUpdatePreferences(settingsMap);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
    }
  }

  Future<void> saveSettings({
    bool throwOnError = false,
    bool captureWindowSize = true,
  }) async {
    try {
      final mode = WindowModeController.instance;
      // Native maximize/fullscreen notifications also arrive during compact
      // transitions. They must not persist an intermediate/mini window size.
      if (captureWindowSize && mode.isBusy) return;
      final saveRevision = ++_saveRevision;
      final normalSnapshot = mode.isMini ? mode.normalWindowSnapshot : null;
      final isMaximized = normalSnapshot?.maximized ??
          (captureWindowSize
              ? await windowManager.isMaximized()
              : isWindowMaximized);
      final isFullScreen = normalSnapshot?.fullScreen ??
          (captureWindowSize ? await windowManager.isFullScreen() : false);
      if (saveRevision != _saveRevision ||
          (captureWindowSize &&
              (mode.isBusy || mode.isMini != (normalSnapshot != null)))) {
        return;
      }
      final settingsMap = {
        "Version": version,
        ...ThemeModePreference.encode(themeMode),
        "DynamicTheme": dynamicTheme,
        "Backgrounds": backgrounds.value.toMap(),
        "PlayerExperience": experience.value.toMap(),
        "DesktopLyricAppearance": desktopLyricAppearance.value.toJson(),
        "UiLanguage": uiLanguage.value.code,
        "UiLayout": uiLayout.value.toMap(),
        "Rendering": rendering.value.toMap(),
        "PlayerShortcuts": shortcuts.value.toMap(),
        "OnlineSources": onlineSources.value.toJson(),
        "CustomMusicSources": CustomMusicSourceProfileCodec.encodeSettings(
          customMusicSources.value,
        ),
        "DefaultTheme": defaultTheme,
        "ArtistSeparator": artistSeparator,
        "LocalLyricFirst": localLyricFirst,
        "LyricApiUrl": lyricApiUrl,
        "RestoreLastSession": restoreLastSession,
        "AutoCheckUpdates": autoCheckUpdates,
        ...updateChannel.toMap(),
        "IgnoredUpdateVersion": ignoredUpdateVersion,
        "LastUpdateCheckAt": lastUpdateCheckAt?.toIso8601String(),
        "FontFamily": fontFamily,
        "FontPath": fontPath,
      };

      // 只有在窗口不是最大化且不是全屏时才保存窗口尺寸
      // 这样windowSize始终保存的是窗口化时的尺寸
      Size sizeToSave = normalSnapshot?.bounds.size ?? windowSize;
      if (captureWindowSize &&
          normalSnapshot == null &&
          !isMaximized &&
          !isFullScreen) {
        sizeToSave = await windowManager.getSize();
      }
      if (saveRevision != _saveRevision ||
          (captureWindowSize &&
              (mode.isBusy || mode.isMini != (normalSnapshot != null)))) {
        return;
      }
      final safeSize = WindowGeometryPolicy.constrain(
        WindowGeometrySize(sizeToSave.width, sizeToSave.height),
      );
      sizeToSave = Size(safeSize.width, safeSize.height);
      windowSize = sizeToSave;
      isWindowMaximized = isMaximized;
      settingsMap.addAll(WindowGeometryPolicy.encode(
        size: safeSize,
        isMaximized: isMaximized,
      ));

      final settingsStr = json.encode(settingsMap);
      final supportPath = (await getAppDataDir()).path;
      final settingsPath = "$supportPath\\settings.json";
      if (saveRevision != _saveRevision) return;
      final output = await File(settingsPath).create(recursive: true);
      // Sliders and mode/appearance switches may save concurrently. A delayed
      // old window/path reply must never overwrite a newer preference snapshot.
      if (saveRevision != _saveRevision) return;
      output.writeAsStringSync(settingsStr);
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      // Existing fire-and-forget callers keep their non-throwing behavior.
      // Interactive settings can opt in and show a failed write to the user.
      if (throwOnError) rethrow;
    }
  }
}
