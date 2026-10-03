import 'dart:async';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class TaskbarLyricPreferenceSaveError implements Exception {
  const TaskbarLyricPreferenceSaveError(this.cause);
  final Object cause;
  @override
  String toString() => 'Taskbar lyric preference save failed: $cause';
}

@visibleForTesting
TaskbarLyricSource playerTaskbarLyricSourceForTesting(PlayService service) =>
    _PlayerTaskbarLyricSource(service);

class _PlayerTaskbarLyricSource extends TaskbarLyricSource {
  _PlayerTaskbarLyricSource(PlayService service)
      : _playback = service.playbackService,
        _lyrics = service.lyricService {
    _playback.addListener(_changed);
    _lyrics.addListener(_changed);
    _playback.playbackIntent.addListener(_changed);
    _playback.playbackRate.addListener(_changed);
    _playback.resolvingAudioPath.addListener(_changed);
    _playback.isBuffering.addListener(_changed);
    _playback.isChangingOutput.addListener(_changed);
    _playback.playlist.addListener(_changed);
    _playback.playMode.addListener(_changed);
    _playback.shuffle.addListener(_changed);
    _playback.stopAfterCurrent.addListener(_changed);
    _playback.segmentLoop.addListener(_changed);
    AudioLibrary.changes.addListener(_changed);
    _positions = _playback.positionStream.listen((_) => _changed());
    _states = _playback.playerStateStream.listen((_) => _changed());
    _lines = _lyrics.lyricLineStream.listen((_) => _changed());
  }
  final PlaybackService _playback;
  final LyricService _lyrics;
  late final StreamSubscription<double> _positions;
  late final StreamSubscription<PlayerState> _states;
  late final StreamSubscription<int> _lines;
  void _changed() => notifyListeners();
  @override
  Future<Lyric?> get lyric => _lyrics.currLyricFuture;
  @override
  int get generation => _lyrics.resolutionGeneration;
  @override
  int get session => _playback.playbackSessionToken;
  @override
  bool get hasTrack =>
      _playback.nowPlaying != null &&
      _playback.resolvingAudioPath.value == null;
  @override
  double get position => _playback.position;
  @override
  bool get playing => _playback.playerState == PlayerState.playing;
  @override
  bool get paused =>
      _playback.playerState == PlayerState.paused ||
      _playback.playerState == PlayerState.pausedDevice;
  @override
  double get playbackRate => _playback.playbackRate.value;
  @override
  Object get intent => _playback.playbackIntent.value;
  @override
  double get duration => _playback.length;
  @override
  String get nextTrackTitle =>
      _playback.nextAutomaticQueueAudio?.displayTitle ?? '';
  @override
  bool get nextButtonEnabled =>
      hasTrack &&
      _playback.playlist.value.isNotEmpty &&
      !_playback.isBuffering.value &&
      _playback.resolvingAudioPath.value == null &&
      !_playback.isChangingOutput.value &&
      _playback.playerState != PlayerState.stalled;
  @override
  bool get playbackButtonEnabled =>
      hasTrack &&
      !_playback.isBuffering.value &&
      !_playback.isChangingOutput.value &&
      switch (_playback.playerState) {
        PlayerState.playing ||
        PlayerState.paused ||
        PlayerState.pausedDevice ||
        PlayerState.stopped ||
        PlayerState.completed =>
          true,
        PlayerState.stalled || PlayerState.unknown => false,
      };
  @override
  void dispose() {
    _playback.removeListener(_changed);
    _lyrics.removeListener(_changed);
    _playback.playbackIntent.removeListener(_changed);
    _playback.playbackRate.removeListener(_changed);
    _playback.resolvingAudioPath.removeListener(_changed);
    _playback.isBuffering.removeListener(_changed);
    _playback.isChangingOutput.removeListener(_changed);
    _playback.playlist.removeListener(_changed);
    _playback.playMode.removeListener(_changed);
    _playback.shuffle.removeListener(_changed);
    _playback.stopAfterCurrent.removeListener(_changed);
    _playback.segmentLoop.removeListener(_changed);
    AudioLibrary.changes.removeListener(_changed);
    unawaited(_positions.cancel());
    unawaited(_states.cancel());
    unawaited(_lines.cancel());
    super.dispose();
  }
}

