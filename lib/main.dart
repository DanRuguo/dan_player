import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_shutdown.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/entry.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';

/// Applies all native window geometry and interaction policy while the runner
/// window is still hidden. This must complete before [runApp] can submit the
/// first frame; otherwise Windows briefly exposes the runner's placeholder
/// bounds and then jumps to the restored size.
Future<void> prepareWindow() async {
  // Keep this immutable during preparation: ratio-lock initialization may
  // persist its captured ratio before the native maximize state is restored.
  final restoreMaximized = AppSettings.instance.isWindowMaximized;
  await windowManager.ensureInitialized();
  await registerAppCloseHandler();
  final windowOptions = WindowOptions(
    minimumSize: WindowModeController.instance.normalMinimumSize,
    size: AppSettings.instance.windowSize,
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
  }
}

Future<void> showPreparedWindow() async {
  // Let Entry paint one complete frame into the hidden native surface. The
  // runner deliberately no longer shows its placeholder first frame.
  await WidgetsBinding.instance.endOfFrame;
  await windowManager.show();
  await windowManager.focus();
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  final supportPath = (await getAppDataDir()).path;
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

  await prepareWindow();
  runApp(Entry(welcome: welcome));
  await showPreparedWindow();
  HotkeysHelper.registerHotKeys();
}
