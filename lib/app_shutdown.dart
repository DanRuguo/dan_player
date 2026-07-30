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

Future<void> shutdownAndExit() async {
  if (_shuttingDown) return;
  _shuttingDown = true;

  try {
    if (PlayService.isInitialized) {
      await PlayService.instance.close().timeout(
            const Duration(seconds: 3),
            onTimeout: () =>
                LOGGER.w("[shutdown] playback service close timed out"),
          );
    }
    await Future.wait(
      [
        savePlaylists(),
        saveCustomAudioOrder(),
        saveCollections(),
        saveLyricSources(),
        AppSettings.instance.saveSettings(),
        AppPreference.instance.save(),
      ],
    ).timeout(const Duration(seconds: 5));
    await HotkeysHelper.unregisterAll().timeout(
      const Duration(seconds: 2),
      onTimeout: () => LOGGER.w("[shutdown] hotkey cleanup timed out"),
    );
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
  }
  await windowManager.setPreventClose(false);
  await windowManager.close();
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
