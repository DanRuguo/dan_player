import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_duration_correction.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/play_service/playback_modes.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/play_service/queue_navigation.dart';
import 'package:dan_player/play_service/queue_edits.dart';
import 'package:dan_player/play_service/queue_track_identity.dart';
import 'package:dan_player/play_service/segment_loop.dart';
import 'package:dan_player/play_service/track_resume_restore.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_util;

export 'package:dan_player/play_service/playback_modes.dart' show PlayMode;

/// A short-lived guard used while a local file is being removed from disk.
/// The active BASS stream must be released before Windows can reliably delete
/// it. If file deletion fails, [PlaybackService.cancelAudioDeletion] reopens
/// the same queue occurrence instead of leaving playback silently detached.
class PlaybackAudioDeletionTicket {
  PlaybackAudioDeletionTicket._({
    required this.path,
    required this.requestToken,
    required this.wasCurrent,
    required this.wasPending,
    required this.wasPlaying,
    required this.index,
    required this.position,
  });

  final String path;
  final int requestToken;
  final bool wasCurrent;
  final bool wasPending;
  final bool wasPlaying;
  final int index;
  final double position;
  bool _resolved = false;
}

/// 只通知 now playing 变更
class PlaybackService extends ChangeNotifier {
  final PlayService playService;

  static bool _sameAudioPath(String? left, String right) =>
      left != null && path_util.equals(left, right);

  static int _deletionQueueIndex(
    List<Audio> audios,
    String audioPath,
    int? preferred,
  ) {
    if (preferred != null &&
        preferred >= 0 &&
        preferred < audios.length &&
        path_util.equals(audios[preferred].path, audioPath)) {
      return preferred;
    }
    return audios
        .indexWhere((audio) => path_util.equals(audio.path, audioPath));
  }

  late StreamSubscription _playerStateStreamSub;
  late StreamSubscription _smtcEventStreamSub;
  late StreamSubscription _positionStreamSub;

  int _lastSmtcProgressMs = -1000;
  int _lastSessionProgressMs = -30000;

  PlaybackService(this.playService) {
    _playerStateStreamSub = _player.playbackEvents.listen((event) {
      if (_closed) return;
      // The native source remains playable while the next one resolves.
      // Late events from that old instance cannot settle the newly selected
      // request, update its statistics, or advance over it (including A-B-A).
      if (resolvingAudioPath.value != null || isChangingOutput.value) {
        diagnosticsRevision.value++;
        return;
      }
      if (event.problem != null) _lastProblem = event.problem;
      diagnosticsRevision.value++;
      if (event.problem != null && event.reason != null) {
        PlaybackStatistics.instance.pause();
        unawaited(_captureTrackResume(force: true));
        _syncPausedToSystem();
        showTextOnSnackBar(event.problem.toString(), kind: AppNoticeKind.error);
      }
      if (event.reason == PlaybackEndReason.userStop) {
        PlaybackStatistics.instance.finish(markCompleted: false);
        _syncPausedToSystem();
      }
      if (event.completed) {
        if (segmentLoop.enabled && canUseSegmentLoop) {
          _repeatSegment(resume: true);
          return;
        }
        PlaybackStatistics.instance.finish(markCompleted: true);
        unawaited(_captureTrackResume(force: true, completed: true));
        // An old track may finish while a user-selected source is still
        // opening. Do not let auto-next replace that newer explicit request.
        if (resolvingAudioPath.value == null) _autoNextAudio();
      }
    });

    _smtcEventStreamSub = _smtc.subscribeToControlEvents().listen((event) {
      switch (event) {
        case SMTCControlEvent.play:
          start();
          break;
        case SMTCControlEvent.pause:
          pause();
          break;
        case SMTCControlEvent.previous:
          lastAudio();
          break;
        case SMTCControlEvent.next:
          nextAudio();
          break;
        case SMTCControlEvent.unknown:
      }
    });

    _positionStreamSub = positionStream.listen((progress) {
      if (_closed ||
          resolvingAudioPath.value != null ||
          isChangingOutput.value) {
        return;
      }
      if (segmentLoop.enabled &&
          playerState == PlayerState.playing &&
          canUseSegmentLoop &&
          segmentLoop.targetForPosition(progress) != null) {
        _repeatSegment();
      }
      PlaybackStatistics.instance
          .tick(nowPlaying, playerState, playbackRate: _player.playbackRate);
      if (playerState == PlayerState.playing) {
        unawaited(_captureTrackResume(positionOverride: progress));
      }
      final progressMs = (progress * 1000).floor();
      if ((progressMs - _lastSmtcProgressMs).abs() >= 1000) {
        _lastSmtcProgressMs = progressMs;
        _smtc.updateTimeProperties(progress: progressMs);
      }
      if ((progressMs - _lastSessionProgressMs).abs() >= 30000) {
        _lastSessionProgressMs = progressMs;
        _schedulePlaybackStateSave(positionOverride: progress);
      }
    });
  }

  late final BassPlayer _player = _createPlayer();

  BassPlayer _createPlayer() {
    final features = AppSettings.instance.experience.value;
    final player = BassPlayer()
      ..wasapiExclusive = features.exclusiveOutput
      ..configureReplayGain(AppSettings.instance.replayGain.value)
      ..setEqGains(AppPreference.instance.playbackPref.eqGains)
      ..setEqEnabled(AppPreference.instance.playbackPref.eqEnabled);
    if (player.supportsPlaybackRate) {
      player.setPlaybackRate(features.playbackRate);
    }
    return player;
  }

  final _smtc = SmtcFlutter();
  final _pref = AppPreference.instance.playbackPref;

  late final _wasapiExclusive = ValueNotifier(_player.wasapiExclusive);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;
  final isChangingOutput = ValueNotifier(false);
  late final _playbackRate = ValueNotifier(_player.playbackRate);
  ValueNotifier<double> get playbackRate => _playbackRate;
  bool get supportsPlaybackRate => _player.supportsPlaybackRate;
  String? get tempoUnavailableReason => _player.tempoUnavailableReason;

