import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_auto_refresh.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/search/audio_search_index.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/windows_shell.dart';
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
  bool _usingCachedIndex = false;
  bool _scanCancelled = false;
  LibraryRefreshTask? _task;

  void _scanPhaseChanged() {
    if (mounted) setState(() {});
  }

  Stream<IndexActionState> _scan() async* {
    final index = File('${widget.indexPath.path}/index.json');
    final roots = <String>[];
    try {
      if (await index.exists()) {
        final raw = jsonDecode(await index.readAsString()) as Map;
        if (raw['roots'] is List) {
          roots.addAll((raw['roots'] as List).whereType<String>());
        }
        if (roots.isEmpty && raw['folders'] is List) {
          roots.addAll((raw['folders'] as List)
              .whereType<Map>()
              .map((folder) => folder['path'])
              .whereType<String>());
        }
      }
    } catch (error) {
      // Root labels are optional health metadata. Leave index recovery to the
      // existing scanner/loader instead of failing on this auxiliary read.
      LOGGER.w('[library health roots] $error');
    }
    String? failure;
    try {
      final task = LibraryRefreshTask.native(
          folders: roots,
          indexPath: widget.indexPath,
          incremental: true,
          commit: () async {
            await whenIndexUpdated();
            if (_error != null) throw _error!;
            return 0;
          });
      _task = task;
      task.addListener(_scanPhaseChanged);
      if (mounted) setState(() {});
      yield* task.stream;
    } catch (error) {
      failure = '$error';
      final cancelled = error is LibraryScanCancelled;
      if ((!failure.contains('INDEX_SCAN_INCOMPLETE') && !cancelled) ||
          !await index.exists()) {
        rethrow;
      }
      // Rust deliberately left the old complete snapshot intact. Open it so
      // an unplugged source doesn't prevent access to playlists and settings.
      _usingCachedIndex = true;
      if (cancelled) {
        failure = null;
        _scanCancelled = true;
      }
      await LibraryMutationGate.shared.run(whenIndexUpdated);
    } finally {
      try {
        if (!_scanCancelled) {
          await LibraryHealthService(widget.indexPath)
              .recordScan(roots, failure: failure);
        }
      } catch (error) {
        LOGGER.w('[library health] $error');
      }
    }
  }

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
        LyricDocumentStore.instance.load(),
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
      await WindowsShell.instance.markLibraryReady();
      LibraryAutoRefresh.instance.start();
      await _subscription?.cancel();
      if (mounted) {
        context.go(app_paths.START_PAGES[AppPreference.instance.startPage]);
        if (_usingCachedIndex) {
          showAppNotice(
              ui(_scanCancelled
                  ? '已取消扫描，正在使用上次曲库。'
                  : '部分音乐来源暂不可访问，已打开上次曲库。可在设置中查看来源状态或重定位目录。'),
              kind: AppNoticeKind.warning);
        }
      }
    } catch (error, stackTrace) {
      _showFailure(error, stackTrace);
    }
  }

  void _showFailure(Object error, StackTrace stackTrace) {
    LOGGER.e("[update index] $error", stackTrace: stackTrace);
    _settled = true;
    _error = error;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    updateIndexStream = _scan().asBroadcastStream();

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
    _task?.removeListener(_scanPhaseChanged);
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
                      _task?.phase == LibraryRefreshPhase.cancelling
                          ? ui('正在取消扫描')
                          : snapshot.data?.message == 'INDEX_PHASE_COMMITTING'
                              ? ui('正在提交曲库')
                              : ui("正在检查音乐索引"),
                      style: TextStyle(color: scheme.onSurface),
                    ),
                    if (_task != null && !_task!.isTerminal) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                          onPressed:
                              _task!.canCancel ? _task!.requestCancel : null,
                          child: Text(ui('取消扫描'))),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
