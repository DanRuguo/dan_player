import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:window_manager/window_manager.dart';

bool _shuttingDown = false;

Future<void> _waitForCleanup(List<Future<void>> tasks) async {
  await Future.wait(tasks);
}

Future<void> shutdownAndExit() async {
  if (_shuttingDown) return;
  _shuttingDown = true;

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
        saveCollections(),
        saveLyricSources(),
        AppSettings.instance.saveSettings(),
        AppPreference.instance.save(),
      ]),
      HotkeysHelper.unregisterAll(),
    ];
    if (PlayService.isInitialized) {
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
    shutdownAndExit();
  }
}

final _appCloseListener = _AppCloseListener();

Future<void> registerAppCloseHandler() async {
  windowManager.addListener(_appCloseListener);
  await windowManager.setPreventClose(true);
}
