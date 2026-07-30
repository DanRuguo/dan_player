import 'dart:async';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_state_store.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
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
      if (event == PlayerState.completed) {
        _autoNextAudio();
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

  late final BassPlayer _player = BassPlayer()
    ..setEqGains(AppPreference.instance.playbackPref.eqGains)
    ..setEqEnabled(AppPreference.instance.playbackPref.eqEnabled);
  final _smtc = SmtcFlutter();
  final _pref = AppPreference.instance.playbackPref;

  late final _wasapiExclusive = ValueNotifier(_player.wasapiExclusive);
  ValueNotifier<bool> get wasapiExclusive => _wasapiExclusive;

  /// 独占模式
  void useExclusiveMode(bool exclusive) {
    if (_player.useExclusiveMode(exclusive)) {
      _wasapiExclusive.value = exclusive;
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

  int? _playlistIndex;
  int get playlistIndex => _playlistIndex ?? 0;

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
      final refreshedIndex =
          playlist.value.indexWhere((audio) => audio.path == nowPlayingPath);
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

  double get length => _player.length;

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

  List<double> get spectrumLevels => _player.spectrumLevels;

  /// 1. 更新 [_playlistIndex] 为 [audioIndex]
  /// 2. 更新 [nowPlaying] 为 playlist[_nowPlayingIndex]
  /// 3. _bassPlayer.setSource
  /// 4. 设置解码音量
  /// 4. 获取歌词 **将 [_nextLyricLine] 置为0**
  /// 5. 播放
  /// 6. 通知并更新主题色
  void _loadAndPlay(int audioIndex, List<Audio> playlist) {
    try {
      if (audioIndex < 0 || audioIndex >= playlist.length) {
        throw RangeError.index(audioIndex, playlist, "audioIndex");
      }
      _playlistIndex = audioIndex;
      nowPlaying = playlist[audioIndex];
      _player.setSource(nowPlaying!.path);
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);

      playService.lyricService.updateLyric();

      _player.start();
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
        if (!canSend) return;

        playService.desktopLyricService
            .sendPlayerStateMessage(playerState == PlayerState.playing);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });

      _lastSessionProgressMs = 0;
      _schedulePlaybackStateSave(positionOverride: 0);
    } catch (err) {
      LOGGER.e("[load and play] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  SavedPlaybackState? _snapshotState({double? positionOverride}) {
    if (nowPlaying == null || playlist.value.isEmpty) return null;
    return SavedPlaybackState(
      queuePaths: [for (final audio in playlist.value) audio.path],
      backupPaths: [for (final audio in _playlistBackup) audio.path],
      index: playlistIndex,
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
    if (!AppSettings.instance.restoreLastSession || nowPlaying != null) return;

    final saved = await PlaybackStateStore.load();
    if (saved == null || nowPlaying != null) return;

    final byPath = AudioLibrary.instance.audioByPath;
    List<Audio> resolve(List<String> paths) => [
          for (final path in paths)
            if (byPath[path] != null) byPath[path]!,
        ];

    final queue = resolve(saved.queuePaths);
    if (queue.isEmpty) return;
    final backup = resolve(saved.backupPaths);

    var index = -1;
    if (saved.index >= 0 && saved.index < saved.queuePaths.length) {
      final currentPath = saved.queuePaths[saved.index];
      index = queue.indexWhere((audio) => audio.path == currentPath);
    }
    if (index < 0) index = 0;

    playlist.value = queue;
    _playlistBackup = backup.isEmpty ? List.from(queue) : backup;
    shuffle.value = saved.shuffle;
    _loadPaused(index, queue, saved.position);
    _schedulePlaybackStateSave(positionOverride: saved.position);
  }

  void _loadPaused(
    int audioIndex,
    List<Audio> playlist,
    double savedPosition,
  ) {
    try {
      _playlistIndex = audioIndex;
      nowPlaying = playlist[audioIndex];
      _player.setSource(nowPlaying!.path);
      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
      playService.lyricService.updateLyric();

      final restoredPosition =
          savedPosition > 0 && savedPosition < length ? savedPosition : 0.0;
      if (restoredPosition > 0) _player.seek(restoredPosition);

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

      playService.desktopLyricService.canSendMessage.then((canSend) {
        if (!canSend) return;
        playService.desktopLyricService.sendPlayerStateMessage(false);
        playService.desktopLyricService.sendNowPlayingMessage(nowPlaying!);
      });
    } catch (err, trace) {
      nowPlaying = null;
      _playlistIndex = null;
      notifyListeners();
      LOGGER.e("[restore session] $err", stackTrace: trace);
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
    if (_playlistIndex != null) {
      final nextPlaylist = List<Audio>.from(playlist.value)
        ..insert(_playlistIndex! + 1, audio);
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
    if (_playlistIndex == null || playlist.value.isEmpty) return;

    if (_playlistIndex! < playlist.value.length - 1) {
      _loadAndPlay(_playlistIndex! + 1, playlist.value);
      return;
    }

    final currentAudio = nowPlaying ?? playlist.value[_playlistIndex!];
    final source = _playlistBackup.isEmpty ? playlist.value : _playlistBackup;
    _buildShuffleCycle(source, currentAudio);

    if (playlist.value.length <= 1) {
      _loadAndPlay(0, playlist.value);
    } else {
      _loadAndPlay(1, playlist.value);
    }
  }

  bool _nextAudio_forward() {
    if (_playlistIndex == null) return false;

    if (_playlistIndex! < playlist.value.length - 1) {
      _loadAndPlay(_playlistIndex! + 1, playlist.value);
      return true;
    }
    return false;
  }

  void _nextAudio_loop() {
    if (_playlistIndex == null) return;
    if (shuffle.value) {
      _nextShuffleAudio();
      return;
    }

    int newIndex = _playlistIndex! + 1;
    if (newIndex >= playlist.value.length) {
      newIndex = 0;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  void _nextAudio_singleLoop() {
    if (_playlistIndex == null) return;

    _loadAndPlay(_playlistIndex!, playlist.value);
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
    if (_playlistIndex == null || playlist.value.isEmpty) return;

    int newIndex = _playlistIndex! - 1;
    if (newIndex < 0) {
      newIndex = playlist.value.length - 1;
    }

    _loadAndPlay(newIndex, playlist.value);
  }

  /// 暂停
  void pause() {
    try {
      _player.pause();
      _syncPausedToSystem();
      unawaited(_savePlaybackState());
    } catch (err) {
      LOGGER.e("[pause] $err");
      showTextOnSnackBar(err.toString());
    }
  }

  /// 恢复播放
  void start() {
    try {
      _player.start();
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
    _player.seek(position);
    _lastSmtcProgressMs = -1000;
    playService.lyricService.findCurrLyricLine();
    _schedulePlaybackStateSave(positionOverride: position);
  }

  Future<void> close() async {
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

    _player.free();
    _wasapiExclusive.dispose();
    _eqEnabled.dispose();
    _playMode.dispose();
    _shuffle.dispose();
    sleepTimerRemaining.dispose();
    stopAfterCurrent.dispose();
  }
}
