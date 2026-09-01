import 'dart:async';
import 'package:dan_player/desktop_tray_appearance.dart';
import 'package:dan_player/component/app_shape.dart';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/component/app_fonts.dart';
import 'package:dan_player/hotkeys_helper.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/theme_provider.dart';
import 'package:dan_player/taskbar_song_preview.dart';
import 'package:dan_player/utils.dart';
import 'package:dan_player/window_mode_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:path/path.dart' as path;

/// Transport metadata updates remain independent of the optional bounded song
/// preview. No positions, lyrics or per-frame updates are sent to the taskbar.
@immutable
class DesktopPlaybackSnapshot {
  const DesktopPlaybackSnapshot({
    this.ready = false,
    this.hasTrack = false,
    this.hasQueue = false,
    this.playing = false,
    this.buffering = false,
    this.desktopLyrics = false,
    this.title = '',
    this.preview,
  });

  final bool ready;
  final bool hasTrack;
  final bool hasQueue;
  final bool playing;
  final bool buffering;
  final bool desktopLyrics;
  final String title;
  final TaskbarPreviewTrack? preview;

  bool allows(String action) => switch (action) {
        'toggle' => ready && hasTrack && !buffering,
        'previous' || 'next' => ready && hasQueue && !buffering,
        'desktopLyrics' => ready && hasTrack,
        _ => false,
      };

  Map<String, Object> toMap() => {
        'ready': ready,
        'hasTrack': hasTrack,
        'hasQueue': hasQueue,
        'playing': playing,
        'buffering': buffering,
        'desktopLyrics': desktopLyrics,
        'title': title,
      };

  @override
  bool operator ==(Object other) =>
      other is DesktopPlaybackSnapshot &&
      ready == other.ready &&
      hasTrack == other.hasTrack &&
      hasQueue == other.hasQueue &&
      playing == other.playing &&
      buffering == other.buffering &&
      desktopLyrics == other.desktopLyrics &&
      title == other.title &&
      preview == other.preview;

  @override
  int get hashCode => Object.hash(ready, hasTrack, hasQueue, playing, buffering,
      desktopLyrics, title, preview);
}

abstract interface class DesktopNativeAdapter {
  void setEventHandler(Future<void> Function(MethodCall call)? handler);
  Future<Object?> invoke(String method, [Map<String, Object>? arguments]);
}

abstract interface class DesktopWindowAdapter {
  Future<void> hide();
  Future<void> show({bool? mini});
}

abstract interface class DesktopPlaybackAdapter
    implements ValueListenable<DesktopPlaybackSnapshot> {
  void startObserving();
  Future<void> runAction(String action);
  Future<void> stopObserving();
}

class _NativeDesktopAdapter implements DesktopNativeAdapter {
  static const channel = MethodChannel('dan_player/desktop_integration');

  @override
  void setEventHandler(Future<void> Function(MethodCall call)? handler) =>
      channel.setMethodCallHandler(handler);

  @override
  Future<Object?> invoke(String method, [Map<String, Object>? arguments]) =>
      channel.invokeMethod<Object?>(method, arguments);
}

class _DesktopWindowAdapter implements DesktopWindowAdapter {
  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> show({bool? mini}) async {
    if (mini == true) await WindowModeController.instance.enter();
    if (mini == false) await WindowModeController.instance.exit();
    final minimized = await windowManager.isMinimized();
    await windowManager.show();
    if (minimized) await windowManager.restore();
    await windowManager.focus();
  }
}

