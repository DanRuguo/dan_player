import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:window_manager/window_manager.dart';

bool _shuttingDown = false;

/// Separates a user close request from an explicit Quit command. Injectable so
/// failure/rapid-close tests never need a real HWND, native audio or user files.
class AppCloseCoordinator {
  AppCloseCoordinator({
    required this.closeToTray,
    required this.hideToTray,
    required this.exit,
  });

  final bool Function() closeToTray;
  final Future<bool> Function() hideToTray;
  final Future<void> Function() exit;
  Future<void>? _pending;

  Future<void> requestClose() => _pending ??= _request().whenComplete(() {
        _pending = null;
      });

  Future<void> _request() async {
    if (closeToTray()) {
      try {
        if (await hideToTray()) return;
      } catch (error, trace) {
        LOGGER.w('后台播放不可用，将正常退出：$error', stackTrace: trace);
      }
    }
    await exit();
  }
}

final _closeCoordinator = AppCloseCoordinator(
  closeToTray: () => AppSettings.instance.experience.value.closeToTray,
  hideToTray: () => DesktopIntegration.instance.hideToTray(),
  exit: shutdownAndExit,
);

Future<void> requestAppClose() async {
  if (!_shuttingDown) await _closeCoordinator.requestClose();
}

Future<void> _waitForCleanup(List<Future<void>> tasks) async {
  await Future.wait(tasks);
}

Future<void> shutdownAndExit() async {
  if (_shuttingDown) return;
  _shuttingDown = true;

  // Quit always bypasses the hide preference. Unsubscribe before audio teardown
  // so Shell callbacks cannot read a disposed native player or reopen a window.
  try {
    await DesktopIntegration.instance.dispose();
  } catch (error, trace) {
    LOGGER.w('退出时清理桌面集成失败：$error', stackTrace: trace);
  }

  try {
    await windowManager.hide();
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }

  try {
    final cleanupTasks = <Future<void>>[
      Future.wait([
        savePlaylists(),
        saveCustomAudioOrder(),
        saveLyricSources(),
        AppSettings.instance.saveSettings(),
        AppPreference.instance.save(),
      ]),
      HotkeysHelper.unregisterAll(),
    ];
    // An empty desktop lyric helper can exist before native playback is ready.
    // The facade closes only resources it already owns; it creates nothing.
    if (PlayService.hasFacade) {
      cleanupTasks.add(PlayService.instance.close());
    }
    await _waitForCleanup(cleanupTasks).timeout(
      const Duration(seconds: 2),
      onTimeout: () => LOGGER.w("[shutdown] cleanup timed out"),
    );
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
  try {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
}

class _AppCloseListener with WindowListener {
  @override
  void onWindowClose() {
    requestAppClose();
  }
}

final _appCloseListener = _AppCloseListener();

Future<void> registerAppCloseHandler() async {
  windowManager.addListener(_appCloseListener);
  await windowManager.setPreventClose(true);
}