/// Owns only optional taskbar subscriptions. The disabled service is passive.
/// Native transport/appearance are supplied by DesktopIntegration's lifecycle.
class TaskbarLyricService with WidgetsBindingObserver {
  TaskbarLyricService({
    required ValueNotifier<PlayerExperiencePreferences> preferences,
    required ValueListenable<bool> playbackReady,
    required TaskbarLyricSource Function() createSource,
    required LyricDisplayCoordinator coordinator,
    required Future<void> Function() savePreferences,
    required ValueListenable<Object?> rendering,
    ValueListenable<Object?>? appearanceChanges,
    bool Function()? animationsAllowed,
    bool Function()? layoutAnimationsAllowed,
  })  : _preferences = preferences,
        _playbackReady = playbackReady,
        _createSource = createSource,
        _coordinator = coordinator,
        _savePreferences = savePreferences,
        _rendering = rendering,
        _appearanceChanges = appearanceChanges,
        _animationsAllowed = animationsAllowed ?? (() => true),
        _layoutAnimationsAllowed =
            layoutAnimationsAllowed ?? animationsAllowed ?? (() => true);

  static final instance = TaskbarLyricService(
    preferences: AppSettings.instance.experience,
    playbackReady: PlayService.playbackReady,
    createSource: () => _PlayerTaskbarLyricSource(PlayService.instance),
    coordinator: LyricDisplayCoordinator.shared,
    savePreferences: () => AppSettings.instance
        .saveSettings(throwOnError: true, captureWindowSize: false),
    rendering: AppSettings.instance.rendering,
    animationsAllowed: () => AppSettings.instance.rendering.value.animations
        .allows(MotionKind.lyrics),
    layoutAnimationsAllowed: () => AppSettings
        .instance.rendering.value.animations
        .allows(MotionKind.layout),
  );

  final ValueNotifier<PlayerExperiencePreferences> _preferences;
  final ValueListenable<bool> _playbackReady;
  final TaskbarLyricSource Function() _createSource;
  final LyricDisplayCoordinator _coordinator;
  final Future<void> Function() _savePreferences;
  final ValueListenable<Object?> _rendering;
  final ValueListenable<Object?>? _appearanceChanges;
  final bool Function() _animationsAllowed;
  final bool Function() _layoutAnimationsAllowed;
  Future<void> Function(Map<String, Object>)? _send;
  TaskbarLyricAppearance Function()? _appearance;
  TaskbarLyricAppearance? _cachedAppearance;
  void Function(Object, StackTrace)? _onError;
  TaskbarLyricsPublisher? _publisher;
  TaskbarLyricSource? _source;
  bool _attached = false;
  bool _disposed = false;
  bool _changingPreference = false;
  bool _enabled = false;
  bool _nativeEnabled = false;
  Object? _lastAppearanceSettings;
  int _generation = 0;
  Future<void> _closeTail = Future.value();
  late final Future<void> Function() _closeCallback = _close;
  late final void Function() _desktopRequestCallback = _desktopRequested;
  late final Future<bool> Function() _taskbarRequestCallback = _requestTaskbar;
  Future<bool> _requestTaskbar() => setEnabled(true);

  /// Recheck a native button click against the live source, not its last frame.
  /// Other desktop Next actions retain their existing interrupt-loading policy.
  bool get runtimeCanNext =>
      !_disposed &&
      _enabled &&
      _playbackReady.value &&
      _preferences.value.taskbarAppearance.showNextButton &&
      _source?.hasTrack == true &&
      _source!.nextButtonEnabled;

