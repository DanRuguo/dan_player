import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_lyric/appearance_controller.dart';
import 'package:desktop_lyric/desktop_lyric_appearance.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class PlaybackClock extends ChangeNotifier {
  PlaybackClock({int Function()? nowMilliseconds, this.automaticTicks = true}) {
    _elapsed.start();
    _nowMilliseconds = nowMilliseconds ?? () => _elapsed.elapsedMilliseconds;
    _anchorTimestamp = _nowMilliseconds();
  }

  static const _frameInterval = Duration(milliseconds: 33);

  final Stopwatch _elapsed = Stopwatch();
  final bool automaticTicks;
  late final int Function() _nowMilliseconds;
  late int _anchorTimestamp;
  Timer? _ticker;
  int _anchorPositionMilliseconds = 0;
  bool _playing = false;
  double _playbackRate = 1.0;
  int _revision = 0;

  int get positionMilliseconds =>
      _anchorPositionMilliseconds +
      (_playing
          ? ((_nowMilliseconds() - _anchorTimestamp).clamp(0, 1 << 53) *
                  _playbackRate)
              .round()
          : 0);

  bool get playing => _playing;
  double get playbackRate => _playbackRate;
  int get revision => _revision;

  void sync(PlaybackTimelineMessage message) {
    _revision++;
    _anchorPositionMilliseconds =
        message.positionMilliseconds.clamp(0, 1 << 53);
    _anchorTimestamp = _nowMilliseconds();
    _playing = message.playing;
    _playbackRate = safeDesktopPlaybackRate(message.playbackRate);
    _updateTicker();
    notifyListeners();
  }

  void setPlaying(bool value) {
    if (_playing == value) return;
    _revision++;

    _anchorPositionMilliseconds = positionMilliseconds;
    _anchorTimestamp = _nowMilliseconds();
    _playing = value;
    _updateTicker();
    notifyListeners();
  }

  void _updateTicker() {
    if (!_playing || !automaticTicks) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }

    _ticker ??= Timer.periodic(_frameInterval, (_) => notifyListeners());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _elapsed.stop();
    super.dispose();
  }
}

class DesktopLyricController {
  ValueNotifier<bool> isPlaying = ValueNotifier(false);
  ValueNotifier<bool> isDarkMode = ValueNotifier(false);
  ValueNotifier<ThemeChangedMessage> theme = ValueNotifier(
    ThemeChangedMessage(
      Colors.blue.toARGB32(),
      Colors.white.toARGB32(),
      Colors.black.toARGB32(),
    ),
  );
  ValueNotifier<NowPlayingChangedMessage> nowPlaying = ValueNotifier(
    const NowPlayingChangedMessage('无', '无', '无'),
  );
  ValueNotifier<LyricLineChangedMessage> lyricLine = ValueNotifier(
    const LyricLineChangedMessage('无', Duration.zero, '无'),
  );
  ValueNotifier<LyricLineTimelineMessage?> detailedLyricLine =
      ValueNotifier(null);
  final ValueNotifier<bool> vertical = ValueNotifier(false);
  final ValueNotifier<bool> locked = ValueNotifier(false);
  late final appearance = TextDisplayController(onChanged: _appearanceChanged);
  final appearanceSaveError = ValueNotifier<String?>(null);
  int _appearanceRevision = 0;
  final PlaybackClock playbackClock;
  StreamSubscription<String>? _inputSubscription;
  final Future<void> Function(bool) _setIgnoreMouseEvents;
  final Future<void> Function() _closeWindow;
  final void Function(String) _sendMessage;

  int activeSequence = 0;
  int _lockRevision = 0;
  bool _disposed = false;
  bool _inputClosed = false;

  bool get inputClosed => _inputClosed;

  static void initWithArgs(List<String> args) {
    if (args.length != 1) return;

    _instance = DesktopLyricController._();
    try {
      final initArgs = InitArgsMessage.fromJson(json.decode(args.first));
      _instance!.applyInitialState(initArgs);
    } catch (error, stack) {
      stderr.writeln(error);
      stderr.writeln(stack);
    }
  }

