import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:desktop_lyric/ui_language.dart';

class UpdatingPage extends StatelessWidget {
  const UpdatingPage({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: AppEntrance(
          identity: 'library-startup-progress',
          child: FutureBuilder(
            future: getAppDataDir(),
            builder: (context, snapshot) {
              if (snapshot.data == null) {
                return const Center(
                  child: Text("Fail to get app data dir."),
                );
              }

              return UpdatingStateView(indexPath: snapshot.data!);
            },
          ),
        ),
      ),
    );
  }
}

class UpdatingStateView extends StatefulWidget {
  const UpdatingStateView({super.key, required this.indexPath});

  final Directory indexPath;

  @override
  State<UpdatingStateView> createState() => _UpdatingStateViewState();
}

class _UpdatingStateViewState extends State<UpdatingStateView> {
  late final Stream<IndexActionState> updateIndexStream;
  StreamSubscription? _subscription;
  Object? _error;
  bool _settled = false;

  Future<void> whenIndexUpdated() async {
    if (_settled) return;
    _settled = true;
    try {
      await AudioLibrary.initFromIndex();
      // 联网曲目必须先并入总乐库，随后统一迁移的歌单和播放会话才能正确解析
      // online:// 稳定标识，不会把它们误判为失效条目。
      await OnlineLibrary.instance.initialize();
      await PlaybackStatistics.instance.initialize();
      await Future.wait([
        readCustomAudioOrder(),
        readPlaylists(),
        readLyricSources(),
      ]);
      unawaited(AudioSearchIndex.instance.ensureBuilt());
      unawaited(
        CoverCache.instance.prune(
          AudioLibrary.instance.audioCollection.map(
            (audio) => CoverCacheEntry(audio.path, audio.modified,
                fingerprint: audio.coverFingerprint),
          ),
        ),
      );
      await PlayService.instance.playbackService.restoreLastSessionOnce();
      await _subscription?.cancel();
      if (mounted) {
        context.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
      }
    } catch (error, stackTrace) {
      _showFailure(error, stackTrace);
    }
  }

  void _showFailure(Object error, StackTrace stackTrace) {
    LOGGER.e("[update index] $error", stackTrace: stackTrace);
    _settled = true;
    if (mounted) {
      setState(() {
        _error = error;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    updateIndexStream = updateIndex(
      indexPath: widget.indexPath.path,
    ).asBroadcastStream();

    _subscription = updateIndexStream.listen(
      (action) {
        LOGGER.i("[update index] ${action.progress}: ${action.message}");
      },
      onDone: whenIndexUpdated,
      onError: (Object error, StackTrace stackTrace) {
        _showFailure(error, stackTrace);
        _subscription?.cancel();
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _settled = true;
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final error = _error;

    return SizedBox(
      width: 400.0,
      child: error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 36.0),
                const SizedBox(height: 12.0),
                Text(
                  ui("音乐索引无法读取"),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  "$error",
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16.0),
                FilledButton.icon(
                  onPressed: () => context.go(app_paths.WELCOMING_PAGE),
                  icon: const Icon(Icons.folder_open),
                  label: Text(ui("重新选择音乐文件夹")),
                ),
              ],
            )
          : StreamBuilder(
              stream: updateIndexStream,
              builder: (context, snapshot) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LinearProgressIndicator(
                      value: snapshot.data?.progress,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                    const SizedBox(height: 8.0),
                    Text(
                      snapshot.data?.message ?? ui("正在检查音乐索引"),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