/// A passive observer. Merely constructing a tray/setting/background does not
/// touch PlayService.instance. Startup remains the owner of BASS construction.
class _DesktopPlaybackAdapter extends ValueNotifier<DesktopPlaybackSnapshot>
    implements DesktopPlaybackAdapter {
  _DesktopPlaybackAdapter() : super(const DesktopPlaybackSnapshot());

  PlaybackService? _playback;
  DesktopLyricService? _lyrics;
  StreamSubscription<PlayerState>? _playerEvents;
  bool _observing = false;

  @override
  void startObserving() {
    if (_observing) return;
    _observing = true;
    AudioLibrary.changes.addListener(_publish);
    PlayService.playbackReady.addListener(_ready);
    _ready();
  }

  void _ready() {
    if (!_observing || !PlayService.playbackReady.value || _playback != null) {
      return;
    }
    final service = PlayService.instance;
    _playback = service.playbackService;
    _lyrics = service.desktopLyricService;
    _playback!.addListener(_publish);
    _playback!.playlist.addListener(_publish);
    _playback!.isBuffering.addListener(_publish);
    _lyrics!.addListener(_publish);
    _playerEvents = _playback!.playerStateStream.listen((_) => _publish());
    _publish();
  }

  void _publish() {
    final playback = _playback;
    if (!_observing || playback == null) return;
    final audio = playback.nowPlaying;
    value = DesktopPlaybackSnapshot(
      ready: true,
      hasTrack: audio != null,
      hasQueue: playback.playlist.value.isNotEmpty,
      playing: playback.playerState == PlayerState.playing,
      buffering: playback.isBuffering.value,
      desktopLyrics: _lyrics!.isRunning || _lyrics!.isStarting,
      title: audio == null ? '' : '${audio.displayTitle} — ${audio.artist}',
      preview: audio == null ? null : TaskbarPreviewTrack.fromAudio(audio),
    );
  }

  @override
  Future<void> runAction(String action) async {
    final playback = _playback;
    if (playback == null || !value.allows(action)) return;
    switch (action) {
      case 'toggle':
        if (playback.playerState == PlayerState.playing) {
          playback.pause();
        } else if (playback.playerState == PlayerState.completed) {
          playback.playAgain();
        } else {
          playback.start();
        }
      case 'previous':
        playback.lastAudio();
      case 'next':
        playback.nextAudio();
      case 'desktopLyrics':
        final lyrics = _lyrics!;
        if (lyrics.isRunning || lyrics.isStarting) {
          lyrics.killDesktopLyric();
        } else {
          await lyrics.startDesktopLyric();
          if (lyrics.state == DesktopLyricState.failed) {
            throw StateError('打开桌面歌词失败：${lyrics.lastError ?? '组件不可用'}');
          }
        }
    }
    _publish();
  }

  @override
  Future<void> stopObserving() async {
    if (!_observing) return;
    _observing = false;
    AudioLibrary.changes.removeListener(_publish);
    PlayService.playbackReady.removeListener(_ready);
    _playback?.removeListener(_publish);
    _playback?.playlist.removeListener(_publish);
    _playback?.isBuffering.removeListener(_publish);
    _lyrics?.removeListener(_publish);
    await _playerEvents?.cancel();
    _playerEvents = null;
    _playback = null;
    _lyrics = null;
  }
}

/// One native window, one audio service. Native Shell failures never prevent
/// startup and never authorize hiding a window without a working restore icon.
class DesktopIntegration implements Listenable {
  DesktopIntegration._()
      : _native = _NativeDesktopAdapter(),
        _window = _DesktopWindowAdapter(),
        _playback = _DesktopPlaybackAdapter(),
        _preferences = AppSettings.instance.experience,
        _supported = Platform.isWindows,
        _previewRenderer = renderTaskbarSongPreview,
        _themeOverride = null,
        _syncAppearance = true,
        _onError = HotkeysHelper.showError;

  @visibleForTesting
  DesktopIntegration.forTesting({
    required DesktopNativeAdapter native,
    required DesktopWindowAdapter window,
    required DesktopPlaybackAdapter playback,
    required ValueListenable<PlayerExperiencePreferences> preferences,
    bool supported = true,
    bool syncAppearance = false,
    void Function(String)? onError,
    TaskbarPreviewRenderer previewRenderer = renderTaskbarSongPreview,
    ThemeProvider? themeProvider,
  })  : _native = native,
        _window = window,
        _playback = playback,
        _preferences = preferences,
        _supported = supported,
        _previewRenderer = previewRenderer,
        _themeOverride = themeProvider,
        _syncAppearance = syncAppearance,
        _onError = onError;

  static final instance = DesktopIntegration._();
  final DesktopNativeAdapter _native;
  final DesktopWindowAdapter _window;
  final DesktopPlaybackAdapter _playback;
  final ValueListenable<PlayerExperiencePreferences> _preferences;
  final bool _supported;
  final bool _syncAppearance;
  final TaskbarPreviewRenderer _previewRenderer;
  final ThemeProvider? _themeOverride;
  ThemeProvider get _theme => _themeOverride ?? ThemeProvider.instance;
  TaskbarPreviewPublisher? _preview;
  String? _previewError;
  final void Function(String)? _onError;
  final _changes = ValueNotifier<int>(0);
  final _hidden = ValueNotifier<bool>(false);
  Future<void>? _initialization;
  Future<void>? _disposal;
  Future<void> _nativeTail = Future.value();
  Future<void> _windowTail = Future.value();
  Future<void> Function()? _onExit;
  DesktopPlaybackSnapshot? _sentPlayback;
  bool? _sentTaskbar;
  double? _sentTrayBlurRadius;
  bool? _sentRoundedCorners;
  (bool, int, String, String)? _sentAppearance;
  UiLanguage? _sentLanguage;