  void applyInitialState(InitArgsMessage initArgs) {
    uiLanguage.value = UiLanguage.parse(initArgs.language);
    isPlaying.value = initArgs.isPlaying;
    playbackClock.sync(PlaybackTimelineMessage(
      0,
      0,
      initArgs.isPlaying,
      playbackRate: initArgs.playbackRate,
    ));
    vertical.value = initArgs.vertical;
    appearance.value = initArgs.appearance;
    nowPlaying.value = NowPlayingChangedMessage(
      initArgs.title,
      initArgs.artist,
      initArgs.album,
    );

    isDarkMode.value = initArgs.darkMode;
    theme.value = ThemeChangedMessage(
      initArgs.primary,
      initArgs.surfaceContainer,
      initArgs.onSurface,
    );
  }

  static DesktopLyricController? _instance;
  static DesktopLyricController get instance {
    _instance ??= DesktopLyricController._();
    return _instance!;
  }

  DesktopLyricController._({
    PlaybackClock? clock,
    bool listenToInput = true,
    Future<void> Function(bool)? setIgnoreMouseEvents,
    Stream<List<int>>? input,
    Future<void> Function()? closeWindow,
    void Function(String)? sendMessage,
  })  : playbackClock = clock ?? PlaybackClock(),
        _sendMessage = sendMessage ?? stdout.write,
        _closeWindow = closeWindow ?? (() => windowManager.close()),
        _setIgnoreMouseEvents = setIgnoreMouseEvents ??
            ((value) => windowManager.setIgnoreMouseEvents(value)) {
    if (!listenToInput) return;
    _inputSubscription = (input ?? stdin)
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(handleMessage, onDone: _onInputDone,
            onError: (Object error, StackTrace stack) {
      stderr.writeln('Desktop lyric input failed: $error\n$stack');
    });
  }

  /// A real controller with injectable clock/window effects, without stdin or
  /// native initialization. Used by isolated component/protocol tests.
  @visibleForTesting
  factory DesktopLyricController.detached({
    PlaybackClock? clock,
    Future<void> Function(bool)? setIgnoreMouseEvents,
    Stream<List<int>>? input,
    Future<void> Function()? closeWindow,
    void Function(String)? sendMessage,
  }) =>
      DesktopLyricController._(
        clock: clock,
        listenToInput: input != null,
        setIgnoreMouseEvents: setIgnoreMouseEvents,
        input: input,
        closeWindow: closeWindow,
        sendMessage: sendMessage,
      );

  void _appearanceChanged(DesktopLyricAppearance value) {
    if (_disposed || _inputClosed) return;
    appearanceSaveError.value = null;
    try {
      _sendMessage(DesktopLyricAppearanceChangedMessage(value,
              revision: ++_appearanceRevision)
          .buildMessageJson());
    } catch (_) {
      appearanceSaveError.value = '无法连接播放器，外观尚未保存。';
    }
  }

  void retryAppearanceSave() => _appearanceChanged(appearance.value);

  void _onInputDone() {
    if (_disposed || _inputClosed) return;
    _inputClosed = true;
    isPlaying.value = false;
    playbackClock.setPlaying(false);
    // The owning player's pipe is gone. A late Process.start result can no
    // longer be killed by a parent that has exited, so close this HWND here.
    unawaited(Future<void>.sync(_closeWindow)
        .catchError((Object error, StackTrace stack) {
      stderr.writeln('Desktop lyric close after EOF failed: $error\n$stack');
    }));
  }

