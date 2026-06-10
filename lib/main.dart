import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/entry.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/src/rust/api/logger.dart';
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initWindow() async {
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = WindowOptions(
    minimumSize: const Size(507, 507),
    size: AppSettings.instance.windowSize,
    center: true,
    backgroundColor: const Color(0xFFF7F4ED),
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
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

  await RustLib.init();

  initRustLogger().listen((msg) {
    LOGGER.i("[rs]: $msg");
  });

  // For hot reload, `unregisterAll()` needs to be called.
  await HotkeysHelper.unregisterAll();
  HotkeysHelper.registerHotKeys();

  await migrateAppData();

  final supportPath = (await getAppDataDir()).path;
  if (File("$supportPath\\settings.json").existsSync()) {
    await AppSettings.readFromJson();
    await loadPrefFont();
  }
  if (File("$supportPath\\app_preference.json").existsSync()) {
    await AppPreference.read();
  }
  final welcome = !File("$supportPath\\index.json").existsSync();

  runApp(Entry(welcome: welcome));

  await initWindow();
}
