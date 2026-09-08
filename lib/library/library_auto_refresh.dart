import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/library/library_watch.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/utils.dart';

class LibraryAutoRefresh {
  LibraryAutoRefresh._();
  static final instance = LibraryAutoRefresh._();
  LibraryWatch? _watch;

  /// Called after the startup index, playlists and playback session are ready.
  void start() {
    if (_watch != null) return;
    _watch = LibraryWatch(
        refresh: _refresh,
        onError: (error, trace) {
          LOGGER.w('[automatic library refresh] $error', stackTrace: trace);
        });
    AppSettings.instance.libraryAutoRefresh.addListener(_configure);
    AudioLibrary.changes.addListener(_configure);
    _configure();
  }

  void _configure() => unawaited(_watch
          ?.configure(
              enabled: AppSettings.instance.libraryAutoRefresh.value,
              roots: AudioLibrary.instance.scanRoots)
          .catchError((Object error, StackTrace trace) {
        LOGGER.w('[library watcher configuration] $error', stackTrace: trace);
      }));

  Future<void> _refresh() async {
    final directory = await getAppDataDir();
    final before =
        LibraryRefreshSnapshot.capture(AudioLibrary.instance.audioCollection);
    final task = LibraryRefreshTask.native(
        folders: AudioLibrary.instance.scanRoots,
        indexPath: directory,
        incremental: true,
        commit: () => completeLibraryRefresh(
              incremental: true,
              before: before,
              readCommitted: () => LibraryRefreshSnapshot.read(
                  File('${directory.path}/index.json')),
              invalidateCover: CoverCache.instance.invalidate,
              clearCovers: CoverCache.instance.clear,
              reload: () async {
                // initFromIndex preserves the live online collection. Do not read
                // playlists or lyric preferences from disk over an active user's edits.
                await AudioLibrary.initFromIndex();
                playlistTree
                    .refreshAudioReferences(AudioLibrary.instance.audioByPath);
                if (PlayService.isInitialized) {
                  PlayService.instance.playbackService.refreshAudioReferences(
                      AudioLibrary.instance.audioByPath);
                }
                await AudioSearchIndex.instance.ensureBuilt();
              },
            ));
    task.start();
    await task.completed;
    if (task.phase == LibraryRefreshPhase.cancelled) return;
    try {
      await LibraryHealthService(directory).recordScan(
          AudioLibrary.instance.scanRoots,
          failure: task.error == null ? null : '${task.error}');
    } catch (error) {
      LOGGER.w('[library health] $error');
    }
    if (task.error != null) throw task.error!;
  }

  Future<void> stop() async {
    final watch = _watch;
    if (watch == null) return;
    _watch = null;
    AppSettings.instance.libraryAutoRefresh.removeListener(_configure);
    AudioLibrary.changes.removeListener(_configure);
    await watch.dispose();
  }
}
