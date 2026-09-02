import 'dart:async';

import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Construction is still owned by startup/playback actions, never a widget.
/// Publishing in a microtask lets the caller assign its late-final resource
/// before any listener can read it, and avoids notifying during a widget build.
class PlaybackReadiness extends ChangeNotifier
    implements ValueListenable<bool> {
  bool _ready = false;
  bool _scheduled = false;
  bool _disposed = false;

  @override
  bool get value => _ready;

  T initialize<T>(T Function() create) {
    if (_disposed) throw StateError('Playback readiness has been disposed');
    final resource = create();
    // A failed constructor does not reach this point and never reports ready.
    if (!_ready && !_scheduled) {
      _scheduled = true;
      scheduleMicrotask(() {
        if (_disposed || !_scheduled) return;
        _scheduled = false;
        _ready = true;
        notifyListeners();
      });
    }
    return resource;
  }

  /// A constructed resource may be closed before its ready microtask runs.
  /// Cancelling only the pending publication preserves the existing ready
  /// semantics and leaves mounted listeners safe to detach during shutdown.
  void cancelPendingInitialization() {
    _scheduled = false;
  }

  @override
  void dispose() {
    cancelPendingInitialization();
    _disposed = true;
    super.dispose();
  }
}

/// A passive gate: listening to readiness does not access PlayService.instance
/// or construct a native player. Tests can inject an in-memory readiness flag.
class PlaybackReadyBuilder extends StatelessWidget {
  const PlaybackReadyBuilder({
    super.key,
    this.readiness,
    required this.readyBuilder,
    required this.waitingBuilder,
  });

  final ValueListenable<bool>? readiness;
  final WidgetBuilder readyBuilder;
  final WidgetBuilder waitingBuilder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: readiness ?? PlayService.playbackReady,
        builder: (context, ready, _) =>
            ready ? readyBuilder(context) : waitingBuilder(context),
      );
}

class PlayService {
  PlayService._()
      : _readiness = _playbackReadiness,
        _createPlayback = PlaybackService.new,
        _createLyric = LyricService.new,
        _createDesktopLyric = DesktopLyricService.new;

  /// Owns no native resources until a getter is explicitly used. Fake factories
  /// let shutdown tests exercise the real facade without BASS or helper windows.
  @visibleForTesting
  PlayService.forTesting({
    required PlaybackReadiness readiness,
    required PlaybackService Function(PlayService) createPlayback,
    required DesktopLyricService Function(PlayService) createDesktopLyric,
    LyricService Function(PlayService)? createLyric,
  })  : _readiness = readiness,
        _createPlayback = createPlayback,
        _createLyric = createLyric ?? LyricService.new,
        _createDesktopLyric = createDesktopLyric;

  final PlaybackReadiness _readiness;
  final PlaybackService Function(PlayService) _createPlayback;
  final LyricService Function(PlayService) _createLyric;
  final DesktopLyricService Function(PlayService) _createDesktopLyric;
  PlaybackService? _playbackService;
  LyricService? _lyricService;
  DesktopLyricService? _desktopLyricService;
  Future<void>? _closeFuture;
  bool _closing = false;

  PlaybackService get playbackService {
    final existing = _playbackService;
    if (existing != null) return existing;
    _ensureCanCreate();
    final created =
        _readiness.initialize<PlaybackService>(() => _createPlayback(this));
    _playbackService = created;
    return created;
  }

  /// Construct native playback during the startup transition, before song
  /// tiles become interactive. In particular, this lets a persisted exclusive
  /// output preference acquire and prewarm its endpoint outside a tap frame.
  void ensurePlaybackInitialized() {
    playbackService;
  }

  LyricService get lyricService {
    final existing = _lyricService;
    if (existing != null) return existing;
    _ensureCanCreate();
    return _lyricService = _createLyric(this);
  }

  DesktopLyricService get desktopLyricService {
    final existing = _desktopLyricService;
    if (existing != null) return existing;
    _ensureCanCreate();
    return _desktopLyricService = _createDesktopLyric(this);
  }

  void _ensureCanCreate() {
    if (_closing) throw StateError('播放器正在退出，不能创建新的播放资源');
  }

  static PlayService? _instance;
  static final _playbackReadiness = PlaybackReadiness();
  static ValueListenable<bool> get playbackReady => _playbackReadiness;

  static bool get hasFacade => _instance != null;

  // Kept for existing callers: a facade may exist before its lazy player.
  static bool get isInitialized => hasFacade;

  static PlayService get instance {
    _instance ??= PlayService._();
    return _instance!;
  }

  /// Flush an already-created player without constructing native playback.
  static Future<void> flushExistingPlaybackState() =>
      _instance?._playbackService?.flushPlaybackState() ?? Future<void>.value();

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _readiness.cancelPendingInitialization();
    // Never invoke a lazy getter here: a lyric-only or unused facade must not
    // initialize BASS while exiting. An existing player can also precede its
    // ready microtask, so test the owned resource rather than readiness.value.
    try {
      _lyricService?.dispose();
    } finally {
      try {
        final desktopLyric = _desktopLyricService;
        if (desktopLyric != null) {
          desktopLyric.dispose();
          // dispose stops helper input and flushes the slider debounce; await
          // its existing/new save tail before the process/window can exit.
          await desktopLyric.flushAppearance();
        }
      } finally {
        await _playbackService?.close();
      }
    }
  }
}
