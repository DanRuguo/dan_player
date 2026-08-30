import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/online/online_music_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/queue_navigation.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';

enum PlayMode {
  /// 顺序播放到播放列表结尾
  forward,

  /// 循环整个播放列表
  loop,

  /// 循环播放单曲
  singleLoop;

  static PlayMode? fromString(String playMode) {
    for (var value in PlayMode.values) {
      if (value.name == playMode) return value;
    }
    return null;
  }
}

/// 只通知 now playing 变更
class PlaybackService extends ChangeNotifier {
  final PlayService playService;

  late StreamSubscription _playerStateStreamSub;
  late StreamSubscription _smtcEventStreamSub;
  late StreamSubscription _positionStreamSub;

  int _lastSmtcProgressMs = -1000;
  int _lastSessionProgressMs = -30000;

  PlaybackService(this.playService) {
    _playerStateStreamSub = playerStateStream.listen((event) {
      if (_closed) return;
      if (event == PlayerState.completed) {
        PlaybackStatistics.instance.finish(markCompleted: true);
        // An old track may finish while a user-selected online track is still
        // opening. Do not let auto-next replace that newer explicit request.
        if (!isBuffering.value) _autoNextAudio();
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
      if (_closed) return;
      PlaybackStatistics.instance
          .tick(nowPlaying, playerState, playbackRate: _player.playbackRate);
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
      showTextOnSnackBar('调整播放速度失败：$error');
      return false;
    }
  }

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    if (_closed) return;
    if (exclusive == _player.wasapiExclusive) return;
    if (isBuffering.value || isChangingOutput.value) {
      showTextOnSnackBar('请等待当前音乐加载完成后再切换输出模式');
      return;
    }
    final token = ++_sourceRequestToken;
    isChangingOutput.value = true;
    _player.cancelPendingSource();
    final current = nowPlaying;
    _loadingPlaylistIndex = _playlistIndex;
    isBuffering.value = current?.isOnline == true;
    resolvingAudioPath.value = current?.isOnline == true ? current!.path : null;
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
            showTextOnSnackBar('音频输出已切换，但设置保存失败：$error');
          }
        }
      }
    } catch (err, trace) {
      if (_isCurrentSourceRequest(token)) {
        LOGGER.e('[change output mode] $err', stackTrace: trace);
        showTextOnSnackBar('切换音频输出失败：$err');
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
  }

  void applyEqGains(List<double> gains) {
    _player.setEqGains(gains);
    _pref.eqGains = _player.eqGains;
  }

  Audio? nowPlaying;
  final ValueNotifier<bool> isBuffering = ValueNotifier(false);
  final ValueNotifier<String?> resolvingAudioPath = ValueNotifier(null);
  int _sourceRequestToken = 0;
  bool _closed = false;
  Future<void>? _closeFuture;

  bool _isCurrentSourceRequest(int token) =>
      !_closed && token == _sourceRequestToken;

  int? _playlistIndex;
  int? _loadingPlaylistIndex;
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
  Timer? _stateSaveTimer;
  Future<void> _stateWrite = Future.value();
  bool _sessionRestoreAttempted = false;

  void replaceAudioReference(String oldPath, Audio audio) {
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

  late final _playMode = ValueNotifier(_pref.playMode);
  ValueNotifier<PlayMode> get playMode => _playMode;

  void setPlayMode(PlayMode playMode) {
    this.playMode.value = playMode;
    _pref.playMode = playMode;
  }

  late final _shuffle = ValueNotifier(false);
  ValueNotifier<bool> get shuffle => _shuffle;

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

  /// 修改解码时的音量（不影响 Windows 系统音量）
  void setVolumeDsp(double volume) {
    _player.setVolumeDsp(volume);
    _pref.volumeDsp = volume;
  }

  Stream<double> get positionStream => _player.positionStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<List<double>> get spectrumStream => _player.spectrumStream;

  Stream<List<double>> get frequencySpectrumStream =>
      _player.frequencySpectrumStream;

  List<double> get spectrumLevels => _player.spectrumLevels;

  List<double> get frequencySpectrumLevels => _player.frequencySpectrumLevels;

  /// Resolve/open first; only a successful native source becomes nowPlaying.
  void _loadAndPlay(int audioIndex, List<Audio> playlist) {
    if (_closed) return;
    final token = ++_sourceRequestToken;
    _player.cancelPendingSource();
    unawaited(_loadAndPlayResolved(token, audioIndex, playlist));
  }

  Future<void> _loadAndPlayResolved(
    int token,
    int audioIndex,
    List<Audio> playlist,
  ) async {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) {
        throw RangeError.index(audioIndex, playlist, "audioIndex");
      }
      final target = playlist[audioIndex];
      _loadingPlaylistIndex = audioIndex;
      isBuffering.value = target.isOnline;
      resolvingAudioPath.value = target.isOnline ? target.path : null;
      final source = target.isOnline
          ? (await OnlineMusicService.instance.resolveStreamUrl(target))
              .toString()
          : target.path;
      if (!_isCurrentSourceRequest(token)) return;
      final applied = await _player.setSource(source, isUrl: target.isOnline);
      if (!applied || !_isCurrentSourceRequest(token)) return;
      if (nowPlaying != null) {
        PlaybackStatistics.instance.finish(markCompleted: false);
      }
      _playlistIndex = audioIndex;
      nowPlaying = target;
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
        path: nowPlaying!.path,
      );

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend || !_isCurrentSourceRequest(token)) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });

      _lastSessionProgressMs = 0;
      _schedulePlaybackStateSave(positionOverride: 0);
    } catch (err, trace) {
      LOGGER.e("[load and play] $err");
      LOGGER.d("[load and play] trace", stackTrace: trace);
      if (_isCurrentSourceRequest(token)) {
        showTextOnSnackBar(
          err is OnlineMusicException ? err.message : "播放失败：$err",
        );
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

  Future<void> restoreLastSessionOnce() async {
    if (_sessionRestoreAttempted) return;
    _sessionRestoreAttempted = true;
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

    final byPath = AudioLibrary.instance.audioByPath;
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
    final index = hasSavedOccurrence ? restoredIndex : 0;

    playlist.value = queue;
    _playlistBackup = backup.isEmpty ? List.from(queue) : backup;
    shuffle.value = saved.shuffle;
    _loadPaused(index, queue, hasSavedOccurrence ? saved.position : 0.0);
  }

  void _loadPaused(
    int audioIndex,
    List<Audio> playlist,
    double savedPosition,
  ) {
    if (_closed) return;
    final token = ++_sourceRequestToken;
    _player.cancelPendingSource();
    unawaited(
      _loadPausedResolved(token, audioIndex, playlist, savedPosition),
    );
  }

  Future<void> _loadPausedResolved(
    int token,
    int audioIndex,
    List<Audio> playlist,
    double savedPosition,
  ) async {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) {
        throw RangeError.index(audioIndex, playlist, 'audioIndex');
      }
      final target = playlist[audioIndex];
      _loadingPlaylistIndex = audioIndex;
      isBuffering.value = target.isOnline;
      resolvingAudioPath.value = target.isOnline ? target.path : null;
      final source = target.isOnline
          ? (await OnlineMusicService.instance.resolveStreamUrl(target))
              .toString()
          : target.path;
      if (!_isCurrentSourceRequest(token)) return;
      final applied = await _player.setSource(source, isUrl: target.isOnline);
      if (!applied || !_isCurrentSourceRequest(token)) return;
      _playlistIndex = audioIndex;
      nowPlaying = target;
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

      notifyListeners();
      ThemeProvider.instance.applyThemeFromAudio(nowPlaying!);
      _lastSmtcProgressMs = (restoredPosition * 1000).floor();
      _lastSessionProgressMs = _lastSmtcProgressMs;
      _smtc.updateState(state: SMTCState.paused);
      _smtc.updateDisplay(
        title: nowPlaying!.displayTitle,
        artist: nowPlaying!.artist,
        album: nowPlaying!.album,
        duration: (length * 1000).floor(),
        path: nowPlaying!.path,
      );
      _smtc.updateTimeProperties(progress: _lastSmtcProgressMs);
      _schedulePlaybackStateSave(positionOverride: restoredPosition);

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend || !_isCurrentSourceRequest(token)) return;
        playService.desktopLyricService.sendPlayerStateMessage(false);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
    } catch (err, trace) {
      if (!_isCurrentSourceRequest(token)) return;
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

  /// 播放当前播放列表的第几项，只能用在播放列表界面
  void playIndexOfPlaylist(int audioIndex) {
    if (audioIndex < 0 || audioIndex >= playlist.value.length) return;
    _loadAndPlay(audioIndex, playlist.value);
  }

  /// 播放playlist[audioIndex]并设置播放列表为playlist
  void play(int audioIndex, List<Audio> playlist) {
    if (audioIndex < 0 || audioIndex >= playlist.length) return;

    if (shuffle.value) {
      final willPlay = playlist[audioIndex];
      if (_hasSameAudioPool(_playlistBackup, playlist)) {
        final indexInCycle = _findAudioByPath(this.playlist.value, willPlay);
        if (indexInCycle >= 0) {
          _loadAndPlay(indexInCycle, this.playlist.value);
          return;
        }
      }

      _buildShuffleCycle(playlist, willPlay);
      _loadAndPlay(0, this.playlist.value);
    } else {
      this.playlist.value = List.from(playlist);
      _playlistBackup = List.from(playlist);
      _loadAndPlay(audioIndex, this.playlist.value);
    }
  }

  void shuffleAndPlay(List<Audio> audios) {
    if (audios.isEmpty) return;

    playlist.value = List.from(audios);
    playlist.value.shuffle();
    _playlistBackup = List.from(audios);

    shuffle.value = true;

    _loadAndPlay(0, playlist.value);
  }

  /// 下一首播放
  void addToNext(Audio audio) {
    if (playlist.value.isNotEmpty) {
      final nextPlaylist = List<Audio>.from(playlist.value)
        ..insert(_navigationIndex + 1, audio);
      playlist.value = nextPlaylist;
      if (shuffle.value) {
        if (_findAudioByPath(_playlistBackup, audio) < 0) {
          _playlistBackup = List<Audio>.from(_playlistBackup)..add(audio);
        }
      } else {
        _playlistBackup = List<Audio>.from(nextPlaylist);
      }
      _schedulePlaybackStateSave();
    } else {
      play(0, [audio]);
    }
  }

  void useShuffle(bool flag) {
    if (nowPlaying == null) return;
    if (flag == shuffle.value) return;

    if (flag) {
      _buildShuffleCycle(
        _playlistBackup.isEmpty ? playlist.value : _playlistBackup,
        nowPlaying!,
      );
      shuffle.value = true;
    } else {
      playlist.value = List.from(_playlistBackup);
      final currentIndex = _findAudioByPath(playlist.value, nowPlaying!);
      _playlistIndex = currentIndex >= 0 ? currentIndex : 0;
      shuffle.value = false;
    }
    _schedulePlaybackStateSave();
  }

  int _findAudioByPath(List<Audio> audios, Audio audio) {
    return audios.indexWhere((item) => item.path == audio.path);
  }

  bool _hasSameAudioPool(List<Audio> left, List<Audio> right) {
    if (left.length != right.length || left.isEmpty) return false;
    final leftPaths = left.map((audio) => audio.path).toSet();
    if (leftPaths.length != left.length) return false;
    return right.every((audio) => leftPaths.contains(audio.path));
  }

  void _buildShuffleCycle(List<Audio> source, Audio startAudio) {
    final cycleSource = List<Audio>.from(source);
    if (cycleSource.isEmpty) return;

    final startIndex = _findAudioByPath(cycleSource, startAudio);
    final start = startIndex >= 0
        ? cycleSource.removeAt(startIndex)
        : cycleSource.removeAt(0);
    cycleSource.shuffle();

    playlist.value = [start, ...cycleSource];
    _playlistBackup = List<Audio>.from(source);
    _playlistIndex = 0;
  }

  void _nextShuffleAudio() {
    if (playlist.value.isEmpty) return;
    final currentIndex = _navigationIndex;

    if (currentIndex < playlist.value.length - 1) {
      _loadAndPlay(currentIndex + 1, playlist.value);
      return;
    }

    final currentAudio = playlist.value[currentIndex];
    final source = _playlistBackup.isEmpty ? playlist.value : _playlistBackup;
    _buildShuffleCycle(source, currentAudio);

    if (playlist.value.length <= 1) {
      _loadAndPlay(0, playlist.value);
    } else {
      _loadAndPlay(1, playlist.value);
    }
  }

  bool _nextAudio_forward() {
    if (playlist.value.isEmpty) return false;
    final currentIndex = _navigationIndex;

    if (currentIndex < playlist.value.length - 1) {
      _loadAndPlay(currentIndex + 1, playlist.value);
      return true;
    }
    return false;
  }

  void _nextAudio_loop() {
    if (playlist.value.isEmpty) return;
    if (shuffle.value) {
      _nextShuffleAudio();
      return;
    }

    int newIndex = _navigationIndex + 1;
    if (newIndex >= playlist.value.length) {
      newIndex = 0;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  void _nextAudio_singleLoop() {
    if (playlist.value.isEmpty) return;

    final index = _navigationIndex;
    _loadAndPlay(index < 0 ? 0 : index, playlist.value);
  }

  void _syncPausedToSystem() {
    _smtc.updateState(state: SMTCState.paused);
    playService.desktopLyricService.canSendMessage.then((canSend) {
      if (canSend) {
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

    if (shuffle.value && playMode.value != PlayMode.singleLoop) {
      _nextShuffleAudio();
      return;
    }

    switch (playMode.value) {
      case PlayMode.forward:
        if (!_nextAudio_forward()) _syncPausedToSystem();
        break;
      case PlayMode.loop:
        _nextAudio_loop();
        break;
      case PlayMode.singleLoop:
        _nextAudio_singleLoop();
        break;
    }
  }

  /// 手动下一曲时默认循环播放列表
  void nextAudio() => _nextAudio_loop();

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
      PlaybackStatistics.instance.pause();
      _syncPausedToSystem();
      unawaited(_savePlaybackState());
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    if (_closed) return;
    try {
      _player.start();
      final current = nowPlaying;
      if (current != null) {
        PlaybackStatistics.instance
            .start(current, playbackRate: _player.playbackRate);
      }
      _smtc.updateState(state: SMTCState.playing);
      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;

        playService.desktopLyricService.sendPlayerStateMessage(true);
      });
    } catch (err) {
      LOGGER.e("[start]: $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 再次播放。在顺序播放完最后一曲时再次按播放时使用。
  /// 与 [start] 的差别在于它会通知重绘组件
  void playAgain() => _nextAudio_singleLoop();

  void seek(double position) {
    if (_closed) return;
    try {
      _player.seek(position);
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
    _closed = true;
    _sourceRequestToken += 1;
    _player.cancelPendingSource();
    isBuffering.value = false;
    resolvingAudioPath.value = null;
    _stateSaveTimer?.cancel();
    _stateSaveTimer = null;
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
    isBuffering.dispose();
    resolvingAudioPath.dispose();
  }
}