  Map<String, String> _menuLabels() => {
        'showMain': ui('显示主窗口'),
        'showMini': ui('迷你播放器'),
        'previous': ui('上一首'),
        'play': ui('播放'),
        'pause': ui('暂停'),
        'next': ui('下一首'),
        'lyrics': ui('桌面歌词'),
        'exit': ui('退出 Dan Player'),
      };
  bool _started = false;
  bool _closed = false;
  bool _exitRequested = false;
  bool _syncScheduled = false;
  bool _recoveringWindow = false;
  int _nativeRevision = -1;
  bool _available = false;
  bool _taskbarAvailable = false;
  String? _lastError;

  bool get isAvailable => _available && !_closed;
  bool get taskbarAvailable => _taskbarAvailable && !_closed;
  bool get isInitialized => _started && !_closed;
  String? get lastError => _lastError;
  String? get previewError => _previewError;

  /// True when the HWND is hidden OR minimized. Passive and safe before init.
  ValueListenable<bool> get isHidden => _hidden;

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  void _notify() {
    if (!_closed) _changes.value++;
  }

  Future<Object?> _invoke(String method, [Map<String, Object>? arguments]) =>
      _native.invoke(method, arguments).timeout(const Duration(seconds: 2));

  Future<void> initialize({required Future<void> Function() onExit}) {
    _onExit = onExit;
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_closed || !_supported) return;
    _native.setEventHandler(_onNativeEvent);
    try {
      final initialTaskbar = _preferences.value.taskbarControls;
      final initialRoundedCorners = _preferences.value.roundedWindowCorners;
      final initialBlur = PlayerExperiencePreferences.safeTrayMenuBlurRadius(
          _preferences.value.trayMenuBlurRadius);
      final language = uiLanguage.value;
      final appearance = _syncAppearance ? _appearance() : null;
      _applyState(await _invoke('configure', {
        ...desktopTrayIconConfiguration(),
        'taskbarControls': initialTaskbar,
        'trayMenuBlurRadius': initialBlur,
        'roundedWindowCorners': initialRoundedCorners,
        'windowCornerRadius': AppShape.surfaceRadius.topLeft.x,
        'labels': _menuLabels(),
        if (appearance != null) 'dark': appearance.$1,
        if (appearance != null) 'accent': appearance.$2,
        if (appearance != null) 'fontFamily': appearance.$3,
        if (appearance != null) 'fontPath': appearance.$4,
      }));
      if (_closed) return;
      _sentTaskbar = initialTaskbar;
      _sentTrayBlurRadius = initialBlur;
      _sentRoundedCorners = initialRoundedCorners;
      _sentAppearance = appearance;
      _sentLanguage = language;
      _started = true;
      _preview = TaskbarPreviewPublisher(
          invoke: _invoke,
          renderer: _previewRenderer,
          onReady: () {
            _previewError = null;
            _notify();
          },
          onError: (error) {
            _previewError = '歌曲预览暂不可用，已回退为系统缩略图。';
            LOGGER.w('Taskbar preview: $error');
            _notify();
          });
      _preferences.addListener(_scheduleSync);
      uiLanguage.addListener(_scheduleSync);
      if (_syncAppearance) _theme.addListener(_scheduleSync);
      _playback.addListener(_scheduleSync);
      _playback.startObserving();
      _scheduleSync();
    } catch (error, trace) {
      if (_closed) return;
      _lastError = '桌面集成初始化失败，请重试。';
      LOGGER.w('桌面集成初始化失败：$error', stackTrace: trace);
      _available = false;
      _notify();
    }
  }

  (bool, int, String, String) _appearance() {
    final scheme = _theme.currScheme;
    final argb = scheme.primary.toARGB32();
    // Win32 COLORREF is 0x00BBGGRR, while Flutter stores 0xAARRGGBB.
    final colorRef =
        ((argb >> 16) & 0xff) | (argb & 0x0000ff00) | ((argb & 0xff) << 16);
    final family = _theme.fontFamily;
    final settings = AppSettings.instance;
    final fontPath = family == danEmbeddedFontFamily
        ? path.join(File(Platform.resolvedExecutable).parent.path, 'data',
            'flutter_assets', 'assets', 'fonts', 'PingFangSC-Regular.ttf')
        : settings.fontFamily == family
            ? settings.fontPath ?? ''
            : '';
    return (scheme.brightness == Brightness.dark, colorRef, family, fontPath);
  }

  void _applyState(Object? raw) {
    if (_closed || raw is! Map) return;
    final revision = raw['revision'];
    if (revision is int) {
      if (revision < _nativeRevision) return;
      _nativeRevision = revision;
    }
    final wasAvailable = _available;
    if (raw['trayAvailable'] is bool) {
      _available = raw['trayAvailable'] as bool;
    }
    if (raw['taskbarAvailable'] is bool) {
      _taskbarAvailable = raw['taskbarAvailable'] as bool;
    }
    final visible = raw['windowVisible'];
    final minimized = raw['minimized'];
    if (visible is bool && minimized is bool) {
      _hidden.value = !visible || minimized;
    }
    _lastError = switch (raw['reason']) {
      'tray_unavailable' => '系统托盘暂不可用；关闭窗口将正常退出。',
      final String _ => '桌面集成暂不可用，请重试。',
      _ => null,
    };
    _notify();
    // Explorer may restart while hidden. If re-registering the icon fails,
    // restore our own HWND so the user is not left with unreachable playback.
    if (wasAvailable && !_available && visible == false && !_exitRequested) {
      _recoverUnreachableWindow();
    }
  }

  void _recoverUnreachableWindow() {
    if (_recoveringWindow || _closed) return;
    _recoveringWindow = true;
    unawaited(showWindow().catchError((Object error) {
      _lastError = '恢复播放器窗口失败，请重试。';
      _notify();
    }).whenComplete(() => _recoveringWindow = false));
  }

  void _scheduleSync() {
    if (!_started || _closed || _syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (_closed) return;
      // Artwork loading/rendering is not in _nativeTail: slow covers cannot
      // delay play/pause buttons, tray restoration or exit.
      _preview?.synchronize(
          enabled: _preferences.value.taskbarSongPreview,
          track: _playback.value.preview,
          scheme: _syncAppearance
              ? _theme.currScheme
              : ColorScheme.fromSeed(seedColor: Colors.teal),
          fontFamily: _syncAppearance ? _theme.fontFamily : 'DanPingFangSC');
      _nativeTail = _nativeTail.then((_) async {
        if (_closed) return;
        final taskbar = _preferences.value.taskbarControls;
        final roundedCorners = _preferences.value.roundedWindowCorners;
        final blurRadius = PlayerExperiencePreferences.safeTrayMenuBlurRadius(
            _preferences.value.trayMenuBlurRadius);
        final appearance = _syncAppearance ? _appearance() : null;
        final language = uiLanguage.value;
        if (_sentTaskbar != taskbar ||
            _sentTrayBlurRadius != blurRadius ||
            _sentRoundedCorners != roundedCorners ||
            _sentAppearance != appearance ||
            _sentLanguage != language) {
          _applyState(await _invoke('configure', {
            ...desktopTrayIconConfiguration(),
            'taskbarControls': taskbar,
            'trayMenuBlurRadius': blurRadius,
            'roundedWindowCorners': roundedCorners,
            'windowCornerRadius': AppShape.surfaceRadius.topLeft.x,
            if (_sentLanguage != language) 'labels': _menuLabels(),
            if (appearance != null) 'dark': appearance.$1,
            if (appearance != null) 'accent': appearance.$2,
            if (appearance != null) 'fontFamily': appearance.$3,
            if (appearance != null) 'fontPath': appearance.$4,
          }));
          _sentTaskbar = taskbar;
          _sentTrayBlurRadius = blurRadius;
          _sentRoundedCorners = roundedCorners;
          _sentAppearance = appearance;
          _sentLanguage = language;
        }
        final snapshot = _playback.value;
        if (!_closed && _sentPlayback != snapshot) {
          await _invoke('updatePlayback', snapshot.toMap());
          _sentPlayback = snapshot;
        }
      }).catchError((Object error, StackTrace trace) {
        if (_closed) return;
        _lastError = '更新桌面播放控制失败，请重试。';
        LOGGER.w('更新桌面播放控制失败：$error', stackTrace: trace);
        _notify();
      });
    });
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    if (_closed) return;
    if (call.method == 'stateChanged') {
      _applyState(call.arguments);
    } else if (call.method == 'action' && call.arguments is String) {
      await dispatchAction(call.arguments as String);
    }
  }

  @visibleForTesting
  Future<void> dispatchAction(String action) async {
    if (_closed || _exitRequested) return;
    try {
      switch (action) {
        case 'restore':
          await showWindow();
        case 'showMain':
          await showWindow(mini: false);
        case 'showMini':
          await showWindow(mini: true);
        case 'exit':
          _exitRequested = true;
          await _onExit?.call();
        default:
          // A stale Shell menu must not bypass current queue/buffering checks.
          if (_playback.value.allows(action)) {
            await _playback.runAction(action);
          }
      }
    } catch (error, trace) {
      if (_closed) return;
      // A failed exit callback that never started disposal must remain
      // retryable; a successfully started shutdown keeps the one-way gate.
      if (action == 'exit') _exitRequested = false;
      final message = '桌面操作失败：$error';
      _lastError = '桌面操作失败，请重试。';
      LOGGER.w(message, stackTrace: trace);
      _notify();
      if (_hidden.value) {
        try {
          await showWindow();
        } catch (_) {}
      }
      _onError?.call(message);
    }
  }

  Future<T> _windowOperation<T>(Future<T> Function() action) {
    final result = _windowTail.then((_) => action());
    _windowTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> hideToTray() => _windowOperation(() async {
        if (!_started || _closed || _exitRequested) return false;
        try {
          // Revalidate with Shell immediately before hiding; an old status bit
          // alone is not enough after an Explorer restart or registration error.
          final confirmation = await _invoke('prepareHide');
          _applyState(confirmation);
          if (confirmation is! Map ||
              confirmation['trayAvailable'] != true ||
              !isAvailable ||
              _exitRequested) {
            return false;
          }
          await _window.hide();
          if (_closed || _exitRequested) return false;
          _hidden.value = true;
          _applyState(await _invoke('getState'));
          return true;
        } catch (error, trace) {
          LOGGER.w('隐藏到托盘失败：$error', stackTrace: trace);
          // A failure after hide must also be recoverable before the caller
          // chooses the normal exit fallback.
          try {
            if (!_closed && !_exitRequested) await _window.show();
          } catch (_) {}
          if (!_closed) _hidden.value = false;
          return false;
        }
      });

  Future<void> showWindow({bool? mini}) => _windowOperation(() async {
        if (_closed || _exitRequested) return;
        await _window.show(mini: mini);
        if (_closed) return;
        _hidden.value = false;
        if (_started) _applyState(await _invoke('getState'));
      });

  Future<void> dispose() => _disposal ??= _dispose();

  /// A failed final window close can leave the already-disposed player visible.
  /// Restore only its retry/error UI: never re-register native callbacks, tray
  /// resources, playback observers, or audio. Ordinary hidden windows cannot
  /// bypass the normal tray restore checks through this shutdown-only entry.
  void restorePresentationAfterFailedShutdown() {
    if (!_closed) return;
    _hidden.value = false;
  }

  Future<void> _dispose() async {
    if (_closed) return;
    _closed = true;
    _exitRequested = true;
    _available = false;
    _taskbarAvailable = false;
    // Publish synchronously before the first await. Mounted visual consumers
    // can stop work immediately while async stream/native teardown completes.
    _hidden.value = true;
    _changes.value++;
    _native.setEventHandler(null);
    if (_started) {
      _preferences.removeListener(_scheduleSync);
      uiLanguage.removeListener(_scheduleSync);
      if (_syncAppearance) _theme.removeListener(_scheduleSync);
      _playback.removeListener(_scheduleSync);
      try {
        await _playback.stopObserving();
      } catch (error, trace) {
        LOGGER.w('解绑桌面播放状态失败：$error', stackTrace: trace);
      }
    }
    try {
      await _preview?.dispose();
      if (_supported) await _invoke('dispose');
    } catch (error, trace) {
      LOGGER.w('清理桌面集成失败：$error', stackTrace: trace);
    }
    // Listenable objects intentionally survive final process cleanup. Existing
    // mounted settings/background widgets may remove listeners during teardown.
  }
}

/// Preserves the route tree, scroll state and playback service while the native
/// window is hidden. Stream/timer-driven visuals can additionally listen to
/// DesktopIntegration.instance.isHidden; no application lifecycle is fabricated.
class DesktopVisibilityHost extends StatelessWidget {
  const DesktopVisibilityHost({super.key, required this.child, this.isHidden});

  final Widget child;
  final ValueListenable<bool>? isHidden;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: isHidden ?? DesktopIntegration.instance.isHidden,
        child: child,
        builder: (context, hidden, child) => TickerMode(
          enabled:
              !hidden || !RenderingPreferencesScope.of(context).pauseWhenHidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: IgnorePointer(ignoring: hidden, child: child),
          ),
        ),
      );
}
