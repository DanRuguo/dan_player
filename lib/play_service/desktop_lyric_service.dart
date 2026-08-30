import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/utils.dart';
import 'package:desktop_lyric/message.dart' as msg;
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

enum DesktopLyricState {
  stopped,
  starting,
  running,
  recovering,
  failed,
}

class DesktopLyricService extends ChangeNotifier {
  DesktopLyricService(
    this.playService, {
    Future<Process> Function(String, List<String>)? startProcess,
    bool Function(String)? executableExists,
    Future<void> Function()? saveAppearance,
    ColorScheme Function()? readTheme,
  })  : _startProcess = startProcess ??
            ((executable, arguments) => Process.start(executable, arguments)),
        _executableExists =
            executableExists ?? ((executable) => File(executable).existsSync()),
        _readTheme = readTheme ?? (() => ThemeProvider.instance.currScheme),
        _saveAppearance = saveAppearance ??
            (() => AppSettings.instance
                .saveSettings(throwOnError: true, captureWindowSize: false)) {
    AppSettings.instance.experience.addListener(_syncDisplayPreference);
    AppSettings.instance.desktopLyricAppearance.addListener(_syncAppearance);
    uiLanguage.addListener(_syncLanguage);
    PlayService.playbackReady.addListener(_handlePlaybackReady);
  }

  final PlayService playService;
  final Future<Process> Function(String, List<String>) _startProcess;
  final bool Function(String) _executableExists;
  final Future<void> Function() _saveAppearance;
  final ColorScheme Function() _readTheme;

  PlaybackService get _playbackService => playService.playbackService;

  // Listening to settings/starting an empty lyric window must not initialize
  // the lazy native player. Readiness is published after its construction.
  PlaybackService? get _readyPlayback =>
      PlayService.playbackReady.value ? _playbackService : null;

  static const _playbackSyncInterval = Duration(milliseconds: 400);
  static const _maximumRecoveryAttempts = 2;

  Future<Process?> desktopLyric = Future.value(null);
  StreamSubscription<String>? _desktopLyricSubscription;
  StreamSubscription<String>? _desktopLyricErrorSubscription;
  Process? _desktopLyricProcess;
  Timer? _playbackSyncTimer;
  Timer? _recoveryTimer;
  Timer? _recoveryBudgetResetTimer;
  Timer? _appearanceSaveTimer;
  bool _appearanceDirty = false;
  int _appearanceRevision = 0;
  Future<void> _appearanceSaveFuture = Future.value();

  DesktopLyricState state = DesktopLyricState.stopped;
  Object? lastError;
  bool isLocked = false;

  bool _desiredActive = false;
  bool _disposed = false;
  int _launchGeneration = 0;
  int _recoveryAttempts = 0;
  int _trackSequence = 0;
  String? _trackIdentity;

  bool get isRunning =>
      state == DesktopLyricState.running && _desktopLyricProcess != null;

  bool get isStarting =>
      state == DesktopLyricState.starting ||
      state == DesktopLyricState.recovering;

  Future<void> startDesktopLyric() async {
    if (_disposed || isRunning || isStarting) return;

    _desiredActive = true;
    _recoveryAttempts = 0;
    _recoveryTimer?.cancel();
    await _launch(recovering: false);
  }

  Future<void> _launch({required bool recovering}) async {
    if (_disposed || !_desiredActive) return;

    final desktopLyricPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      'desktop_lyric',
      'desktop_lyric.exe',
    );
    if (!_executableExists(desktopLyricPath)) {
      _failPermanently(
        FileSystemException('找不到桌面歌词组件', desktopLyricPath),
      );
      return;
    }

    final generation = ++_launchGeneration;
    state =
        recovering ? DesktopLyricState.recovering : DesktopLyricState.starting;
    lastError = null;
    desktopLyric = Future.value(null);
    notifyListeners();

    final playback = _readyPlayback;
    final nowPlaying = playback?.nowPlaying;
    final currScheme = _readTheme();
    final isDarkMode = currScheme.brightness == Brightness.dark;

