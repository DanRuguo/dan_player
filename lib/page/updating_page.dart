import 'package:dan_player/startup_progress.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_content_transition.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:dan_player/component/app_shape.dart';
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
import 'package:dan_player/statistics/statistics_display_service.dart';
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
    final task = _task;
    if (task != null) {
      StartupProgress.instance.scan(task.lastAction?.progress ?? 0,
          cancel: task.canCancel ? () => unawaited(task.requestCancel()) : null,
          cancelling: task.phase == LibraryRefreshPhase.cancelling);
    }
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
      _scanPhaseChanged();
      if (mounted) setState(() {});
      yield* task.stream;
    } catch (error) {
      failure = '$error';
      final cancelled = error is LibraryScanCancelled;
      if ((!failure.contains('INDEX_SCAN_INCOMPLETE') && !cancelled) ||
          !await index.exists()) {
        rethrow;
      }
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
      StartupProgress.instance.advance(StartupStage.loadingLibrary);
      await AudioLibrary.initFromIndex();
      await OnlineLibrary.instance.initialize();
      await PlaybackStatistics.instance.initialize();
      StartupProgress.instance.advance(StartupStage.playlists);
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
      StartupProgress.instance.advance(StartupStage.playback);
      await PlayService.instance.playbackService.restoreLastSessionOnce();
      await WindowsShell.instance.markLibraryReady();
      LibraryAutoRefresh.instance.start();
      await _subscription?.cancel();
      StartupProgress.instance.advance(StartupStage.ready);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(StatisticsDisplayService.instance.prewarmOnce());
      });
      WidgetsBinding.instance.ensureVisualUpdate();
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
    StartupProgress.instance.fail();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    updateIndexStream = _scan().asBroadcastStream();

    String? lastLoggedPhase;
    _subscription = updateIndexStream.listen(
      (action) {
        final phase = action.message;
        if (phase.isNotEmpty && phase != lastLoggedPhase) {
          lastLoggedPhase = phase;
          LOGGER.i('[update index] $phase');
        }
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = _error;

    return Container(
      width: 420.0,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.dialogRadius,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.44),
        ),
      ),
      child: error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.error_outline,
                      color: scheme.onErrorContainer, size: 28.0),
                ),
                const SizedBox(height: 14.0),
                Text(
                  ui("音乐索引无法读取"),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
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
                const SizedBox(height: 18.0),
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
                final statusLabel = _task?.phase == LibraryRefreshPhase.cancelling
                    ? ui('正在取消扫描')
                    : snapshot.data?.message == 'INDEX_PHASE_COMMITTING'
                        ? ui('正在提交曲库')
                        : ui("正在检查音乐索引");
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.library_music_outlined,
                        color: scheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 14),
                    AppContentTransition(
                      identity: statusLabel,
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: snapshot.data?.progress,
                      ),
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