  void handleMessage(String event) {
    if (_disposed || _inputClosed) return;
    try {
      final decoded = json.decode(event);
      if (decoded is! Map) return;

      final type = decoded['type'];
      final rawContent = decoded['message'];
      if (type is! String || rawContent is! Map) return;
      final content = Map<String, dynamic>.from(rawContent);

      if (type == getMessageTypeName<UiLanguageMessage>()) {
        uiLanguage.value = UiLanguage.parse(content['language']);
      } else if (type == getMessageTypeName<PlayerStateChangedMessage>()) {
        final playerState = PlayerStateChangedMessage.fromJson(content);
        isPlaying.value = playerState.playing;
        playbackClock.setPlaying(playerState.playing);
      } else if (type == getMessageTypeName<NowPlayingChangedMessage>()) {
        nowPlaying.value = NowPlayingChangedMessage.fromJson(content);
        lyricLine.value = const LyricLineChangedMessage('', Duration.zero);
        detailedLyricLine.value = null;
      } else if (type == getMessageTypeName<LyricLineChangedMessage>()) {
        lyricLine.value = LyricLineChangedMessage.fromJson(content);
      } else if (type == getMessageTypeName<PlaybackTimelineMessage>()) {
        _handlePlaybackTimeline(PlaybackTimelineMessage.fromJson(content));
      } else if (type == getMessageTypeName<LyricLineTimelineMessage>()) {
        _handleLyricTimeline(LyricLineTimelineMessage.fromJson(content));
      } else if (type == getMessageTypeName<ThemeModeChangedMessage>()) {
        isDarkMode.value = ThemeModeChangedMessage.fromJson(content).darkMode;
      } else if (type == getMessageTypeName<ThemeChangedMessage>()) {
        theme.value = ThemeChangedMessage.fromJson(content);
      } else if (type == getMessageTypeName<DesktopLyricDisplayMessage>()) {
        vertical.value = DesktopLyricDisplayMessage.fromJson(content).vertical;
      } else if (type == getMessageTypeName<DesktopLyricAppearanceMessage>()) {
        final message = DesktopLyricAppearanceMessage.fromJson(content);
        if (message.revision >= _appearanceRevision) {
          _appearanceRevision = message.revision;
          appearance.value = message.appearance;
        }
      } else if (type ==
          getMessageTypeName<DesktopLyricAppearanceSavedMessage>()) {
        final message = DesktopLyricAppearanceSavedMessage.fromJson(content);
        if (message.revision == _appearanceRevision) {
          appearanceSaveError.value = message.saved ? null : '外观保存失败，当前会话仍然生效。';
        }
      } else if (type == getMessageTypeName<UnlockMessage>()) {
        unawaited(setLocked(false).catchError((Object error, StackTrace stack) {
          stderr.writeln('Desktop lyric unlock failed: $error\n$stack');
        }));
      }
    } catch (error, stack) {
      stderr.writeln(error);
      stderr.writeln(stack);
    }
  }

  void _handlePlaybackTimeline(PlaybackTimelineMessage message) {
    if (message.sequence < activeSequence) return;
    if (message.sequence > activeSequence) {
      activeSequence = message.sequence;
      detailedLyricLine.value = null;
    }

    isPlaying.value = message.playing;
    playbackClock.sync(message);
  }

  void _handleLyricTimeline(LyricLineTimelineMessage message) {
    if (message.sequence < activeSequence) return;
    if (message.sequence > activeSequence) {
      activeSequence = message.sequence;
    }

    detailedLyricLine.value = message;
    lyricLine.value = LyricLineChangedMessage(
      message.content,
      Duration(milliseconds: message.lengthMilliseconds),
      message.translation,
    );
  }

  Future<void> setLocked(bool value) async {
    // window_manager owns this process's HWND. GetForegroundWindow could lock
    // an unrelated application if focus changed between a tap and its await.
    final revision = ++_lockRevision;
    await _setIgnoreMouseEvents(value);
    if (_disposed || revision != _lockRevision) return;
    locked.value = value;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lockRevision++;
    unawaited(_inputSubscription?.cancel());
    playbackClock.dispose();
    isPlaying.dispose();
    isDarkMode.dispose();
    theme.dispose();
    nowPlaying.dispose();
    lyricLine.dispose();
    detailedLyricLine.dispose();
    vertical.dispose();
    locked.dispose();
    appearance.dispose();
    appearanceSaveError.dispose();
  }
}