  bool get runtimeCanPlayPause =>
      !_disposed &&
      _enabled &&
      _nativeEnabled &&
      _publisher != null &&
      _playbackReady.value &&
      _preferences.value.taskbarAppearance.showPauseIndicator &&
      _source?.hasTrack == true &&
      _source!.playbackButtonEnabled;

  void attach({
    required Future<void> Function(Map<String, Object>) send,
    required TaskbarLyricAppearance Function() appearance,
    required void Function(Object, StackTrace) onError,
  }) {
    if (_attached || _disposed) return;
    _attached = true;
    _send = send;
    _appearance = appearance;
    _onError = onError;
    _coordinator.register(LyricDisplayMode.taskbar, _closeCallback);
    _coordinator.beforeDesktopRequest = _desktopRequestCallback;
    _coordinator.requestTaskbar = _taskbarRequestCallback;
    _preferences.addListener(_preferenceChanged);
    _preferenceChanged();
  }

  void _writePreference(bool value) {
    if (_preferences.value.taskbarLyrics == value) return;
    _changingPreference = true;
    try {
      _preferences.value = _preferences.value.copyWith(taskbarLyrics: value);
    } finally {
      _changingPreference = false;
    }
  }

  void _desktopRequested() {
    _generation++;
    _enabled = false;
    _playbackReady.removeListener(_ready);
    if (!_preferences.value.taskbarLyrics) return;
    _writePreference(false);
    unawaited(_persist());
  }

  void _preferenceChanged() {
    if (_changingPreference || _disposed || !_attached) return;
    final enabled = _preferences.value.taskbarLyrics;
    final appearanceSettings = _preferences.value.taskbarAppearance;
    final appearanceChanged = appearanceSettings != _lastAppearanceSettings;
    _lastAppearanceSettings = appearanceSettings;
    if (enabled == _enabled) {
      if (appearanceChanged) refreshAppearance();
      return;
    }
    unawaited(_transition(enabled).catchError((Object error, StackTrace trace) {
      _report(error, trace);
      return false;
    }));
  }

  Future<bool> setEnabled(bool enabled) async {
    if (_disposed || !_attached) return false;
    _writePreference(enabled);
    final result = await _transition(enabled, persistRollback: false);
    final persisted = await _persist();
    return result && persisted;
  }

  Future<bool> _transition(bool enabled, {bool persistRollback = true}) async {
    final generation = ++_generation;
    _enabled = enabled;
    if (!enabled) {
      _playbackReady.removeListener(_ready);
      await _coordinator.hide(LyricDisplayMode.taskbar);
      return generation == _generation;
    }
    _playbackReady.removeListener(_ready);
    _playbackReady.addListener(_ready);
    try {
      return await _coordinator.show(LyricDisplayMode.taskbar, () async {
        if (_enabled && generation == _generation) await _open();
      });
    } catch (error, trace) {
      if (generation == _generation) {
        _enabled = false;
        _writePreference(false);
        _playbackReady.removeListener(_ready);
        if (persistRollback) unawaited(_persist());
      }
      _report(error, trace);
      return false;
    }
  }

  void _ready() {
    if (!_enabled || _disposed || !_playbackReady.value) return;
    unawaited(_transition(true));
  }

  TaskbarLyricAppearance _currentAppearance() {
    final style = _cachedAppearance ??= _appearance!();
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return TaskbarLyricAppearance(
      accent: style.accent,
      fontFamily: style.fontFamily,
      fontPath: style.fontPath,
      placement: style.placement,
      areaSelection: style.areaSelection,
      showNextTrack: style.showNextTrack,
      showNextLyric: style.showNextLyric,
      showPauseIndicator: style.showPauseIndicator,
      strokeEnabled: style.strokeEnabled,
      colorScheme: style.colorScheme,
      showNextButton: style.showNextButton,
      animate: style.animate &&
          _animationsAllowed() &&
          !features.disableAnimations &&
          !features.reduceMotion,
      layoutAnimate: style.animate &&
          style.layoutAnimate &&
          _layoutAnimationsAllowed() &&
          !features.disableAnimations &&
          !features.reduceMotion,
    );
  }

