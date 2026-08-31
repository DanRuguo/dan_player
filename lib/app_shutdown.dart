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

/// Shares concurrent quit requests and permits retry if the window close fails.
/// A successful quit remains latched while Windows tears down the process.
class AppShutdownCoordinator {
  Future<void>? _pending;
  bool _completed = false;

  bool get isShuttingDown => _completed || _pending != null;

  Future<void> run(Future<void> Function() action,
      {bool throwOnError = false}) async {
    if (_completed) return;
    final task = _pending ??= Future<void>.microtask(action).then((_) {
      _completed = true;
    }).whenComplete(() => _pending = null);
    try {
      await task;
    } catch (_) {
      if (throwOnError) rethrow;
    }
  }
}

final _shutdownCoordinator = AppShutdownCoordinator();

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
  if (!_shutdownCoordinator.isShuttingDown) {
    await _closeCoordinator.requestClose();
  }
}

Future<void> _waitForCleanup(List<Future<void>> tasks) async {
  await Future.wait(tasks);
}

/// Hiding must finish before region/iconic-frame/plugin resources are removed.
/// The injectable steps let ordering/failure regressions run without a window,
/// playback, settings persistence, or any user files.
Future<void> prepareWindowForShutdown({
  required Future<void> Function() hideWindow,
  required Future<void> Function() disposeDesktop,
  required void Function(Object, StackTrace) onHideError,
}) async {
  try {
    await hideWindow();
  } catch (error, trace) {
    onHideError(error, trace);
  }
  await disposeDesktop();
}

Future<void> shutdownAndExit({bool throwOnError = false}) =>
    _shutdownCoordinator.run(_shutdownAndCloseWindow,
        throwOnError: throwOnError);

Future<void> _shutdownAndCloseWindow() async {
  // Quit always bypasses the hide preference. Hide before removing the custom
  // region/DWM preview; otherwise the still-visible parent can flash its native
  // caption. Desktop subscriptions are still removed before audio teardown.
  try {
    await prepareWindowForShutdown(
      hideWindow: windowManager.hide,
      disposeDesktop: DesktopIntegration.instance.dispose,
      onHideError: (error, trace) => LOGGER.e(error, stackTrace: trace),
    );
  } catch (error, trace) {
    LOGGER.w('退出时清理桌面集成失败：$error', stackTrace: trace);
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
    // Cleanup has already run. Do not pretend playback has been restored, but
    // make the close error/retry controls reachable instead of stranding an
    // invisible player that every subsequent Quit request would ignore.
    DesktopIntegration.instance.restorePresentationAfterFailedShutdown();
    try {
      await windowManager.setPreventClose(true);
    } catch (preventError, preventTrace) {
      LOGGER.e(preventError, stackTrace: preventTrace);
    }
    try {
      await windowManager.show();
    } catch (showError, showTrace) {
      LOGGER.e(showError, stackTrace: showTrace);
    }
    rethrow;
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
