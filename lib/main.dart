import 'package:desktop_lyric/frame_pacing.dart';
import 'package:dan_player/data/snapshot3_upgrade.dart';
import 'dart:io';

import 'package:dan_player/app_launch_mode.dart';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:dan_player/library/audio_metadata_journal.dart';
import 'package:dan_player/page/library_migration_recovery.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/online/song_comment_association.dart';
import 'package:dan_player/src/rust/api/logger.dart';
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_backdrop.dart';
import 'package:dan_player/window_layout_controller.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:dan_player/windows_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/main.dart' as desktop_lyric;

/// Applies all native window geometry and interaction policy while the runner
/// window is still hidden. This must complete before [runApp] can submit the
/// first frame; otherwise Windows briefly exposes the runner's placeholder
/// bounds and then jumps to the restored size.
Future<void> prepareWindow() async {
  AppSettings.instance.windowGeometryCaptureSuspended = true;
  // Keep this immutable during preparation: ratio-lock initialization may
  // persist its captured ratio before the native maximize state is restored.
  final restoreMaximized = AppSettings.instance.isWindowMaximized;
  final restoredSize = AppSettings.instance.windowSize;
  await windowManager.ensureInitialized();
  await registerAppCloseHandler();
  final windowOptions = WindowOptions(
    minimumSize: WindowModeController.instance.normalMinimumSize,
    size: restoredSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  // The plugin's callback is void and does not await async work. Apply the
  // window options first, then install the native blur policy they would
  // otherwise overwrite, and only then finish showing the window.
  await windowManager.waitUntilReadyToShow(windowOptions);
  await WindowBackdropService.instance.initialize(
    brightness: ThemeProvider.instance.currScheme.brightness,
    enabled: AppSettings.instance.backgrounds.value.needsNativeGlass,
  );
  try {
    await WindowLayoutController.instance.initialize();
  } catch (error, trace) {
    LOGGER.w('[window layout] $error', stackTrace: trace);
    showAppNotice(
      ui('窗口尺寸锁定设置暂未应用，可在“设置 > 外观与背景”中重试。'),
      kind: AppNoticeKind.warning,
    );
  }
  // Optional shell integration must never prevent the normal window opening.
  try {
    await DesktopIntegration.instance.initialize(onExit: shutdownAndExit);
  } catch (error, trace) {
    LOGGER.w('[desktop integration] $error', stackTrace: trace);
  }

  if (restoreMaximized) {
    await windowManager.maximize();
    AppSettings.instance.isWindowMaximized = true;
  } else {
    // Hidden native material/style changes may deliver an intermediate resize.
    // Read it back after preparation and repair undersized startup geometry
    // before the first visible frame, while the loaded size is still immutable.
    final actual = await windowManager.getSize();
    final minimum = WindowModeController.instance.normalMinimumSize;
    if (!actual.width.isFinite ||
        !actual.height.isFinite ||
        actual.width < minimum.width - 1 ||
        actual.height < minimum.height - 1) {
      await windowManager.setSize(restoredSize);
      await windowManager.center();
    }
  }
}

Future<void> showPreparedWindow() async {
  // Let Entry paint one complete frame into the hidden native surface. The
  // runner deliberately no longer shows its placeholder first frame.
  await WidgetsBinding.instance.endOfFrame;
  await windowManager.show();
  await windowManager.focus();
  AppSettings.instance.windowGeometryCaptureSuspended = false;
}

Future<void> loadPrefFont() async {
  final settings = AppSettings.instance;
  if (settings.fontFamily == null || settings.fontPath == null) return;

  try {
    final fontFile = File(settings.fontPath!);
    if (!fontFile.existsSync()) return;

    final fontLoader = FontLoader(settings.fontFamily!);
    fontLoader.addFont(
      fontFile.readAsBytes().then((value) {
        return ByteData.sublistView(value);
      }),
    );
    await fontLoader.load();
    ThemeProvider.instance.changeFontFamily(settings.fontFamily!);
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

Future<void> main(List<String> arguments) => dispatchAppLaunch(
      arguments,
      startPlayer: _startMainPlayer,
      startDesktopLyric: desktop_lyric.runDesktopLyric,
    );

// The native palette creates a second Flutter engine against this executable's
// root library. Keep its entrypoint visible in the same release AOT bundle.
@pragma('vm:entry-point')
Future<void> desktopLyricAppearanceMain(List<String> arguments) =>
    desktop_lyric.desktopLyricAppearanceMain(arguments);

Future<void> _startMainPlayer() async {
  FramePacedWidgetsBinding();
  // Artwork is already decoded to physical display buckets. Keep Flutter's
  // decoded cache bounded as a second line of defence for large libraries.
  PaintingBinding.instance.imageCache
    ..maximumSize = 384
    ..maximumSizeBytes = 128 * 1024 * 1024;

  await RustLib.init();

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  // Reset the single app-local shortcut dispatcher for a hot restart.
  await HotkeysHelper.unregisterAll();

  await migrateAppData();

  final dataDirectory = await getAppDataDir();
  final migration = LibraryDataMigration(dataDirectory);
  try {
    await migration.recover();
    await AudioMetadataJournal(dataDirectory).recover();
    await Snapshot3Upgrade.prepare(dataDirectory);
  } catch (error) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(const WindowOptions(
        size: Size(760, 520), center: true, title: 'Dan Player · 曲库恢复'));
    runApp(MaterialApp(
        theme: Entry(welcome: false).fromSchemeAndFontFamily(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
        home: LibraryMigrationRecovery(
            migration: migration,
            error: error,
            allowRestore: !await AudioMetadataJournal(dataDirectory).hasPending,
            resume: () async {
              await AudioMetadataJournal(dataDirectory).recover();
              await Snapshot3Upgrade.prepare(dataDirectory);
              await _startPlayer(dataDirectory);
            })));
    await showPreparedWindow();
    return;
  }
  await _startPlayer(dataDirectory);
}

Future<void> _startPlayer(Directory dataDirectory) async {
  final supportPath = dataDirectory.path;
  void syncFrameRate() {
    final prefs = AppSettings.instance.rendering.value;
    frameRatePreference.value = prefs.frameRate;
    pauseWindowRendering.value =
        prefs.pauseWhenHidden && DesktopIntegration.instance.isHidden.value;
  }

  AppSettings.instance.rendering.addListener(syncFrameRate);
  DesktopIntegration.instance.isHidden.addListener(syncFrameRate);
  if (File("$supportPath\\settings.json").existsSync()) {
    await AppSettings.readFromJson();
    await loadPrefFont();
  }
  if (File("$supportPath\\app_preference.json").existsSync()) {
    await AppPreference.read();
  }
  // Comment bindings are app-owned metadata. Load them independently of the
  // media index so a damaged/offline library scan cannot discard associations.
  await SongCommentAssociationStore.instance.initialize();
  final welcome = !File("$supportPath\\index.json").existsSync();

  syncFrameRate();
  await prepareWindow();
  runApp(Entry(welcome: welcome));
  await showPreparedWindow();
  HotkeysHelper.registerHotKeys();
  await WindowsShell.instance.initialize(welcome: welcome);
}