  /// Apply immediately; the calling settings/menu surface persists the choice
  /// and can report a write failure without hiding a successful audio change.
  bool setPlaybackRate(double rate) {
    if (_closed) return false;
    try {
      PlaybackRate.validate(rate);
      PlaybackStatistics.instance
          .tick(nowPlaying, playerState, playbackRate: _player.playbackRate);
      if (!_player.setPlaybackRate(rate)) return false;
      _playbackRate.value = _player.playbackRate;
      AppSettings.instance.experience.value = AppSettings
          .instance.experience.value
          .copyWith(playbackRate: _player.playbackRate);
      PlaybackStatistics.instance
          .tick(nowPlaying, playerState, playbackRate: _player.playbackRate);
      playService.desktopLyricService.sendPlaybackTimelineMessage();
      return true;
    } catch (error, trace) {
      LOGGER.w('[playback rate] $error', stackTrace: trace);
      showTextOnSnackBar('调整播放速度失败：{0}', arguments: [error]);
      return false;
    }
  }

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    if (_closed) return;
    if (exclusive == _player.wasapiExclusive) return;
    if (resolvingAudioPath.value != null || isChangingOutput.value) {
      showTextOnSnackBar('请等待当前音乐加载完成后再切换输出模式');
      return;
    }
    final token = ++_sourceRequestToken;
    isChangingOutput.value = true;
    _player.cancelPendingSource();
    final current = nowPlaying;
    _loadingPlaylistIndex = _playlistIndex;
    isBuffering.value = current?.isOnline == true;
    resolvingAudioPath.value = current?.path;
    unawaited(_useExclusiveModeResolved(token, exclusive));
  }

  Future<void> _useExclusiveModeResolved(int token, bool exclusive) async {
    try {
      final applied = await _player.useExclusiveMode(exclusive);
      if (!_closed) _wasapiExclusive.value = _player.wasapiExclusive;
      if (applied && _isCurrentSourceRequest(token)) {
        AppSettings.instance.experience.value = AppSettings
            .instance.experience.value
            .copyWith(exclusiveOutput: _player.wasapiExclusive);
        try {
          await AppSettings.instance.saveSettings(throwOnError: true);
        } catch (error, trace) {
          LOGGER.w('[save output preference] $error', stackTrace: trace);
          if (_isCurrentSourceRequest(token)) {
            showTextOnSnackBar('音频输出已切换，但设置保存失败：{0}', arguments: [error]);
          }
        }
      }
    } catch (err, trace) {
      if (_isCurrentSourceRequest(token)) {
        _recordProblem(err, output: true);
        LOGGER.e('[change output mode] $err', stackTrace: trace);
        showTextOnSnackBar('切换音频输出失败：{0}', arguments: [err]);
      }
    } finally {
      if (!_closed) isChangingOutput.value = false;
      if (_isCurrentSourceRequest(token)) {
        isBuffering.value = false;
        resolvingAudioPath.value = null;
        _loadingPlaylistIndex = null;
      }
    }
  }

  late final _eqEnabled = ValueNotifier(_player.eqEnabled);
  ValueNotifier<bool> get eqEnabled => _eqEnabled;

  List<double> get eqGains => _player.eqGains;

  bool setEqEnabled(bool enabled) {
    final applied = _player.setEqEnabled(enabled);
    _eqEnabled.value = _player.eqEnabled;
    _pref.eqEnabled = _player.eqEnabled;
    return applied;
  }

  void setEqBandGain(int band, double gain) {
    _player.setEqBandGain(band, gain);
    _pref.eqGains = _player.eqGains;
    diagnosticsRevision.value++;
  }

  void applyEqGains(List<double> gains) {
    _player.setEqGains(gains);
    _pref.eqGains = _player.eqGains;
    diagnosticsRevision.value++;
  }

  Audio? nowPlaying;
  final diagnosticsRevision = ValueNotifier(0);
  PlaybackProblem? _lastProblem;

  /// A small on-demand snapshot. No path, title, provider identifier, token or
  /// upstream exception text is included in the default diagnostic export.
  Map<String, Object?> playbackDiagnostics() => {
        'schemaVersion': 1,
        'appVersion': AppSettings.version,
        'operatingSystem': Platform.operatingSystem,
        'phase': isChangingOutput.value
            ? 'changingOutput'
            : resolvingAudioPath.value != null
                ? 'loading'
                : playerState.name,
        'sourceKind': nowPlaying == null
            ? null
            : nowPlaying!.isCueTrack
                ? 'cue'
                : nowPlaying!.isOnline
                    ? 'online'
                    : 'local',
        'queueLength': playlist.value.length,
        'queueIndex': _playlistIndex,
        'error': _lastProblem?.toSafeJson(),
        'output': _player.outputDiagnostics(),
      };

  void _recordProblem(Object error, {bool output = false}) {
    _lastProblem = error is PlaybackProblem
        ? error
        : PlaybackProblem(
            output
                ? PlaybackProblemKind.deviceInitialization
                : error is OnlineMusicException
                    ? PlaybackProblemKind.sourceUnavailable
                    : PlaybackProblemKind.unknown,
            output ? '音频输出操作失败。' : '播放操作失败。');
    diagnosticsRevision.value++;
  }

  bool relinkLocalPath(String oldPath, String newPath) {
    if (_closed) return false;
    final applied = _player.relinkLocalPath(oldPath, newPath);
    if (applied) diagnosticsRevision.value++;
    return applied;
  }

  final ValueNotifier<bool> isBuffering = ValueNotifier(false);

  /// Path currently being resolved or opened, for both local and online audio.
  final ValueNotifier<String?> resolvingAudioPath = ValueNotifier(null);
  int _sourceRequestToken = 0;
  int _manualSeekRevision = 0;
  bool _resumeStorageErrorReported = false;
  DateTime? _resumeRetryAfter;
  bool _closed = false;
  Future<void>? _closeFuture;

  bool _isCurrentSourceRequest(int token) =>
      !_closed && token == _sourceRequestToken;

  int? _playlistIndex;
  int? _loadingPlaylistIndex;
  String? _deletingAudioPath;
  int get playlistIndex {
    final index = queueIndexForTrack(playlist.value, nowPlaying?.path,
        preferredIndex: _playlistIndex);
    return index < 0 ? 0 : index;
  }

  int get _navigationIndex {
    final pending = resolvingAudioPath.value;
    return queueIndexForTrack(playlist.value, pending ?? nowPlaying?.path,
        preferredIndex:
            pending == null ? _playlistIndex : _loadingPlaylistIndex);
  }

  final ValueNotifier<List<Audio>> playlist = ValueNotifier([]);
  List<Audio> _playlistBackup = [];
  ShuffleQueueCycle<Audio>? _shuffleCycle;
  final _queueEditHistory = QueueEditHistory<Audio>();
  final segmentLoop = SegmentLoopController();

  bool get canEditQueue =>
      !_closed &&
      resolvingAudioPath.value == null &&
      _deletingAudioPath == null &&
      !isChangingOutput.value;

  int get _currentQueueIndex =>
      queueIndexForTrack(playlist.value, nowPlaying?.path,
          preferredIndex: _playlistIndex);

  bool get canUndoQueueEdit =>
      canEditQueue &&
      _queueEditHistory.canUndo(
          playlist.value, _playlistBackup, _currentQueueIndex);

  void _applyQueueSnapshot(QueueSnapshot<Audio> snapshot) {
    _playlistIndex = snapshot.currentIndex < 0 ? null : snapshot.currentIndex;
    _playlistBackup = snapshot.backup;
    playlist.value = snapshot.items;
    _schedulePlaybackStateSave();
    notifyListeners();
  }

  void _commitQueueEdit(QueueEdit<Audio> edit, List<Audio> backup) {
    final before =
        QueueSnapshot(playlist.value, _playlistBackup, _currentQueueIndex);
    final after = QueueSnapshot(edit.items, backup, edit.currentIndex);
    _queueEditHistory.record(before, after);
    _applyQueueSnapshot(after);
  }

  /// Restore only queue membership/order. The active decoder, seek position,
  /// pause state and A-B loop are deliberately untouched.
  bool undoQueueEdit() {
    if (!canEditQueue) return false;
    final previous = _queueEditHistory.undo(
        playlist.value, _playlistBackup, _currentQueueIndex);
    if (previous == null) return false;
    _applyQueueSnapshot(previous);
    return true;
  }

  bool get canUseSegmentLoop =>
      canEditQueue &&
      nowPlaying?.isLocal == true &&
      length.isFinite &&
      length >= 1;

  void _repeatSegment({bool resume = false}) {
    final start = segmentLoop.start;
    if (start == null || !segmentLoop.enabled || !canUseSegmentLoop) return;
    try {
      _player.seek(start);
      if (resume) _player.start();
      _lastSmtcProgressMs = -1000;
      playService.lyricService.findCurrLyricLine();
    } catch (error, trace) {
      segmentLoop.setEnabled(false);
      LOGGER.w('[segment loop] $error', stackTrace: trace);
      showTextOnSnackBar('片段循环跳转失败，已关闭循环');
    }
  }

  bool setSegmentLoopEnabled(bool enabled) {
    if (!canUseSegmentLoop) return false;
    segmentLoop.setEnabled(enabled);
    if (segmentLoop.enabled) _repeatSegment();
    return segmentLoop.enabled;
  }

  /// Queue-only edits leave the current decoder, position and library intact.
  bool removeQueueItem(int index) {
    if (!canEditQueue) return false;
    final queue = playlist.value;
    final current = queueIndexForTrack(queue, nowPlaying?.path,
        preferredIndex: _playlistIndex);
    final edit = QueueEdit.remove(queue, current, index);
    if (edit == null) return false;
    final backup = shuffle.value
        ? List<Audio>.from(_playlistBackup)
        : List<Audio>.from(edit.items);
    if (shuffle.value) {
      final removed =
          backup.indexWhere((item) => item.path == queue[index].path);
      if (removed >= 0) backup.removeAt(removed);
    }
    _commitQueueEdit(edit, backup);
    return true;
  }

  bool moveQueueItemNext(int index) {
    if (!canEditQueue) return false;
    final current = queueIndexForTrack(playlist.value, nowPlaying?.path,
        preferredIndex: _playlistIndex);
    final edit = QueueEdit.moveNext(playlist.value, current, index);
    if (edit == null) return false;
    _commitQueueEdit(edit, shuffle.value ? _playlistBackup : edit.items);
    return true;
  }

  bool keepOnlyCurrentQueueItem() {
    if (!canEditQueue || nowPlaying == null) return false;
    final current = queueIndexForTrack(playlist.value, nowPlaying!.path,
        preferredIndex: _playlistIndex);
    if (current < 0 || playlist.value.length <= 1) return false;
    final kept = playlist.value[current];
    _commitQueueEdit(QueueEdit([kept], 0), [kept]);
    return true;
  }

  /// Remove equivalent entries without reopening the current occurrence.
  /// The same edit restores both visible and pre-shuffle order through undo.
  int deduplicateQueue() {
    if (!canEditQueue) return 0;
    final queue = playlist.value;
    final edit = QueueEdit.deduplicate(queue, _currentQueueIndex,
        keyOf: queueTrackIdentity);
    if (edit == null) return 0;
    final backup = shuffle.value
        ? QueueEdit.deduplicatedBackup(_playlistBackup, edit.items,
            keyOf: queueTrackIdentity)
        : edit.items;
    _commitQueueEdit(edit, backup);
    return queue.length - edit.items.length;
  }

  Timer? _stateSaveTimer;
  Future<void> _stateWrite = Future.value();
  Future<void>? _sessionRestoreFuture;

  void replaceAudioReference(String oldPath, Audio audio) {
    _queueEditHistory.mapItems((item) => item.path == oldPath ? audio : item);
    List<Audio> replaceIn(List<Audio> list) => [
          for (final item in list) item.path == oldPath ? audio : item,
        ];

    if (nowPlaying?.path == oldPath) {
      nowPlaying = audio;
    }
    playlist.value = replaceIn(playlist.value);
    _playlistBackup = replaceIn(_playlistBackup);
    _schedulePlaybackStateSave();
    notifyListeners();
  }

  void refreshAudioReferences(Map<String, Audio> audioByPath) {
    _queueEditHistory.mapItems((item) => audioByPath[item.path] ?? item);
    List<Audio> refresh(List<Audio> list) => [
          for (final item in list) audioByPath[item.path] ?? item,
        ];

    final nowPlayingPath = nowPlaying?.path;
    if (nowPlayingPath != null) {
      nowPlaying = audioByPath[nowPlayingPath] ?? nowPlaying;
    }
    playlist.value = refresh(playlist.value);
    _playlistBackup = refresh(_playlistBackup);
    if (nowPlayingPath != null) {
      final refreshedIndex = queueIndexForTrack(
        playlist.value,
        nowPlayingPath,
        preferredIndex: _playlistIndex,
      );
      if (refreshedIndex >= 0) {
        _playlistIndex = refreshedIndex;
      }
    }
    _schedulePlaybackStateSave();
    notifyListeners();
  }

  /// Release a matching active stream before the file-system deletion starts.
  /// Queue removal is deferred until [commitAudioDeletion], so a failed delete
  /// can restore the former track through [cancelAudioDeletion].
  Future<PlaybackAudioDeletionTicket> prepareAudioDeletion(
      String audioPath) async {
    final openingIndex = _loadingPlaylistIndex;
    final opening = openingIndex != null &&
            openingIndex >= 0 &&
            openingIndex < playlist.value.length
        ? playlist.value[openingIndex]
        : null;
    if ((nowPlaying?.isCueTrack == true &&
            _sameAudioPath(nowPlaying?.localFilePath, audioPath)) ||
        (opening?.isCueTrack == true &&
            _sameAudioPath(opening?.localFilePath, audioPath))) {
      throw const FormatException('整轨音频正在作为 CUE 分轨使用，请先切换歌曲后再删除。');
    }
    final wasCurrent = _sameAudioPath(nowPlaying?.path, audioPath);
    final wasPending = _sameAudioPath(resolvingAudioPath.value, audioPath);
    final index = _deletionQueueIndex(
      playlist.value,
      audioPath,
      wasPending ? _loadingPlaylistIndex : _playlistIndex,
    );
    final state = playerState;
    final wasPlaying = state == PlayerState.playing ||
        state == PlayerState.stalled ||
        state == PlayerState.pausedDevice;
    final savedPosition = wasCurrent ? position : 0.0;
    _deletingAudioPath = audioPath;
    if (wasCurrent) segmentLoop.clear();

    if (wasCurrent || wasPending) {
      _sourceRequestToken += 1;
      OnlineMusicService.instance.cancelPendingStreamResolution();
      _player.cancelPendingSource();
      isBuffering.value = false;
      resolvingAudioPath.value = null;
      _loadingPlaylistIndex = null;
    }
    final deletionToken = _sourceRequestToken;
    if (wasCurrent) {
      PlaybackStatistics.instance.finish(markCompleted: false);
    }
    _player.freeSourceIfPath(audioPath);
    if (wasPending) {
      await _player.waitForPendingFileOpen(audioPath);
      _player.freeSourceIfPath(audioPath);
    }

    return PlaybackAudioDeletionTicket._(
      path: audioPath,
      requestToken: deletionToken,
      wasCurrent: wasCurrent,
      wasPending: wasPending,
      wasPlaying: wasPlaying,
      index: index,
      position: savedPosition,
    );
  }

  /// Remove every queue occurrence after the physical file is gone. If the
  /// deleted song was active, keep the queue moving at the same logical slot.
  void commitAudioDeletion(PlaybackAudioDeletionTicket ticket) {
    if (ticket._resolved) return;
    _queueEditHistory.clear();
    ticket._resolved = true;
    if (_sameAudioPath(_deletingAudioPath, ticket.path)) {
      _deletingAudioPath = null;
    }

    final filtered = [
      for (final audio in playlist.value)
        if (!path_util.equals(audio.path, ticket.path) &&
            !path_util.equals(audio.localFilePath, ticket.path))
          audio,
    ];
    _playlistBackup = [
      for (final audio in _playlistBackup)
        if (!path_util.equals(audio.path, ticket.path) &&
            !path_util.equals(audio.localFilePath, ticket.path))
          audio,
    ];
    playlist.value = filtered;

    final stillDisplaysDeletedSource =
        _sameAudioPath(nowPlaying?.path, ticket.path);
    final stillOwnsDetachedSource = ticket.wasCurrent &&
        ticket.requestToken == _sourceRequestToken &&
        stillDisplaysDeletedSource;
    if (stillDisplaysDeletedSource) {
      nowPlaying = null;
      _playlistIndex = null;
      if (stillOwnsDetachedSource && filtered.isNotEmpty) {
        final nextIndex = ticket.index.clamp(0, filtered.length - 1);
        if (ticket.wasPlaying) {
          _loadAndPlay(nextIndex, filtered);
        } else {
          unawaited(_loadPaused(nextIndex, filtered, 0));
        }
      } else if (stillOwnsDetachedSource) {
        _smtc.updateState(state: SMTCState.paused);
      }
    } else {
      final currentPath = nowPlaying?.path;
      final refreshed = queueIndexForTrack(
        filtered,
        currentPath,
        preferredIndex: _playlistIndex,
      );
      _playlistIndex = refreshed < 0 ? null : refreshed;
    }

    _schedulePlaybackStateSave();
    notifyListeners();
  }

  /// Restore playback when the operating system refuses to delete the file.
  void cancelAudioDeletion(PlaybackAudioDeletionTicket ticket) {
    if (ticket._resolved) return;
    ticket._resolved = true;
    if (_sameAudioPath(_deletingAudioPath, ticket.path)) {
      _deletingAudioPath = null;
    }
    if (!ticket.wasCurrent ||
        ticket.requestToken != _sourceRequestToken ||
        !_sameAudioPath(nowPlaying?.path, ticket.path) ||
        ticket.index < 0 ||
        ticket.index >= playlist.value.length) {
      if (ticket.wasCurrent &&
          _sameAudioPath(nowPlaying?.path, ticket.path) &&
          ticket.requestToken != _sourceRequestToken) {
        nowPlaying = null;
        _playlistIndex = null;
        notifyListeners();
      }
      return;
    }
    unawaited(_loadPaused(
      ticket.index,
      playlist.value,
      ticket.position,
      resumeAfterLoad: ticket.wasPlaying,
    ));
  }

  late final _playMode = ValueNotifier(_pref.playMode);
  ValueNotifier<PlayMode> get playMode => _playMode;

  void setPlayMode(PlayMode playMode) {
    if (_closed || this.playMode.value == playMode) return;
    this.playMode.value = playMode;
    _pref.playMode = playMode;
    _scheduleModePreferenceSave();
  }

  late final _shuffle = ValueNotifier(_pref.shuffle ?? false);
  ValueNotifier<bool> get shuffle => _shuffle;

  Timer? _modeSaveTimer;
  Future<void> _modeWrite = Future.value();

  void _scheduleModePreferenceSave() {
    _modeSaveTimer?.cancel();
    _modeSaveTimer = Timer(const Duration(milliseconds: 150), () {
      _modeSaveTimer = null;
      _writeModePreferences();
    });
  }

  void _writeModePreferences() {
    _modeWrite = _modeWrite.then((_) => AppPreference.instance.save(),
        onError: (_) => AppPreference.instance.save());
  }

  Timer? _sleepTicker;
  DateTime? _sleepDeadline;
  final ValueNotifier<Duration?> sleepTimerRemaining = ValueNotifier(null);
  final ValueNotifier<bool> stopAfterCurrent = ValueNotifier(false);

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    if (duration <= Duration.zero) return;

    _sleepDeadline = DateTime.now().add(duration);
    sleepTimerRemaining.value = duration;
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final deadline = _sleepDeadline;
      if (deadline == null) {
        cancelSleepTimer();
        return;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        sleepTimerRemaining.value = remaining;
        return;
      }

      cancelSleepTimer();
      if (playerState == PlayerState.playing) pause();
    });
  }

  void cancelSleepTimer() {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    _sleepDeadline = null;
    sleepTimerRemaining.value = null;
  }

  double get length {
    final value = _player.length;
    return value.isFinite && value >= 0
        ? value
        : (nowPlaying?.duration ?? 0).toDouble();
  }

  double get position => _player.position;

  PlayerState get playerState => _player.playerState;

  double get volumeDsp => _player.volumeDsp;

  ReplayGainTags get replayGainTags => _player.replayGainTags;

  /// Audio application only; the settings surface persists a successful choice.
  bool configureReplayGain(ReplayGainPreferences preferences) {
    if (_closed) return false;
    final applied = _player.configureReplayGain(preferences);
    if (applied) diagnosticsRevision.value++;
    return applied;
  }

  /// 修改解码时的音量（不影响 Windows 系统音量）
  void setVolumeDsp(double volume) {
    _player.setVolumeDsp(volume);
    _pref.volumeDsp = volume;
    diagnosticsRevision.value++;
  }

  Stream<double> get positionStream => _player.positionStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<List<double>> get spectrumStream => _player.spectrumStream;

  Stream<List<double>> get frequencySpectrumStream =>
      _player.frequencySpectrumStream;

  List<double> get spectrumLevels => _player.spectrumLevels;

  List<double> get frequencySpectrumLevels => _player.frequencySpectrumLevels;

  /// Capture values synchronously before replacing a source. While a source
  /// is opening the decoder and nowPlaying may briefly describe different
  /// files, so progress notifications must not create a mixed snapshot.
  Future<void> _captureTrackResume({
    bool force = false,
    bool completed = false,
    double? positionOverride,
  }) async {
    final audio = nowPlaying;
    final preferences = AppSettings.instance.trackResume.value;
    if (_closed ||
        audio == null ||
        resolvingAudioPath.value != null ||
        segmentLoop.enabled) {
      return;
    }
    if (!force && _resumeRetryAfter?.isAfter(DateTime.now()) == true) return;
    final duration = length;
    if (!preferences.accepts(local: audio.isLocal, duration: duration)) return;
    final capturedPosition = positionOverride ?? position;
    final track = audio.path;
    final stableTrackId = audio.stableTrackId;
    try {
      final store = await TrackResumeStore.instance;
      await store.remember(
          track: track,
          stableTrackId: stableTrackId,
          position: capturedPosition,
          duration: duration,
          preferences: preferences,
          force: force,
          completed: completed);
    } catch (error, trace) {
      _reportResumeStorageError(error, trace);
    }
  }

  void _reportResumeStorageError(Object error, StackTrace trace) {
    // A locked/full disk must not interrupt audio or flood one message per
    // progress tick. Settings still provide explicit clear/save error output.
    _resumeRetryAfter = DateTime.now().add(const Duration(seconds: 30));
    if (_resumeStorageErrorReported) return;
    _resumeStorageErrorReported = true;
    LOGGER.w('[track resume] $error', stackTrace: trace);
  }

  /// Resolve/open first; only a successful native source becomes nowPlaying.
  void _loadAndPlay(int audioIndex, List<Audio> playlist,
      {bool allowTrackResume = false}) {
    if (_closed) return;
    unawaited(_captureTrackResume(force: true));
    segmentLoop.clear();
    if (audioIndex >= 0 &&
        audioIndex < playlist.length &&
        _sameAudioPath(
            _deletingAudioPath, playlist[audioIndex].localFilePath)) {
      return;
    }
    final token = ++_sourceRequestToken;
    OnlineMusicService.instance.cancelPendingStreamResolution();
    _player.cancelPendingSource();
    _queueEditHistory.clear();
    unawaited(_loadAndPlayResolved(token, audioIndex, playlist,
        allowTrackResume: allowTrackResume, seekRevision: _manualSeekRevision));
  }

  Future<void> _loadAndPlayResolved(
    int token,
    int audioIndex,
    List<Audio> playlist, {
    required bool allowTrackResume,
    required int seekRevision,
  }) async {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) {
        throw RangeError.index(audioIndex, playlist, "audioIndex");
      }
      final target = playlist[audioIndex];
      _loadingPlaylistIndex = audioIndex;
      isBuffering.value = target.isOnline;
      resolvingAudioPath.value = target.path;
      final source = target.isOnline
          ? (await OnlineMusicService.instance.resolveStreamUrl(target))
              .toString()
          : target.localFilePath;
      if (!_isCurrentSourceRequest(token)) return;
      final applied = await _player.setSource(source,
          isUrl: target.isOnline,
          segment: target.cueTrack == null
              ? null
              : AudioSegment(
                  target.cueTrack!.startSeconds, target.cueTrack!.endSeconds));
      if (!applied || !_isCurrentSourceRequest(token)) return;
      if (allowTrackResume && target.isLocal) {
        try {
          final preferences = AppSettings.instance.trackResume.value;
          final nativeDuration = length;
          if (preferences.accepts(local: true, duration: nativeDuration)) {
            await restoreRememberedTrackPosition(
              read: () async => (await TrackResumeStore.instance)
                  .resumePosition(
                      track: target.path,
                      stableTrackId: target.stableTrackId,
                      duration: nativeDuration,
                      preferences: preferences),
              canApply: () =>
                  _isCurrentSourceRequest(token) &&
                  seekRevision == _manualSeekRevision &&
                  AppSettings.instance.trackResume.value == preferences &&
                  !segmentLoop.enabled,
              seek: _player.seek,
            );
          }
        } catch (error, trace) {
          _reportResumeStorageError(error, trace);
        }
      }
      if (!_isCurrentSourceRequest(token)) return;
      if (nowPlaying != null) {
        PlaybackStatistics.instance.finish(markCompleted: false);
      }
      _playlistIndex = queueIndexForTrack(this.playlist.value, target.path,
          preferredIndex: _loadingPlaylistIndex);
      nowPlaying = target;
      _lastProblem = null;
      // BASS has successfully opened the real byte stream at this point. Its
      // duration is authoritative when a misleading extension or damaged tag
      // header made the library scanner report zero/a conflicting value. The
      // correction is coalesced and persisted off the playback path.
      _observeNativeDuration(target);
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      _player.start();
      PlaybackStatistics.instance
          .start(nowPlaying!, playbackRate: _player.playbackRate);
      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);

      _lastSmtcProgressMs = -1000;
      _smtc.updateState(state: SMTCState.playing);
      _smtc.updateDisplay(
        title: nowPlaying!.displayTitle,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.localFilePath,
      );

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend || !_isCurrentSourceRequest(token)) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });

      _lastSessionProgressMs = (position * 1000).floor();
      _smtc.updateTimeProperties(progress: _lastSessionProgressMs);
      _schedulePlaybackStateSave(positionOverride: position);
    } catch (err, trace) {
      LOGGER.e("[load and play] $err");
      LOGGER.d("[load and play] trace", stackTrace: trace);
      if (_isCurrentSourceRequest(token)) {
        _recordProblem(err);
        showTextOnSnackBar(
          err is OnlineMusicException ? err.message : "播放失败：$err",
        );
        if (playerState != PlayerState.playing) {
          _smtc.updateState(state: SMTCState.paused);
          notifyListeners();
        }
      }
    } finally {
      if (_isCurrentSourceRequest(token)) {
        isBuffering.value = false;
        resolvingAudioPath.value = null;
        _loadingPlaylistIndex = null;
      }
    }
  }

  SavedPlaybackState? _snapshotState({double? positionOverride}) {
    if (nowPlaying == null || playlist.value.isEmpty) return null;
    final currentIndex = queueIndexForTrack(playlist.value, nowPlaying?.path,
        preferredIndex: _playlistIndex);
    // A newly selected queue may be visible while its first track is opening.
    // Never persist the old track's position against an unrelated queue entry.
    if (currentIndex < 0) return null;
    return SavedPlaybackState(
      queuePaths: [for (final audio in playlist.value) audio.path],
      backupPaths: [for (final audio in _playlistBackup) audio.path],
      index: currentIndex,
      position: positionOverride ?? position,
      shuffle: shuffle.value,
      cueTracks: {
        for (final audio in [...playlist.value, ..._playlistBackup])
          if (audio.isCueTrack) audio.path: audio,
      }.values.toList(growable: false),
    );
  }

  Future<void> _savePlaybackState({double? positionOverride}) {
    final state = _snapshotState(positionOverride: positionOverride);
    if (state == null) return Future.value();
    _stateWrite = _stateWrite.then(
      (_) => PlaybackStateStore.save(state),
      onError: (_) => PlaybackStateStore.save(state),
    );
    return _stateWrite;
  }

  /// Commit the latest in-memory queue and position without stopping playback.
  ///
  /// Backup creation uses this to take a complete persisted snapshot instead
  /// of racing the normal 250 ms debounce.
  Future<void> flushPlaybackState() async {
    _stateSaveTimer?.cancel();
    _stateSaveTimer = null;
    if (!_closed) {
      await _captureTrackResume(force: true);
      await _savePlaybackState();
    }
    await _stateWrite;
  }

  void _schedulePlaybackStateSave({double? positionOverride}) {
    if (_closed) return;
    _stateSaveTimer?.cancel();
    _stateSaveTimer = Timer(const Duration(milliseconds: 250), () {
      _stateSaveTimer = null;
      unawaited(
        _savePlaybackState(positionOverride: positionOverride),
      );
    });
  }

  /// Every startup caller waits for the same source-open attempt to settle.
  /// In particular, Windows playback tasks must not run against a queue whose
  /// saved source is still opening in the background.
  Future<void> restoreLastSessionOnce() =>
      _sessionRestoreFuture ??= _restoreLastSession();

  Future<void> _restoreLastSession() async {
    if (_closed ||
        !AppSettings.instance.restoreLastSession ||
        nowPlaying != null) {
      return;
    }

    final restoreToken = _sourceRequestToken;
    final saved = await PlaybackStateStore.load();
    if (!_isCurrentSourceRequest(restoreToken) ||
        saved == null ||
        nowPlaying != null) {
      return;
    }

    final byPath = <String, Audio>{
      ...AudioLibrary.instance.audioByPath,
      for (final audio in saved.cueTracks) audio.path: audio,
      for (final list in PLAYLISTS)
        for (final audio in list.flattenAudios())
          if (audio.isCueTrack) audio.path: audio,
    };
    List<Audio> resolve(List<String> paths) => [
          for (final path in paths)
            if (byPath[path] != null) byPath[path]!,
        ];

    final queue = resolve(saved.queuePaths);
    if (queue.isEmpty) return;
    final backup = resolve(saved.backupPaths);

    final restoredIndex = queueIndexAfterFiltering(
      saved.queuePaths,
      saved.index,
      keepPath: byPath.containsKey,
    );
    final hasSavedOccurrence = restoredIndex >= 0;
    // If that occurrence disappeared, start the first surviving item from the
    // beginning, never apply another song's saved progress to it.
    var index = hasSavedOccurrence ? restoredIndex : 0;

    _playlistBackup = backup.isEmpty ? List.from(queue) : backup;
    final desiredShuffle = _pref.shuffle ?? saved.shuffle;
    var restoredQueue = queue;
    if (saved.shuffle && !desiredShuffle) {
      index = queueOccurrenceIndex(queue, index, _playlistBackup,
          keyOf: (audio) => audio.path);
      // A corrupt legacy backup must never discard the saved active entry.
      if (index >= 0) {
        restoredQueue = List.of(_playlistBackup);
      } else {
        index = hasSavedOccurrence ? restoredIndex : 0;
      }
    } else if (!saved.shuffle && desiredShuffle) {
      final cycle = ShuffleQueueCycle(queue, startIndex: index);
      _shuffleCycle = cycle;
      _playlistBackup = cycle.source;
      restoredQueue = cycle.items;
      index = 0;
    }
    playlist.value = restoredQueue;
    shuffle.value = desiredShuffle;
    _pref.shuffle = desiredShuffle;
    _scheduleModePreferenceSave();
    var canRestorePosition = hasSavedOccurrence;
    final restoredTrack = restoredQueue[index];
    if (restoredTrack.isCueTrack) {
      Audio? originalCue;
      for (final audio in saved.cueTracks) {
        if (audio.path == restoredTrack.path) {
          originalCue = audio;
          break;
        }
      }
      canRestorePosition = canRestorePosition &&
          sameCueResumeSegment(originalCue?.cueTrack, restoredTrack.cueTrack!);
    }
    await _loadPaused(
        index, restoredQueue, canRestorePosition ? saved.position : 0.0);
  }

  Future<void> _loadPaused(
    int audioIndex,
    List<Audio> playlist,
    double savedPosition, {
    bool resumeAfterLoad = false,
  }) {
    if (_closed) return Future.value();
    unawaited(_captureTrackResume(force: true));
    _queueEditHistory.clear();
    segmentLoop.clear();
    final token = ++_sourceRequestToken;
    OnlineMusicService.instance.cancelPendingStreamResolution();
    _player.cancelPendingSource();
    return _loadPausedResolved(
      token,
      audioIndex,
      playlist,
      savedPosition,
      resumeAfterLoad: resumeAfterLoad,
    );
  }

  Future<void> _loadPausedResolved(
    int token,
    int audioIndex,
    List<Audio> playlist,
    double savedPosition, {
    required bool resumeAfterLoad,
  }) async {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) {
        throw RangeError.index(audioIndex, playlist, 'audioIndex');
      }
      final target = playlist[audioIndex];
      _loadingPlaylistIndex = audioIndex;
      isBuffering.value = target.isOnline;
      resolvingAudioPath.value = target.path;
      final source = target.isOnline
          ? (await OnlineMusicService.instance.resolveStreamUrl(target))
              .toString()
          : target.localFilePath;
      if (!_isCurrentSourceRequest(token)) return;
      final applied = await _player.setSource(source,
          isUrl: target.isOnline,
          segment: target.cueTrack == null
              ? null
              : AudioSegment(
                  target.cueTrack!.startSeconds, target.cueTrack!.endSeconds));
      if (!applied || !_isCurrentSourceRequest(token)) return;
      _playlistIndex = queueIndexForTrack(this.playlist.value, target.path,
          preferredIndex: _loadingPlaylistIndex);
      nowPlaying = target;
      _lastProblem = null;
      _observeNativeDuration(target);
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
      playService.lyricService.updateLyric();

      var restoredPosition =
          savedPosition > 0 && savedPosition < length ? savedPosition : 0.0;
      if (restoredPosition > 0) {
        try {
          _player.seek(restoredPosition);
        } catch (err, trace) {
          restoredPosition = 0;
          LOGGER.w('[restore session] 无法恢复播放位置：$err', stackTrace: trace);
          showTextOnSnackBar('已恢复歌曲，但原播放位置暂不可用');
        }
      }
      if (resumeAfterLoad) {
        _player.start();
        PlaybackStatistics.instance
            .start(nowPlaying!, playbackRate: _player.playbackRate);
      }

      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);
      _lastSmtcProgressMs = (restoredPosition * 1000).floor();
      _lastSessionProgressMs = _lastSmtcProgressMs;
      _smtc.updateState(
          state: resumeAfterLoad ? SMTCState.playing : SMTCState.paused);
      _smtc.updateDisplay(
        title: nowPlaying!.displayTitle,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.localFilePath,
      );
      _smtc.updateTimeProperties(progress: _lastSmtcProgressMs);
      _schedulePlaybackStateSave(positionOverride: restoredPosition);

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend || !_isCurrentSourceRequest(token)) return;
        playService.desktopLyricService.sendPlayerStateMessage(resumeAfterLoad);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
    } catch (err, trace) {
      if (!_isCurrentSourceRequest(token)) return;
      _recordProblem(err);
      // A failed/stale restore must never clear a successfully opened newer
      // song. Native source replacement itself is transactional as well.
      LOGGER.e("[restore session] $err", stackTrace: trace);
      showTextOnSnackBar(
          err is OnlineMusicException ? err.message : '恢复播放失败：$err');
    } finally {
      if (_isCurrentSourceRequest(token)) {
        isBuffering.value = false;
        resolvingAudioPath.value = null;
        _loadingPlaylistIndex = null;
      }
    }
  }

  void _observeNativeDuration(Audio audio) {
    if (audio.isCueTrack) {
      audio.duration = _player.length.floor();
      return;
    }
    if (audio.isLocal) {
      audioDurationCorrections.observe(audio, _player.length);
    }
  }

  /// 播放当前播放列表的第几项，只能用在播放列表界面
  void playIndexOfPlaylist(int audioIndex) {
    if (audioIndex < 0 || audioIndex >= playlist.value.length) return;
    _loadAndPlay(audioIndex, playlist.value, allowTrackResume: true);
  }

  /// 播放playlist[audioIndex]并设置播放列表为playlist
  void play(int audioIndex, List<Audio> playlist) {
    if (audioIndex < 0 || audioIndex >= playlist.length) return;
    if (_sameAudioPath(
        _deletingAudioPath, playlist[audioIndex].localFilePath)) {
      return;
    }

    if (shuffle.value) {
      if (sameQueuePool(_playlistBackup, playlist,
          keyOf: (audio) => audio.path)) {
        final backupIndex = queueOccurrenceIndex(
            playlist, audioIndex, _playlistBackup,
            keyOf: (audio) => audio.path);
        final cycle = _shuffleCycle;
        final indexInCycle = cycle?.appliesTo(
                    this.playlist.value, _playlistBackup,
                    sameItem: (left, right) => left.path == right.path) ==
                true
            ? cycle!.queueIndex(backupIndex)
            : queueOccurrenceIndex(playlist, audioIndex, this.playlist.value,
                keyOf: (audio) => audio.path);
        if (indexInCycle >= 0) {
          _loadAndPlay(indexInCycle, this.playlist.value,
              allowTrackResume: true);
          return;
        }
      }

      _buildShuffleCycle(playlist, startIndex: audioIndex);
      _loadAndPlay(0, this.playlist.value, allowTrackResume: true);
    } else {
      this.playlist.value = List.from(playlist);
      _playlistBackup = List.from(playlist);
      _loadAndPlay(audioIndex, this.playlist.value, allowTrackResume: true);
    }
  }

  void shuffleAndPlay(List<Audio> audios) {
    if (_closed || audios.isEmpty) return;
    _buildShuffleCycle(audios);
    shuffle.value = true;
    _pref.shuffle = true;
    _scheduleModePreferenceSave();

    _loadAndPlay(0, playlist.value);
  }

  /// 下一首播放
  void addToNext(Audio audio) {
    if (!enqueueAudios([audio], next: true)) {
      showTextOnSnackBar('歌曲正在加载，请稍后重试');
    }
  }

  /// Batch insertion preserves the selected display order and current decoder.
  /// With an empty queue, match the existing single-track play-next behavior.
  bool enqueueAudios(List<Audio> audios, {bool next = false}) {
    if (!canEditQueue || audios.isEmpty) return false;
    final additions = List<Audio>.of(audios);
    if (playlist.value.isEmpty) {
      play(0, additions);
      return true;
    }
    final edit = QueueEdit.insert(playlist.value, _navigationIndex, additions,
        next: next);
    final backup = shuffle.value
        ? [..._playlistBackup, ...additions]
        : List<Audio>.of(edit.items);
    _commitQueueEdit(edit, backup);
    return true;
  }

  void useShuffle(bool flag) {
    if (_closed) return;
    // Persist an explicit empty-queue choice, even when it is already the
    // default; a later legacy-session load must not overwrite this action.
    _pref.shuffle = flag;
    _scheduleModePreferenceSave();
    if (flag == shuffle.value) return;
    _queueEditHistory.clear();

    if (flag) {
      final queue = playlist.value;
      final anchor =
          _currentQueueIndex >= 0 ? _currentQueueIndex : _navigationIndex;
      _buildShuffleCycle(queue, startIndex: anchor);
      shuffle.value = true;
    } else {
      final source = _playlistBackup.isEmpty ? playlist.value : _playlistBackup;
      final currentIndex = _indexInShuffleSource(_currentQueueIndex, source);
      final pendingIndex = _indexInShuffleSource(_navigationIndex, source);
      _playlistIndex = currentIndex < 0 ? null : currentIndex;
      if (resolvingAudioPath.value != null) {
        _loadingPlaylistIndex = pendingIndex < 0 ? null : pendingIndex;
      }
      _shuffleCycle = null;
      playlist.value = List.of(source);
      shuffle.value = false;
    }
    _schedulePlaybackStateSave();
    notifyListeners();
  }

  int _indexInShuffleSource(int index, List<Audio> source) {
    final cycle = _shuffleCycle;
    if (cycle?.appliesTo(playlist.value, source,
            sameItem: (left, right) => left.path == right.path) ==
        true) {
      return cycle!.sourceIndex(index);
    }
    return queueOccurrenceIndex(playlist.value, index, source,
        keyOf: (audio) => audio.path);
  }

  void _buildShuffleCycle(List<Audio> source,
      {int? startIndex, String? avoidFirstPath}) {
    if (source.isEmpty) return;
    _queueEditHistory.clear();
    final currentSourceIndex =
        _indexInShuffleSource(_currentQueueIndex, source);
    final pendingSourceIndex = _indexInShuffleSource(_navigationIndex, source);
    final cycle = ShuffleQueueCycle<Audio>(source,
        startIndex: startIndex,
        avoidFirst: avoidFirstPath == null
            ? null
            : (audio) => audio.path == avoidFirstPath);
    final currentIndex = cycle.queueIndex(currentSourceIndex);
    _playlistIndex = currentIndex < 0 ? null : currentIndex;
    if (resolvingAudioPath.value != null) {
      final pendingIndex = cycle.queueIndex(pendingSourceIndex);
      _loadingPlaylistIndex = pendingIndex < 0 ? null : pendingIndex;
    }
    _shuffleCycle = cycle;
    _playlistBackup = cycle.source;
    playlist.value = cycle.items;
  }

  bool _advanceQueue({required bool automatic}) {
    final currentIndex = _navigationIndex;
    final step = nextQueueAdvance(
        length: playlist.value.length,
        currentIndex: currentIndex,
        playMode: playMode.value,
        shuffle: shuffle.value,
        automatic: automatic);
    if (step.index == null) return false;
    if (step.newShuffleCycle) {
      final currentPath =
          currentIndex >= 0 && currentIndex < playlist.value.length
              ? playlist.value[currentIndex].path
              : null;
      final source = _playlistBackup.isEmpty ? playlist.value : _playlistBackup;
      _buildShuffleCycle(source, avoidFirstPath: currentPath);
    }
    _loadAndPlay(step.index!, playlist.value);
    return true;
  }

  void _syncPausedToSystem() {
    final token = _sourceRequestToken;
    _smtc.updateState(state: SMTCState.paused);
    playService.desktopLyricService.canSendMessage.then((canSend) {
      if (canSend &&
          _isCurrentSourceRequest(token) &&
          playerState != PlayerState.playing) {
        playService.desktopLyricService.sendPlayerStateMessage(false);
      }
    });
  }

  void _autoNextAudio() {
    if (stopAfterCurrent.value) {
      stopAfterCurrent.value = false;
      _syncPausedToSystem();
      return;
    }

    if (!_advanceQueue(automatic: true)) _syncPausedToSystem();
  }

  /// 手动下一曲时默认循环播放列表
  void nextAudio() => _advanceQueue(automatic: false);

  /// 手动上一曲时默认循环播放列表
  void lastAudio() {
    if (playlist.value.isEmpty) return;

    int newIndex = _navigationIndex - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  /// 暂停
  void pause() {
    if (_closed) return;
    try {
      PlaybackStatistics.instance
          .tick(nowPlaying, playerState, playbackRate: _player.playbackRate);
      _player.pause();
      unawaited(_captureTrackResume(force: true));
      PlaybackStatistics.instance.pause();
      _syncPausedToSystem();
      unawaited(_savePlaybackState());
    } catch (err) {
      _recordProblem(err);
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    if (_closed) return;
    try {
      if (nowPlaying == null) return;
      _player.start();
      if (playerState != PlayerState.playing &&
          playerState != PlayerState.stalled) {
        return;
      }
      final current = nowPlaying;
      if (current != null) {
        PlaybackStatistics.instance
            .start(current, playbackRate: _player.playbackRate);
      }
      _smtc.updateState(state: SMTCState.playing);
      final token = _sourceRequestToken;
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend ||
            !_isCurrentSourceRequest(token) ||
            playerState != PlayerState.playing) {
          return;
        }

        playService.desktopLyricService.sendPlayerStateMessage(true);
      });
    } catch (err) {
      _recordProblem(err, output: true);
      _syncPausedToSystem();
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 再次播放。在顺序播放完最后一曲时再次按播放时使用。
  /// 与 [start] 的差别在于它会通知重绘组件
  void playAgain() {
    if (playlist.value.isEmpty) return;
    final index = _navigationIndex;
    _loadAndPlay(index < 0 ? 0 : index, playlist.value);
  }

  void seek(double position) {
    if (_closed) return;
    _manualSeekRevision++;
    segmentLoop.manualSeek(position);
    try {
      _player.seek(position);
      unawaited(_captureTrackResume(force: true, positionOverride: position));
      _lastSmtcProgressMs = -1000;
      playService.lyricService.findCurrLyricLine();
      _schedulePlaybackStateSave(positionOverride: position);
    } catch (error, trace) {
      LOGGER.w('[seek] $error', stackTrace: trace);
      showTextOnSnackBar(nowPlaying?.isOnline == true
          ? '暂时无法跳到此位置，在线音频可能尚未缓冲完成'
          : '调整播放位置失败，请重新打开歌曲后重试');
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    final resumeWrite = _captureTrackResume(force: true);
    _closed = true;
    _queueEditHistory.clear();
    _sourceRequestToken += 1;
    OnlineMusicService.instance.cancelPendingStreamResolution();
    _player.cancelPendingSource();
    isBuffering.value = false;
    resolvingAudioPath.value = null;
    _stateSaveTimer?.cancel();
    _stateSaveTimer = null;
    if (_modeSaveTimer != null) {
      _modeSaveTimer!.cancel();
      _modeSaveTimer = null;
      _writeModePreferences();
    }
    final snapshot = _snapshotState();
    cancelSleepTimer();
    if (snapshot != null) {
      _stateWrite = _stateWrite.then(
        (_) => PlaybackStateStore.save(snapshot),
        onError: (_) => PlaybackStateStore.save(snapshot),
      );
    }

    try {
      await Future.wait([
        _stateWrite,
        _modeWrite,
        resumeWrite.then((_) => TrackResumeStore.flushIfInitialized()),
        PlaybackStatistics.instance.flush(finishSession: true),
        _playerStateStreamSub.cancel(),
        _positionStreamSub.cancel(),
      ]).timeout(const Duration(seconds: 1));
    } catch (err, trace) {
      LOGGER.e("[shutdown] state or playback stream cleanup failed: $err",
          stackTrace: trace);
    }

    // The native SMTC object owns the event sink. Close it before cancelling
    // the Dart subscription so cancellation cannot wait forever for the sink.
    try {
      await _smtc.close().timeout(const Duration(milliseconds: 500));
    } catch (err, trace) {
      LOGGER.e("[shutdown] SMTC close failed: $err", stackTrace: trace);
    }
    try {
      await _smtcEventStreamSub
          .cancel()
          .timeout(const Duration(milliseconds: 250));
    } catch (err, trace) {
      LOGGER.e("[shutdown] SMTC stream cleanup failed: $err",
          stackTrace: trace);
    }

    await _player.free();
    _wasapiExclusive.dispose();
    isChangingOutput.dispose();
    _playbackRate.dispose();
    _eqEnabled.dispose();
    _playMode.dispose();
    _shuffle.dispose();
    sleepTimerRemaining.dispose();
    stopAfterCurrent.dispose();
    segmentLoop.dispose();
    isBuffering.dispose();
    resolvingAudioPath.dispose();
    diagnosticsRevision.dispose();
  }
}