  Future<void> _open() async {
    if (_disposed || !_enabled || !_playbackReady.value || _publisher != null) {
      return;
    }
    final generation = _generation;
    final style = _currentAppearance();
    // Acknowledge capability/errors before attaching any lyric/clock observer.
    await _send!({
      'enabled': true,
      'text': '',
      'accent': style.accent,
      'fontFamily': style.fontFamily,
      'fontPath': style.fontPath,
      'animate': style.animate,
      'animateLayout': style.layoutAnimate,
      'playing': false,
      'paused': false,
      'nextText': '',
      'words': <Object>[],
      'sourceIdentity': '',
      'lineIdentity': '',
      'positionMilliseconds': 0,
      'playbackRate': 1.0,
      'lineStartMilliseconds': 0,
      'lineEndMilliseconds': 0,
      'timelineRevision': 0,
      'placement': style.placement,
      'areaSelection': style.areaSelection,
      'nextTrackText': '',
      'showPauseIndicator': false,
      'playbackButtonEnabled': false,
      'showNextLyric': style.showNextLyric,
      'strokeEnabled': style.strokeEnabled,
      'colorScheme': style.colorScheme,
      'showNextButton': style.showNextButton,
      'nextButtonEnabled': false,
    });
    _nativeEnabled = true;
    if (_disposed || !_enabled || generation != _generation) return;
    _cachedAppearance = _appearance!();
    final source = _createSource();
    _source = source;
    _publisher = TaskbarLyricsPublisher(
      source: source,
      appearance: _currentAppearance,
      send: _send!,
      onError: _publicationFailed,
    );
    _rendering.addListener(refreshAppearance);
    _appearanceChanges?.addListener(refreshAppearance);
    WidgetsBinding.instance.addObserver(this);
  }

  void refreshAppearance() {
    if (_publisher == null) return;
    _cachedAppearance = _appearance!();
    _publisher!.refresh();
  }

  @override
  void didChangeAccessibilityFeatures() => refreshAppearance();

  Future<void> _close() {
    final result = _closeTail.then((_) async {
      final publisher = _publisher;
      _publisher = null;
      final source = _source;
      _source = null;
      _rendering.removeListener(refreshAppearance);
      _appearanceChanges?.removeListener(refreshAppearance);
      WidgetsBinding.instance.removeObserver(this);
      if (publisher != null) {
        final closing = publisher.close();
        source?.dispose();
        await closing;
      } else if (_nativeEnabled) {
        source?.dispose();
        await _send!({'enabled': false, 'text': ''});
      } else {
        source?.dispose();
      }
      _nativeEnabled = false;
    });
    _closeTail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _report(Object error, StackTrace trace) => _onError?.call(error, trace);

  void _publicationFailed(Object error, StackTrace trace) {
    if (!_enabled || _disposed) return;
    _enabled = false;
    _generation++;
    _writePreference(false);
    _playbackReady.removeListener(_ready);
    _report(error, trace);
    unawaited(_coordinator
        .hide(LyricDisplayMode.taskbar)
        .catchError((Object _, StackTrace __) {}));
    unawaited(_persist());
  }

  Future<bool> _persist() async {
    if (_disposed) return false;
    try {
      await _savePreferences();
      return true;
    } catch (error, trace) {
      if (!_disposed) _report(TaskbarLyricPreferenceSaveError(error), trace);
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _enabled = false;
    _generation++;
    _preferences.removeListener(_preferenceChanged);
    _playbackReady.removeListener(_ready);
    await _coordinator.hide(LyricDisplayMode.taskbar);
    _coordinator.unregister(LyricDisplayMode.taskbar, _closeCallback);
    if (identical(_coordinator.beforeDesktopRequest, _desktopRequestCallback)) {
      _coordinator.beforeDesktopRequest = null;
    }
    if (identical(_coordinator.requestTaskbar, _taskbarRequestCallback)) {
      _coordinator.requestTaskbar = null;
    }
  }
}