    try {
      final processFuture = _startProcess(desktopLyricPath, [
        json.encode(
          msg.InitArgsMessage(
            playback?.playerState == PlayerState.playing,
            nowPlaying?.displayTitle ?? '无',
            nowPlaying?.artist ?? '无',
            nowPlaying?.album ?? '无',
            isDarkMode,
            currScheme.primary.toARGB32(),
            currScheme.surfaceContainer.toARGB32(),
            currScheme.onSurface.toARGB32(),
            vertical:
                AppSettings.instance.experience.value.desktopLyricVertical,
            playbackRate: playback?.playbackRate.value ?? 1.0,
            appearance: AppSettings.instance.desktopLyricAppearance.value,
            language: uiLanguage.value.code,
          ).toJson(),
        ),
      ]);
      desktopLyric = processFuture;

      final process = await processFuture;
      if (!_desiredActive || generation != _launchGeneration) {
        process.kill();
        return;
      }

      _desktopLyricProcess = process;
      _appearanceRevision = 0;
      desktopLyric = Future.value(process);
      state = DesktopLyricState.running;
      lastError = null;
      isLocked = false;
      _attachProcess(process);
      _startPlaybackSync();
      _recoveryBudgetResetTimer?.cancel();
      _recoveryBudgetResetTimer = Timer(const Duration(seconds: 10), () {
        if (identical(_desktopLyricProcess, process) && isRunning) {
          _recoveryAttempts = 0;
        }
      });
      notifyListeners();

      try {
        await _syncCurrentState();
      } catch (error, trace) {
        LOGGER.e('[desktop lyric initial sync] $error', stackTrace: trace);
        if (identical(_desktopLyricProcess, process)) {
          sendNoLyricMessage();
        }
      }
    } catch (error, trace) {
      if (generation != _launchGeneration) return;
      final process = _desktopLyricProcess;
      if (process != null) {
        process.kill();
        _clearProcess(process);
      } else {
        desktopLyric = Future.value(null);
      }
      LOGGER.e('[desktop lyric start] $error', stackTrace: trace);
      _scheduleRecovery(error);
    }
  }

  void _attachProcess(Process process) {
    _desktopLyricErrorSubscription = process.stderr
        .transform(utf8.decoder)
        .listen((event) => LOGGER.e('[desktop lyric] $event'));

    _desktopLyricSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (event) {
        if (identical(_desktopLyricProcess, process) && !_disposed) {
          _handleDesktopMessage(event);
        }
      },
      onError: (Object error, StackTrace trace) {
        LOGGER.e('[desktop lyric stdout] $error', stackTrace: trace);
        _handleBrokenProcess(process, error);
      },
    );

    unawaited(
      process.exitCode.then(
        (exitCode) => _handleProcessExit(process, exitCode),
        onError: (Object error, StackTrace trace) {
          LOGGER.e('[desktop lyric exit] $error', stackTrace: trace);
          _handleBrokenProcess(process, error);
        },
      ),
    );
  }

  void _handleDesktopMessage(String event) {
    if (_disposed) return;
    try {
      final decoded = json.decode(event);
      if (decoded is! Map) return;

      final messageType = decoded['type'];
      final rawContent = decoded['message'];
      if (messageType is! String || rawContent is! Map) return;

      if (messageType == msg.getMessageTypeName<msg.ControlEventMessage>()) {
        final controlEvent = msg.ControlEventMessage.fromJson(
          Map<String, dynamic>.from(rawContent),
        );
        switch (controlEvent.event) {
          case msg.ControlEvent.pause:
            _playbackService.pause();
            break;
          case msg.ControlEvent.start:
            _playbackService.start();
            break;
          case msg.ControlEvent.previousAudio:
            _playbackService.lastAudio();
            break;
          case msg.ControlEvent.nextAudio:
            _playbackService.nextAudio();
            break;
          case msg.ControlEvent.lock:
            isLocked = true;
            notifyListeners();
            break;
          case msg.ControlEvent.close:
            killDesktopLyric();
            break;
        }
      } else if (messageType ==
          msg.getMessageTypeName<msg.DesktopLyricAppearanceChangedMessage>()) {
        final message = msg.DesktopLyricAppearanceChangedMessage.fromJson(
            Map<String, dynamic>.from(rawContent));
        if (message.revision <= _appearanceRevision) return;
        _appearanceRevision = message.revision;
        AppSettings.instance.desktopLyricAppearance.value = message.appearance;
        _syncAppearance();
        _appearanceDirty = true;
        _appearanceSaveTimer?.cancel();
        _appearanceSaveTimer = Timer(const Duration(milliseconds: 500),
            () => unawaited(flushAppearance()));
      } else if (messageType ==
          msg.getMessageTypeName<msg.DesktopLyricDisplayChangedMessage>()) {
        final display = msg.DesktopLyricDisplayChangedMessage.fromJson(
          Map<String, dynamic>.from(rawContent),
        );
        final preferences = AppSettings.instance.experience;
        preferences.value = preferences.value.copyWith(
          desktopLyricVertical: display.vertical,
        );
        // Echo even an unchanged preference: a restarted/older component can
        // ask for the canonical direction without affecting its clock.
        _syncDisplayPreference();
        unawaited(AppSettings.instance
            .saveSettings(throwOnError: true)
            .catchError((Object error, StackTrace trace) {
          LOGGER.e('[desktop lyric preference] $error', stackTrace: trace);
          showTextOnSnackBar('桌面歌词方向保存失败；当前会话仍生效，请在设置中重试。');
        }));
      }
    } catch (error, trace) {
      LOGGER.e('[desktop lyric message] $error', stackTrace: trace);
    }
  }

  Future<void> _syncCurrentState() async {
    if (!isRunning) return;

    // Process.start can outlive an artwork/theme change. Sends made while the
    // helper was starting were intentionally dropped; replay the latest
    // resolved scheme now, including ThemeMode.system's actual brightness.
    final scheme = _readTheme();
    sendThemeMessage(scheme);
    sendThemeModeMessage(scheme.brightness == Brightness.dark);
    _syncDisplayPreference();
    _syncAppearance();
    _syncLanguage();
    final playback = _readyPlayback;
    if (playback == null) {
      sendPlayerStateMessage(false);
      sendNoLyricMessage();
      return;
    }

    sendPlayerStateMessage(
      playback.playerState == PlayerState.playing,
    );
    final nowPlaying = playback.nowPlaying;
    if (nowPlaying != null) {
      _sendNowPlayingMessage(nowPlaying, syncLyric: false);
    }
    await playService.lyricService.syncDesktopLyric();
  }

  void _syncDisplayPreference() {
    if (_disposed || !isRunning) return;
    sendMessage(msg.DesktopLyricDisplayMessage(
      vertical: AppSettings.instance.experience.value.desktopLyricVertical,
    ));
  }

  void _syncAppearance() {
    if (_disposed || !isRunning) return;
    sendMessage(msg.DesktopLyricAppearanceMessage(
        AppSettings.instance.desktopLyricAppearance.value,
        revision: _appearanceRevision));
  }

  Future<void> flushAppearance() {
    _appearanceSaveTimer?.cancel();
    _appearanceSaveTimer = null;
    if (!_appearanceDirty) return _appearanceSaveFuture;
    _appearanceDirty = false;
    final revision = _appearanceRevision;
    final process = _desktopLyricProcess;
    return _appearanceSaveFuture = _appearanceSaveFuture
        .then((_) => _persistAppearance(revision, process));
  }

  Future<void> _persistAppearance(int revision, Process? process) async {
    var saved = true;
    try {
      await _saveAppearance();
    } catch (error, trace) {
      saved = false;
      LOGGER.e('[desktop lyric appearance save] $error', stackTrace: trace);
      if (!_disposed) {
        showTextOnSnackBar('桌面歌词外观保存失败；当前会话仍生效，可在歌词外观中重试保存。');
      }
    }
    // A save can finish after close/relaunch. Never report it to another helper.
    if (!_disposed &&
        identical(process, _desktopLyricProcess) &&
        revision == _appearanceRevision) {
      sendMessage(msg.DesktopLyricAppearanceSavedMessage(
          revision: revision, saved: saved));
    }
  }

  void _handlePlaybackReady() {
    if (_disposed || !PlayService.playbackReady.value || !isRunning) return;
    unawaited(_syncCurrentState().catchError((Object error, StackTrace trace) {
      LOGGER.e('[desktop lyric ready sync] $error', stackTrace: trace);
    }));
  }

  void _startPlaybackSync() {
    _playbackSyncTimer?.cancel();
    _playbackSyncTimer = Timer.periodic(
      _playbackSyncInterval,
      (_) => sendPlaybackTimelineMessage(),
    );
  }

  void _handleProcessExit(Process process, int exitCode) {
    if (!identical(_desktopLyricProcess, process)) return;

    _clearProcess(process);
    if (!_desiredActive) {
      state = DesktopLyricState.stopped;
      notifyListeners();
      return;
    }

    _scheduleRecovery(StateError('桌面歌词进程异常退出（代码 $exitCode）'));
  }

  void _handleBrokenProcess(Process process, Object error) {
    if (!identical(_desktopLyricProcess, process)) return;

    process.kill();
    _clearProcess(process);
    if (_desiredActive) {
      _scheduleRecovery(error);
    }
  }

  void _clearProcess(Process process) {
    if (!identical(_desktopLyricProcess, process)) return;

    _desktopLyricProcess = null;
    desktopLyric = Future.value(null);
    _playbackSyncTimer?.cancel();
    _playbackSyncTimer = null;
    _recoveryBudgetResetTimer?.cancel();
    _recoveryBudgetResetTimer = null;
    unawaited(_desktopLyricSubscription?.cancel());
    unawaited(_desktopLyricErrorSubscription?.cancel());
    _desktopLyricSubscription = null;
    _desktopLyricErrorSubscription = null;
    isLocked = false;
  }

  void _scheduleRecovery(Object error) {
    if (_disposed) return;
    lastError = error;
    if (!_desiredActive) {
      state = DesktopLyricState.stopped;
      notifyListeners();
      return;
    }

    if (_recoveryAttempts >= _maximumRecoveryAttempts) {
      _failPermanently(error);
      return;
    }

    _recoveryAttempts += 1;
    state = DesktopLyricState.recovering;
    desktopLyric = Future.value(null);
    notifyListeners();

    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(
      Duration(milliseconds: 500 * _recoveryAttempts),
      () => unawaited(_launch(recovering: true)),
    );
  }

  void _failPermanently(Object error) {
    _desiredActive = false;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _playbackSyncTimer?.cancel();
    _playbackSyncTimer = null;
    _recoveryBudgetResetTimer?.cancel();
    _recoveryBudgetResetTimer = null;
    _desktopLyricProcess = null;
    desktopLyric = Future.value(null);
    state = DesktopLyricState.failed;
    lastError = error;
    isLocked = false;
    notifyListeners();
    showTextOnSnackBar('桌面歌词启动失败：$error');
  }

  Future<bool> get canSendMessage async => isRunning;

  void sendMessage(msg.Message message) {
    if (_disposed) return;
    final process = _desktopLyricProcess;
    if (!isRunning || process == null) return;

    try {
      process.stdin.write(message.buildMessageJson());
    } catch (error, trace) {
      LOGGER.e('[desktop lyric send] $error', stackTrace: trace);
      _handleBrokenProcess(process, error);
    }
  }

  void killDesktopLyric() {
    // Settings update synchronously on receipt. Flush the debounce before
    // releasing the helper, including application shutdown/dispose.
    unawaited(flushAppearance());
    _desiredActive = false;
    _launchGeneration += 1;
    _recoveryAttempts = 0;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryBudgetResetTimer?.cancel();
    _recoveryBudgetResetTimer = null;

    final process = _desktopLyricProcess;
    if (process != null) {
      _clearProcess(process);
      unawaited(process.stdin.close().catchError((_) {}));
      process.kill();
    } else {
      _playbackSyncTimer?.cancel();
      _playbackSyncTimer = null;
      desktopLyric = Future.value(null);
      isLocked = false;
    }

    state = DesktopLyricState.stopped;
    lastError = null;
    if (!_disposed) notifyListeners();
  }

  void sendUnlockMessage() {
    sendMessage(const msg.UnlockMessage());
    isLocked = false;
    notifyListeners();
  }

  void sendThemeModeMessage(bool darkMode) {
    sendMessage(msg.ThemeModeChangedMessage(darkMode));
  }

  void sendThemeMessage(ColorScheme scheme) {
    sendMessage(
      msg.ThemeChangedMessage(
        scheme.primary.toARGB32(),
        scheme.surfaceContainer.toARGB32(),
        scheme.onSurface.toARGB32(),
      ),
    );
  }

  void sendPlayerStateMessage(bool isPlaying) {
    sendMessage(msg.PlayerStateChangedMessage(isPlaying));
    sendPlaybackTimelineMessage();
  }

  void sendNowPlayingMessage(Audio nowPlaying) {
    _sendNowPlayingMessage(nowPlaying, syncLyric: true);
  }

  void _sendNowPlayingMessage(
    Audio nowPlaying, {
    required bool syncLyric,
  }) {
    _ensureTrackSequence(nowPlaying);
    sendMessage(
      msg.NowPlayingChangedMessage(
        nowPlaying.displayTitle,
        nowPlaying.artist,
        nowPlaying.album,
      ),
    );
    sendPlaybackTimelineMessage();
    if (syncLyric) {
      unawaited(playService.lyricService.syncDesktopLyric());
    }
  }

  int _ensureTrackSequence(Audio? nowPlaying) {
    final identity = nowPlaying?.path;
    if (identity != _trackIdentity) {
      _trackIdentity = identity;
      _trackSequence += 1;
    }
    return _trackSequence;
  }

  void sendPlaybackTimelineMessage() {
    if (!isRunning) return;

    final playback = _readyPlayback;
    final sequence = _ensureTrackSequence(playback?.nowPlaying);
    sendMessage(
      msg.PlaybackTimelineMessage(
        sequence,
        ((playback?.position ?? 0) * 1000).round(),
        playback?.playerState == PlayerState.playing,
        playbackRate: playback?.playbackRate.value ?? 1.0,
      ),
    );
  }

  void sendNoLyricMessage() {
    if (!isRunning) return;

    final sequence = _ensureTrackSequence(_readyPlayback?.nowPlaying);
    sendMessage(
      const msg.LyricLineChangedMessage(
        '无歌词',
        Duration.zero,
      ),
    );
    sendMessage(
      msg.LyricLineTimelineMessage(
        sequence: sequence,
        lineIndex: -1,
        startMilliseconds: 0,
        lengthMilliseconds: 0,
        content: '无歌词',
        translation: null,
        words: const <msg.DesktopLyricWord>[],
      ),
    );
  }

  void sendLyricLineMessage(LyricLine line, {required int lineIndex}) {
    if (!isRunning) return;

    late final String content;
    late final String? translation;
    late final Duration length;
    var words = const <msg.DesktopLyricWord>[];

    if (line is SyncLyricLine) {
      content = line.content;
      translation = line.translation;
      length = line.length;
      words = [
        for (final word in line.words)
          msg.DesktopLyricWord(
            word.start.inMilliseconds,
            word.length.inMilliseconds,
            word.content,
          ),
      ];
    } else if (line is LrcLine) {
      final split = line.content.split('┃');
      content = split.first;
      final translations =
          split.skip(1).where((part) => part.trim().isNotEmpty);
      translation = translations.isEmpty ? null : translations.join(' / ');
      length = line.length;
    } else {
      return;
    }

    final sequence = _ensureTrackSequence(_readyPlayback?.nowPlaying);
    sendMessage(msg.LyricLineChangedMessage(content, length, translation));
    sendMessage(
      msg.LyricLineTimelineMessage(
        sequence: sequence,
        lineIndex: lineIndex,
        startMilliseconds: line.start.inMilliseconds,
        lengthMilliseconds: length.inMilliseconds,
        content: content,
        translation: translation,
        words: words,
      ),
    );
  }

  void _syncLanguage() =>
      sendMessage(msg.UiLanguageMessage(uiLanguage.value.code));

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    AppSettings.instance.experience.removeListener(_syncDisplayPreference);
    AppSettings.instance.desktopLyricAppearance.removeListener(_syncAppearance);
    uiLanguage.removeListener(_syncLanguage);
    PlayService.playbackReady.removeListener(_handlePlaybackReady);
    killDesktopLyric();
    super.dispose();
  }
}
