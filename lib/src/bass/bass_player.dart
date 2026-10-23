import 'package:desktop_lyric/ui_language.dart';
import 'spectrum_analysis.dart';
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/playback_pitch.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/src/bass/bass_diagnostics.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/network_proxy_preferences.dart';
import 'package:dan_player/src/bass/bass_replay_gain.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_transition_mixer.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/play_service/silence_skip_preferences.dart';
import 'package:dan_player/src/bass/bass_silence_analysis.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:dan_player/src/bass/bass_volume.dart';
import 'package:dan_player/src/bass/bass_equalizer.dart';
import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/src/bass/wasapi_output_policy.dart';
import 'package:dan_player/src/bass/bass_wasapi.dart' as BASS;
import 'package:dan_player/utils.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:path/path.dart' as path;
import 'package:dan_player/src/bass/bass.dart' as BASS;
import 'dart:ffi' as ffi;

enum PlayerState {
  /// stop() has been called or the end of an audio has been reached
  stopped,

  /// start() has been called
  playing,

  /// pause() has been called
  paused,

  /// BASS_Pause() has been called or stopping unexpectedly (eg. a USB soundcard being disconnected).
  /// In either case, playback will be resumed by BASS_Start.
  pausedDevice,

  ///Playback of the stream has been stalled due to a lack of sample data.
  ///Playback will automatically resume once there is sufficient data to do so.
  stalled,

  /// the end of an audio has been reached
  completed,

  unknown,
}

extension BassPlaybackIntent on PlayerState {
  /// Starvation is temporary playback, while a paused/unavailable endpoint
  /// requires an explicit transport command before it can resume.
  bool get keepsPlaybackIntent =>
      this == PlayerState.playing || this == PlayerState.stalled;
}

/// A seek invalidates the previous polling stamp. Preserve active playback's
/// position and completion observation without starting a paused transport.
/// A data stall retains playback intent and resumes natively after refill.
Timer? rearmBassPositionUpdaterAfterSeek(
  Timer? current, {
  required PlayerState stateBeforeSeek,
  required Timer Function() create,
}) {
  current?.cancel();
  return stateBeforeSeek.keepsPlaybackIntent ? create() : null;
}

enum BassNetworkConfigurationFailure { proxy, timeout }

/// A native setup failure that can be localized after the URL worker returns.
class BassNetworkConfigurationException implements Exception {
  const BassNetworkConfigurationException(this.failure, this.errorCode);

  final BassNetworkConfigurationFailure failure;
  final int errorCode;

  @override
  String toString() =>
      'BassNetworkConfigurationException(${failure.name}, BASS error $errorCode)';
}

String bassNetworkConfigurationNotice(
        BassNetworkConfigurationException error) =>
    switch (error.failure) {
      BassNetworkConfigurationFailure.proxy =>
        ui('无法设置联网音频代理（BASS 错误码 {0}）。', [error.errorCode]),
      BassNetworkConfigurationFailure.timeout =>
        ui('无法设置联网音频超时（BASS 错误码 {0}）。', [error.errorCode]),
    };

String bassOutputModeFailureNotice(Object error, {required bool restored}) =>
    ui(
      restored ? '输出模式切换失败，已恢复原模式：{0}' : '切换音频输出失败，原模式保持不变：{0}',
      [
        error is BassNetworkConfigurationException
            ? bassNetworkConfigurationNotice(error)
            : error
      ],
    );

class BassPlaybackEvent {
  const BassPlaybackEvent(this.stamp, this.state, {this.reason, this.problem});
  final PlaybackStamp stamp;
  final PlayerState state;
  final PlaybackEndReason? reason;
  final PlaybackProblem? problem;
  bool get completed =>
      reason == PlaybackEndReason.naturalEnd ||
      reason == PlaybackEndReason.segmentEnd;
}

const BASS_PLUGINS = [
  "BASS\\bassape.dll",
  "BASS\\bassdsd.dll",
  "BASS\\bassflac.dll",
  "BASS\\bassmidi.dll",
  "BASS\\bassopus.dll",
  "BASS\\basswv.dll"
];

typedef _BassOpenResult = ({
  int handle,
  int errorCode,
  ReplayGainTags replayGain,
});

class _PreparedBassSource {
  _PreparedBassSource(
      {required this.identity,
      required this.path,
      required this.handle,
      required this.replayGain,
      required this.dspBase,
      required this.format,
      required this.equalizer,
      required this.rate,
      required this.pitch,
      required this.schedule});
  final Object identity;
  final String path;
  final int handle;
  final ReplayGainTags replayGain;
  final double dspBase;
  final BassFormatSnapshot? format;
  final BassEqualizer equalizer;
  final double rate, pitch;
  final BassTransitionSchedule schedule;
}

// BASS_StreamCreateFile may synchronously inspect codec headers and trigger a
// cloud-backed file recall. Keep that work away from Flutter's UI isolate just
// like the network open below. The returned stream handle is process-wide and
// remains valid after this worker releases its DynamicLibrary reference.
Future<_BassOpenResult> _openBassFileInBackground(
  String libraryPath,
  String filePath,
  int flags,
  int device,
  AudioSegment? segment,
) {
  return Isolate.run(
    () => _openBassFile(libraryPath, filePath, flags, device, segment),
    debugName: 'bass-file-open',
  );
}

_BassOpenResult _openBassFile(
  String libraryPath,
  String filePath,
  int flags,
  int device,
  AudioSegment? segment,
) {
  final library = ffi.DynamicLibrary.open(libraryPath);
  ffi.Pointer<ffi.Void>? filePointer;
  try {
    final setDevice = library.lookupFunction<ffi.Int32 Function(ffi.Uint32),
        int Function(int)>('BASS_SetDevice');
    final getError =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'BASS_ErrorGetCode');
    final createFile = library.lookupFunction<
        ffi.Uint32 Function(
          ffi.Int32,
          ffi.Pointer<ffi.Void>,
          ffi.Uint64,
          ffi.Uint64,
          ffi.Uint32,
        ),
        int Function(
          int,
          ffi.Pointer<ffi.Void>,
          int,
          int,
          int,
        )>('BASS_StreamCreateFile');
    filePointer = filePath.toNativeUtf16().cast<ffi.Void>();
    if (setDevice(device) == BASS.FALSE) {
      return (
        handle: 0,
        errorCode: getError(),
        replayGain: const ReplayGainTags(),
      );
    }
    final handle = createFile(BASS.FALSE, filePointer, 0, 0, flags);
    if (handle != 0 && segment != null) {
      final api = BASS.Bass(library);
      try {
        prepareBassSegment(api, handle, segment);
      } catch (_) {
        api.BASS_StreamFree(handle);
        rethrow;
      }
    }
    var replayGain = const ReplayGainTags();
    if (handle != 0) {
      try {
        replayGain = readBassReplayGain(library, handle);
      } catch (_) {
        // Optional metadata must neither fail playback nor orphan the newly
        // opened stream. Unsupported tags simply keep the original volume.
      }
    }
    return (
      handle: handle,
      errorCode: handle == 0 ? getError() : 0,
      replayGain: replayGain,
    );
  } finally {
    if (filePointer != null) ffi.malloc.free(filePointer);
    library.close();
  }
}

// Keep the isolate closure outside BassPlayer so it cannot capture the player,
// its FFI objects, stream controllers, or Flutter state.
Future<_BassOpenResult> _openBassUrlInBackground(
  String libraryPath,
  String url,
  int flags,
  int device,
  int requestId,
  String? proxy,
) {
  return Isolate.run(
    () => _openBassUrl(libraryPath, url, flags, device, requestId, proxy),
    debugName: 'bass-url-open',
  );
}

_BassOpenResult _openBassUrl(
  String libraryPath,
  String url,
  int flags,
  int device,
  int requestId,
  String? proxy,
) {
  final library = ffi.DynamicLibrary.open(libraryPath);
  ffi.Pointer<ffi.Void>? urlPointer;
  ffi.Pointer<ffi.Void>? proxyPointer;
  int Function(int, int)? setConfig;
  const configThread = 0x40000000;
  const netTimeout = 11;
  const netReadTimeout = 37;
  try {
    final setDevice = library.lookupFunction<ffi.Int32 Function(ffi.Uint32),
        int Function(int)>('BASS_SetDevice');
    final getError =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'BASS_ErrorGetCode');
    setConfig = library.lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Uint32),
        int Function(int, int)>('BASS_SetConfig');
    final setConfigPtr = library.lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>),
        int Function(int, ffi.Pointer<ffi.Void>)>('BASS_SetConfigPtr');
    final getConfigPtr = library.lookupFunction<
        ffi.Pointer<ffi.Void> Function(ffi.Uint32),
        ffi.Pointer<ffi.Void> Function(int)>('BASS_GetConfigPtr');
    final createUrl = library.lookupFunction<
        ffi.Uint32 Function(
          ffi.Pointer<ffi.Void>,
          ffi.Uint32,
          ffi.Uint32,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
        ),
        int Function(
          ffi.Pointer<ffi.Void>,
          int,
          int,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Void>,
        )>('BASS_StreamCreateURL');
    urlPointer = url.toNativeUtf16().cast<ffi.Void>();
    proxyPointer = proxy?.toNativeUtf16().cast<ffi.Void>();
    // BASS_CONFIG_NET_PROXY: null = direct, empty = Windows default proxy,
    // server:port = custom. BASS copies the string for later stream use.
    final proxySet =
        setConfigPtr(17 | BASS.BASS_UNICODE, proxyPointer ?? ffi.nullptr);
    // BASS 2.4.18 clears the proxy when given null but can return FALSE/20.
    // Confirm the resulting value before treating direct mode as a failure.
    if (proxySet == BASS.FALSE &&
        !(proxy == null && getConfigPtr(17) == ffi.nullptr)) {
      throw BassNetworkConfigurationException(
          BassNetworkConfigurationFailure.proxy, getError());
    }
    if (setConfig(netTimeout | configThread, 8000) == BASS.FALSE ||
        setConfig(netReadTimeout | configThread, 12000) == BASS.FALSE) {
      throw BassNetworkConfigurationException(
          BassNetworkConfigurationFailure.timeout, getError());
    }

    // BASS's selected device and error code are thread-local. These calls stay
    // in one synchronous worker invocation, with no await between them.
    if (setDevice(device) == BASS.FALSE) {
      return (
        handle: 0,
        errorCode: getError(),
        replayGain: const ReplayGainTags(),
      );
    }
    final handle = createUrl(
      urlPointer,
      0,
      flags,
      ffi.nullptr,
      ffi.Pointer<ffi.Void>.fromAddress(requestId),
    );
    final errorCode = handle == 0 ? getError() : 0;
    return (
      handle: handle,
      errorCode: errorCode,
      replayGain: const ReplayGainTags(),
    );
  } finally {
    if (urlPointer != null) ffi.malloc.free(urlPointer);
    if (proxyPointer != null) ffi.malloc.free(proxyPointer);
    // A VM worker thread may later run another isolate; do not leave per-thread
    // BASS settings behind. The active stream retains its read timeout.
    setConfig?.call(netTimeout | configThread, 0);
    setConfig?.call(netReadTimeout | configThread, 0);
    library.close();
  }
}

class _PendingBassUrlOpen {
  _PendingBassUrlOpen(this.requestId);

  final int requestId;
  final Completer<void> finished = Completer<void>();
  Timer? _cancelTimer;

  void cancel(int Function(ffi.Pointer<ffi.Void>) cancelStream) {
    if (finished.isCompleted || _cancelTimer != null) return;

    void signalCancellation() {
      if (!finished.isCompleted) {
        cancelStream(ffi.Pointer<ffi.Void>.fromAddress(requestId));
      }
    }

    signalCancellation();
    // Cancellation can arrive before the worker has entered native code.
    // Repeat until it returns so that startup race cannot leave an open request.
    _cancelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => signalCancellation(),
    );
  }

  void complete() {
    _cancelTimer?.cancel();
    _cancelTimer = null;
    if (!finished.isCompleted) finished.complete();
  }
}

class _PendingBassFileOpen {
  _PendingBassFileOpen(this.path);

  final String path;
  final Completer<void> finished = Completer<void>();

  void complete() {
    if (!finished.isCompleted) finished.complete();
  }
}

/// Bounds native local-file opens while still letting the latest request get
/// past one slow cloud-backed file. Waiting requests do not create isolates;
/// they re-check the caller's generation before consuming a released slot.
class BassFileOpenGate {
  BassFileOpenGate({this.limit = 2}) : assert(limit > 0);

  final int limit;
  Completer<void>? _latestWaiter;
  int _active = 0;

  Future<bool> acquire(bool Function() mayStart) async {
    if (!mayStart()) return false;
    while (_active >= limit) {
      if (!mayStart()) return false;
      final ready = Completer<void>();
      final superseded = _latestWaiter;
      _latestWaiter = ready;
      if (superseded != null && !superseded.isCompleted) {
        superseded.complete();
      }
      await ready.future;
      if (identical(_latestWaiter, ready)) _latestWaiter = null;
      if (!mayStart()) return false;
    }
    if (!mayStart()) return false;
    _active += 1;
    return true;
  }

  void release() {
    assert(_active > 0);
    if (_active == 0) return;
    _active -= 1;
    _wakeLatest();
  }

  /// Wakes queued callers during shutdown; their generation predicate rejects
  /// them before they can start a native worker.
  void cancelWaiters() {
    final waiter = _latestWaiter;
    _latestWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _wakeLatest() {
    if (_active >= limit) return;
    final waiter = _latestWaiter;
    _latestWaiter = null;
    if (waiter == null) return;
    if (!waiter.isCompleted) waiter.complete();
  }
}

/// Serializes the process-wide BASS proxy setting with URL stream creation.
/// FIFO preserves progress when more than one BassPlayer is active; stale
/// generations are removed without starting another native worker.
class BassUrlOpenGate {
  bool _active = false;
  final Queue<({bool Function() mayStart, Completer<bool> ready})> _waiting =
      Queue();

  Future<bool> acquire(bool Function() mayStart) {
    if (!mayStart()) return Future.value(false);
    if (!_active && _waiting.isEmpty) {
      _active = true;
      return Future.value(true);
    }
    final ready = Completer<bool>();
    _waiting.add((mayStart: mayStart, ready: ready));
    return ready.future;
  }

  void release() {
    assert(_active);
    if (!_active) return;
    _active = false;
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      if (!next.mayStart()) {
        next.ready.complete(false);
        continue;
      }
      _active = true;
      next.ready.complete(true);
      return;
    }
  }

  void cancelStaleWaiters() {
    final retained =
        Queue<({bool Function() mayStart, Completer<bool> ready})>();
    while (_waiting.isNotEmpty) {
      final next = _waiting.removeFirst();
      if (next.mayStart()) {
        retained.add(next);
      } else {
        next.ready.complete(false);
      }
    }
    _waiting.addAll(retained);
  }
}

class BassPlayer {
  // Device 0 and a decoding mixer let native integration tests exercise this
  // exact pipeline without acquiring or changing a user's audio endpoint.
  final bool _offlineOutput;
  final bool _bufferedOfflineOutput;
  bool get _decodingOfflineMixer => _offlineOutput && !_bufferedOfflineOutput;
  static const int _bassAttribFreq = 1;
  static const int _bassDataFft4096 = 0x80000004;
  static const int _bassDataFftRemoveDc = 0x40;
  static const int _bassWasapiBuffer = 4;
  static const int _bassWasapiAutoFormat = 2;
  static const int _fftSize = 4096;
  static const int _fftValueCount = _fftSize ~/ 2;
  static const int _bassErrorValue = 0xFFFFFFFF;
  static const int _bassPositionErrorValue = 0xFFFFFFFFFFFFFFFF;
  static int _nextNetworkRequestId = 1;

  late final String _bassLibraryPath;
  late final ffi.DynamicLibrary _bassLib;
  late final ffi.DynamicLibrary _bassWasapiLib;
  late final BASS.Bass _bass;
  late final BassPlaybackVolume _playbackVolume;
  late final BASS.BassWasapi _bassWasapi;
  BassMixLibrary? _mix;
  BassTempoLibrary? _tempo;
  String? exclusiveOutputUnavailableReason;
  String? tempoUnavailableReason;
  double _playbackRate = 1.0;
  double _playbackPitch = 0.0;
  bool _wasapiInitialized = false;
  int? _exclusiveMixer;
  int? _sharedMixer;
  bool _streamUsesMixer = false;
  PlaybackTransitionPreferences _transitions =
      const PlaybackTransitionPreferences();
  SilenceSkipPreferences _silenceSkipping = const SilenceSkipPreferences();
  BassSilenceBounds? _silenceBounds;
  int? _silenceDecoder;
  final _silenceScans = <BassSilenceScan>{};
  BassTransitionMixer? _transitionMixer;
  _PreparedBassSource? _preparedSource;
  _PreparedBassSource? _transitionTail;
  int _preparationGeneration = 0;
  bool _transitionAnnounced = false;
  ({PlaybackStamp stamp, int endByte})? _sharedCompletionDrain;
  int _stateNativeError = 0;
  int? get _activeMixer => wasapiExclusive ? _exclusiveMixer : _sharedMixer;
  int? get nativeMixerHandle => _activeMixer;
  bool get supportsTransitions => !_freed && _mix != null;
  Object? get preparedSourceIdentity => _preparedSource?.identity;

  /// A source's effective natural end, while [length] remains its original
  /// metadata/seek duration. Only the decoder enforces this boundary.
  double get naturalEndPosition => _silenceBounds?.end ?? length;
  BassSilenceBounds? get silenceBounds => _silenceBounds;

  void configureSilenceSkipping(SilenceSkipPreferences preferences) {
    if (preferences == _silenceSkipping) return;
    _silenceSkipping = preferences;
    for (final scan in _silenceScans) scan.cancel();
    cancelPreparedSource();
  }

  /// Explicit seek and practice take precedence over edge trimming for the
  /// rest of this source. The caller's subsequent seek flushes decoded buffers.
  void restoreFullSilenceRange() {
    final decoder = _silenceDecoder;
    if (_silenceBounds == null || decoder == null) return;
    if (_bass.BASS_ChannelSetPosition(decoder, 0, 0x10) == 0) {
      throw FormatException('无法恢复原始音频范围（BASS ${_bass.BASS_ErrorGetCode()}）');
    }
    _silenceBounds = null;
    _silenceDecoder = null;
  }

  /// A changed preference applies at the next explicit source load. Native
  /// source/output handles are never rebuilt by opening a settings surface.
  void configureTransitions(PlaybackTransitionPreferences preferences) {
    if (_transitions == preferences) return;
    cancelPreparedSource();
    _retireTransitionTail();
    _transitions = preferences;
  }

  double get playbackRate => _playbackRate;
  bool get supportsPlaybackRate => !_freed && _tempo != null;
  double get playbackPitch => _playbackPitch;
  bool get supportsPlaybackPitch => !_freed && _tempo != null;

  String? _fPath;
  bool _sourceIsUrl = false;
  AudioSegment? _segment;
  double? _segmentLength;
  int? _fstream;
  bool get hasSource => !_freed && _fstream != null;
  double _userVolumeDsp = 1;
  double _lastAudibleVolumeDsp = 1;
  double _volumeDspBase = 1;
  bool get _hasSharedMuteGate =>
      !_decodingOfflineMixer &&
      !wasapiExclusive &&
      _streamUsesMixer &&
      _sharedMixer != null;
  double get _sharedSourceVolume =>
      _userVolumeDsp == 0 ? _lastAudibleVolumeDsp : _userVolumeDsp;
  ReplayGainPreferences _replayGain = const ReplayGainPreferences();
  ReplayGainTags _replayGainTags = const ReplayGainTags();

  ReplayGainTags get replayGainTags => _replayGainTags;
  ReplayGainPreferences get replayGain => _replayGain;

  final _eventBoundary = PlaybackEventBoundary();
  BassPlaybackEvent? _lastEvent;
  BassFormatSnapshot? _sourceFormat;
  int get sessionId => _eventBoundary.stamp.session;
  BassPlaybackEvent? get lastEvent => _lastEvent;
  BassFormatSnapshot? get sourceFormat => _sourceFormat;
  bool _deviceInterrupted = false;

  /// Called only after a filesystem rename was committed and verified. The
  /// current decoder keeps its handle/position and unrelated opens keep their
  /// generation. Only future same-source reopen operations use the new path.
  bool relinkLocalPath(String oldPath, String newPath) {
    if (_freed || _fstream == null) return false;
    final next = relinkedLocalPlaybackPath(
        currentPath: _fPath,
        isUrl: _sourceIsUrl,
        oldPath: oldPath,
        newPath: newPath);
    if (next == null) return false;
    _fPath = next;
    return true;
  }

  /// Explicit refresh only (not a 33 ms diagnostics poll). No private path,
  /// URL, native filename pointer or device name enters the export.
  Map<String, Object?> outputDiagnostics() {
    final appliedEq = _equalizer.appliedGains;
    return {
      'session': sessionId,
      'state': playerState.name,
      'endReason': _lastEvent?.reason?.name,
      'error': _lastEvent?.problem?.toSafeJson(),
      'source': _sourceFormat?.toJson(),
      'requestedOutput': _outputMode.preferred ? 'exclusive' : 'shared',
      'streamOutput': wasapiExclusive ? 'exclusive' : 'shared',
      'exclusiveInitialized': _wasapiInitialized,
      'deviceNumber': _diagnosticDeviceNumber,
      'deviceFormat': wasapiExclusive && _wasapiInitialized
          ? readBassWasapiFormat(_bassWasapiLib)?.toJson()
          : null,
      'mixerFormat': _streamUsesMixer && _activeMixer != null
          ? readBassChannelFormat(_bassLib, _activeMixer!)?.toJson()
          : null,
      'userVolume': _userVolumeDsp,
      'effectiveDspMultiplier': _readEffectiveVolume(),
      'replayGainRequested': _replayGain.mode.name,
      'replayGainApplied': _fstream == null
          ? null
          : _replayGainTags.appliedMode(_replayGain)?.name,
      'replayGainSource':
          _fstream == null ? null : _replayGainTags.appliedSource(_replayGain),
      'replayGainPreampDb':
          ReplayGainPreferences.sanitizeGain(_replayGain.preampDb),
      'replayGainFallbackDb':
          ReplayGainPreferences.sanitizeGain(_replayGain.fallbackGainDb),
      'replayGainEffectiveDb': _effectiveReplayGainDb,
      'peakProtection': _replayGain.preventClipping,
      'eqRequested': _eqEnabled,
      'eqAppliedBands': appliedEq.whereType<double>().length,
      'eqAvailableBands': eqAvailableBands,
      'eqUnavailableFrequencies': [
        for (var band = 0; band < eqBandCenters.length; band++)
          if (!eqAvailableBands[band]) eqBandCenters[band],
      ],
      'eqImplementation': _equalizer.implementation,
      'eqRequestedGainsDb': _eqEnabled ? eqGains : null,
      'eqGainsDb': !_equalizer.active ? null : appliedEq,
      'eqSettingsApplied': !_eqEnabled ||
          List.generate(_eqGains.length, (index) => index).every((index) =>
              appliedEq[index] == _eqGains[index] ||
              (!eqAvailableBands[index] && _eqGains[index] == 0)),
      'playbackRate': _playbackRate,
      'playbackPitch': _playbackPitch,
      'pitchAvailable': supportsPlaybackPitch,
      'tempoAvailable': supportsPlaybackRate,
      'physicalOutputDrained': null,
      'bitPerfectVerified': false,
      'gaplessOutputVerified': false,
      'transitionRequested': _transitions.mode.name,
      'continuousMixerActive': _streamUsesMixer && _transitions.enabled,
      'nextSourcePrepared': _preparedSource != null,
      'silenceSkippingRequested': _silenceSkipping.enabled,
      'silenceStart': _silenceBounds?.start,
      'silenceEnd': _silenceBounds?.end,
    };
  }

  int? get _diagnosticDeviceNumber {
    final value = wasapiExclusive && _wasapiInitialized
        ? _bassWasapiLib.lookupFunction<ffi.Uint32 Function(), int Function()>(
            'BASS_WASAPI_GetDevice')()
        : _fstream == null
            ? null
            : _bassChannelGetDevice(_sharedMixer ?? _fstream!);
    return value == _bassErrorValue ? null : value;
  }

  double? get _effectiveReplayGainDb {
    if (_userVolumeDsp <= 0 ||
        _replayGainTags.requestedGainDb(_replayGain) == null) {
      return null;
    }
    final native = _readEffectiveVolume();
    if (native == null || native <= 0) return null;
    return 20 * math.log(native / _userVolumeDsp) / math.ln10;
  }

  final _outputMode = WasapiOutputMode();
  OutputPlaybackIntent? _outputPlaybackIntent;

  /// Current decoder/output mode. Configure this before loading a source;
  /// live changes go through the transactional [useExclusiveMode] method.
  bool get wasapiExclusive => _outputMode.active;
  set wasapiExclusive(bool value) {
    _outputMode.selectBeforePlayback(value);
    if (!value) {
      _disposeExclusiveOutput();
      return;
    }

    // A persisted exclusive preference is applied while PlaybackService is
    // constructed, before a song click can be dispatched. Prewarming the
    // silent persistent mixer here keeps the expensive device acquisition off
    // every song-selection frame. A transient device error is retried by
    // start(); it must not make the whole player unavailable at startup.
    try {
      _ensureExclusiveOutput(start: true);
    } catch (error, trace) {
      LOGGER.w('[wasapi prewarm] $error', stackTrace: trace);
    }
  }

  Timer? _positionUpdater;
  final _positionStreamController =
      StreamController<({PlaybackStamp stamp, double position})>.broadcast();
  final _playerStateStreamController =
      StreamController<BassPlaybackEvent>.broadcast();
  final _spectrumStreamController = StreamController<List<double>>.broadcast();
  final _frequencySpectrumStreamController =
      StreamController<List<double>>.broadcast();
  final _spectrumAnalysis = SpectrumAnalysis();
  late final List<double> _spectrumLevels = _spectrumAnalysis.tones;
  late final List<double> _frequencySpectrumLevels =
      _spectrumAnalysis.frequencies;
  final ffi.Pointer<ffi.Float> _fftBuffer =
      ffi.malloc.allocate<ffi.Float>(_fftValueCount * ffi.sizeOf<ffi.Float>());
  final ffi.Pointer<ffi.Float> _frequencyBuffer =
      ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
  bool _freed = false;
  final List<int> _loadedPlugins = [];
  Future<void>? _freeFuture;
  int _sourceGeneration = 0;
  final Set<_PendingBassUrlOpen> _pendingUrlOpens = {};
  final Set<_PendingBassFileOpen> _pendingFileOpens = {};
  final BassFileOpenGate _fileOpenGate = BassFileOpenGate();
  // BASS_CONFIG_NET_PROXY is process-wide. Keep proxy selection and native URL
  // creation together, including across separate BassPlayer instances.
  static final BassUrlOpenGate _urlOpenGate = BassUrlOpenGate();

  /// audio's length in seconds
  double get length => _fstream == null
      ? 1.0
      : _segmentLength ??
          _bass.BASS_ChannelBytes2Seconds(_fstream!,
              _bass.BASS_ChannelGetLength(_fstream!, BASS.BASS_POS_BYTE));

  /// current position in seconds
  double get position {
    final event = _lastEvent;
    if (event != null && event.completed && _eventBoundary.accepts(event.stamp))
      return naturalEndPosition;
    return _readPosition(decoding: false) ?? 0.0;
  }

  double? _readPosition({required bool decoding}) {
    final stream = _fstream;
    if (stream == null) return null;
    if (!decoding) {
      final remaining = _sharedDrainRemainingSeconds;
      if (remaining != null) {
        return math.max(0.0, naturalEndPosition - remaining * _playbackRate);
      }
    }
    // BASS_POS_DECODE bypasses the tempo/output playback buffer. Only the UI
    // clock uses mixer compensation; a stopped channel is diagnosed against
    // the decoder clock, including when the tempo wrapper is playing at 1x.
    const positionDecode = 0x10000000;
    final bytes = !decoding &&
            _streamUsesMixer &&
            _activeMixer != null &&
            _mix!.getChannelMixer(stream) != 0
        ? _mix!.getChannelPosition(stream, BASS.BASS_POS_BYTE)
        : _bass.BASS_ChannelGetPosition(
            stream, BASS.BASS_POS_BYTE | (decoding ? positionDecode : 0));
    if (bytes == _bassPositionErrorValue) return null;
    final absolute = _bass.BASS_ChannelBytes2Seconds(stream, bytes);
    if (!absolute.isFinite || absolute < 0) return null;
    return _segment?.relativePosition(absolute, length) ?? absolute;
  }

  double? get _sharedDrainRemainingSeconds {
    final drain = _sharedCompletionDrain;
    final mixer = _sharedMixer;
    if (drain == null ||
        mixer == null ||
        !_eventBoundary.accepts(drain.stamp)) {
      return null;
    }
    final played = _bass.BASS_ChannelGetPosition(mixer, BASS.BASS_POS_BYTE);
    if (played < 0 || played == _bassPositionErrorValue) return null;
    final seconds = _bass.BASS_ChannelBytes2Seconds(
        mixer, math.max(0, drain.endByte - played));
    return seconds.isFinite && seconds >= 0 ? seconds : null;
  }

  PlayerState get playerState {
    final state = _nativePlayerState;
    return state == PlayerState.stopped &&
            (_sharedDrainRemainingSeconds ?? 0) > 0
        ? PlayerState.playing
        : state;
  }

  PlayerState get _nativePlayerState {
    _stateNativeError = 0;
    if (_fstream == null) {
      return PlayerState.unknown;
    }
    if (_deviceInterrupted) return PlayerState.pausedDevice;

    final active = _streamUsesMixer &&
            _activeMixer != null &&
            _mix!.getChannelMixer(_fstream!) != 0
        ? _mix!.channelIsActive(_fstream!)
        : _bass.BASS_ChannelIsActive(_fstream!);
    // Output diagnostics below also call BASS; preserve the source error first.
    _stateNativeError = _bass.BASS_ErrorGetCode();
    if (!_decodingOfflineMixer && !wasapiExclusive && _sharedMixer != null) {
      final output = _bass.BASS_ChannelIsActive(_sharedMixer!);
      if (output == BASS.BASS_ACTIVE_PAUSED) return PlayerState.paused;
      if (output == BASS.BASS_ACTIVE_PAUSED_DEVICE ||
          output == BASS.BASS_ACTIVE_STOPPED) {
        return PlayerState.pausedDevice;
      }
    }
    switch (active) {
      case BASS.BASS_ACTIVE_STOPPED:
        return PlayerState.stopped;
      case BASS.BASS_ACTIVE_PLAYING:
      case BASS.BASS_ACTIVE_STALLED:
        if (wasapiExclusive &&
            _bassWasapi.BASS_WASAPI_IsStarted() != BASS.TRUE) {
          return PlayerState.pausedDevice;
        }
        return active == BASS.BASS_ACTIVE_STALLED
            ? PlayerState.stalled
            : PlayerState.playing;
      case BASS.BASS_ACTIVE_PAUSED:
        return PlayerState.paused;
      case BASS.BASS_ACTIVE_PAUSED_DEVICE:
        return PlayerState.pausedDevice;
      default:
        return PlayerState.unknown;
    }
  }

  /// User volume stays independent of the current song's ReplayGain tags.
  double get volumeDsp => _fstream == null ? 0 : _userVolumeDsp;

  /// Composed native DSP/output multiplier, useful for output diagnostics.
  double get effectiveVolumeDsp {
    return _readEffectiveVolume() ?? 0;
  }

  double? _readEffectiveVolume() {
    if (_fstream == null || _freed) return null;

    final volDsp = ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
    try {
      final read = _bass.BASS_ChannelGetAttribute(
        _fstream!,
        BASS.BASS_ATTRIB_VOLDSP,
        volDsp,
      );
      if (read == 0 || !volDsp.value.isFinite) return null;
      final dsp = volDsp.value;
      final output = _bass.BASS_ChannelGetAttribute(
        _fstream!,
        BassPlaybackVolume.playbackAttribute,
        volDsp,
      );
      if (output == 0 || !volDsp.value.isFinite) return null;
      final sourceGain = dsp * volDsp.value;
      if (!_hasSharedMuteGate) return sourceGain;
      final gate = _bass.BASS_ChannelGetAttribute(
          _sharedMixer!, BassPlaybackVolume.playbackAttribute, volDsp);
      return gate != 0 && volDsp.value.isFinite
          ? sourceGain * volDsp.value
          : null;
    } finally {
      ffi.malloc.free(volDsp);
    }
  }

  /// Normal playback updates every 33ms. Successful seeks additionally publish
  /// the actual native position immediately, including while paused.
  // Keep these broadcast views stable across widget rebuilds. Recreating a
  // where/map stream makes progress and lyric consumers detach/re-attach even
  // when the player is unchanged. The predicate still reads the live boundary
  // when each queued event is delivered.
  late final Stream<double> positionStream = _eventBoundary
      .currentEvents(_positionStreamController.stream, (event) => event.stamp)
      .map((event) => event.position);

  late final Stream<PlayerState> playerStateStream =
      playbackEvents.map((event) => event.state);

  late final Stream<BassPlaybackEvent> playbackEvents =
      _eventBoundary.currentEvents(
          _playerStateStreamController.stream, (event) => event.stamp);

  void _publishPosition() => _positionStreamController
      .add((stamp: _eventBoundary.stamp, position: position));

  void _publishState(
    PlayerState state, {
    PlaybackEndReason? reason,
    PlaybackProblem? problem,
  }) {
    final event = BassPlaybackEvent(_eventBoundary.stamp, state,
        reason: reason, problem: problem);
    _lastEvent = event;
    _playerStateStreamController.add(event);
  }

  Stream<List<double>> get spectrumStream => _spectrumStreamController.stream;

  Stream<List<double>> get frequencySpectrumStream =>
      _frequencySpectrumStreamController.stream;

  List<double> get spectrumLevels => List.unmodifiable(_spectrumLevels);

  List<double> get frequencySpectrumLevels =>
      List.unmodifiable(_frequencySpectrumLevels);

  /// A passive snapshot for background motion. Only an existing frequency
  /// spectrum listener can demand FFT work; this getter makes no native call.
  double get lowFrequencyLevel => !_freed &&
          _lastEvent?.state == PlayerState.playing &&
          _frequencySpectrumStreamController.hasListener
      ? _spectrumAnalysis.lowFrequencyLevel
      : 0;

  Timer _getPositionUpdater() {
    final stamp = _eventBoundary.stamp;
    var lastObserved = playerState;
    final initialDevice = !wasapiExclusive && _fstream != null
        ? _bassChannelGetDevice(_sharedMixer ?? _fstream!)
        : null;
    return Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        if (_freed || !_eventBoundary.accepts(stamp)) {
          timer.cancel();
          return;
        }
        _retireFinishedTransitionTail();
        final changedDevice = initialDevice != null &&
            _fstream != null &&
            _bassChannelGetDevice(_sharedMixer ?? _fstream!) != initialDevice;
        final observed =
            changedDevice ? PlayerState.pausedDevice : _nativePlayerState;
        // Capture the source error before checking staged positions or buffers.
        final nativeError = changedDevice ? 0 : _stateNativeError;
        final prepared = _preparedSource;
        var awaitingAudibleHandoff = false;
        var preparedClockUnavailable = false;
        if (prepared != null && !_transitionAnnounced) {
          final audible =
              _mix!.getChannelPosition(prepared.handle, BASS.BASS_POS_BYTE);
          preparedClockUnavailable =
              audible < 0 || audible == _bassPositionErrorValue;
          if (!preparedClockUnavailable &&
              audible > 0 &&
              nativeError != BASS.BASS_ERROR_HANDLE &&
              (observed == PlayerState.playing ||
                  observed == PlayerState.stopped ||
                  observed == PlayerState.stalled)) {
            _transitionAnnounced = true;
            _publishState(PlayerState.completed,
                reason: PlaybackEndReason.naturalEnd);
            return;
          }
          awaitingAudibleHandoff =
              _mix!.getChannelMixer(prepared.handle) == _activeMixer;
        }
        if ((prepared == null || preparedClockUnavailable) &&
            observed == PlayerState.stopped &&
            nativeError != BASS.BASS_ERROR_HANDLE) {
          if (_waitForSharedCompletionDrain(stamp)) {
            _publishPosition();
            return;
          }
          if (preparedClockUnavailable) {
            // A still-attached source does not prove that its playback clock
            // works. After the predecessor drains, retire it and use the
            // ordinary open path rather than waiting indefinitely.
            cancelPreparedSource();
            awaitingAudibleHandoff = false;
          }
        }
        if (awaitingAudibleHandoff &&
            observed == PlayerState.stopped &&
            nativeError != BASS.BASS_ERROR_HANDLE) {
          _waitForSharedCompletionDrain(stamp);
        }
        _publishPosition();
        // QUEUE removes an exhausted decoder before its output buffer has
        // reached the endpoint. Keep the old metadata until the next source
        // has an audible position; this gate must also cover gapless mode.
        if (awaitingAudibleHandoff &&
            observed == PlayerState.stopped &&
            nativeError != BASS.BASS_ERROR_HANDLE) {
          return;
        }
        if (observed == PlayerState.stopped ||
            observed == PlayerState.pausedDevice) {
          _resetSpectrum();
          timer.cancel();
          if (identical(_positionUpdater, timer)) {
            _positionUpdater = null;
          }
          final reason = classifyPlaybackStop(
            validHandle: observed != PlayerState.stopped ||
                nativeError != BASS.BASS_ERROR_HANDLE,
            deviceAvailable: observed != PlayerState.pausedDevice,
            position: _boundaryPosition,
            duration: naturalEndPosition,
            segment: _segment != null,
          );
          if (!_eventBoundary.settle(stamp)) return;
          if (reason == PlaybackEndReason.naturalEnd ||
              reason == PlaybackEndReason.segmentEnd) {
            _publishState(PlayerState.completed, reason: reason);
            _publishPosition();
          } else {
            final device = reason == PlaybackEndReason.deviceUnavailable;
            // Explicit user recovery is required after an endpoint failure;
            // never silently relabel it as shared output or completed audio.
            if (device) {
              if (wasapiExclusive && _fstream != null) {
                _mix?.setChannelPaused(_fstream!, true);
              } else if (_fstream != null) {
                _bass.BASS_ChannelPause(_sharedMixer ?? _fstream!);
              }
              _deviceInterrupted = true;
            }
            _publishState(
                device ? PlayerState.pausedDevice : PlayerState.stopped,
                reason: reason,
                problem: PlaybackProblem(
                  device
                      ? PlaybackProblemKind.deviceDisconnected
                      : reason == PlaybackEndReason.invalidHandle
                          ? PlaybackProblemKind.invalidHandle
                          : PlaybackProblemKind.unexpectedStop,
                  device
                      ? changedDevice
                          ? '默认输出设备已变化，播放已暂停。'
                          : '音频设备已暂停或断开。'
                      : '音频在到达可确认的结束位置前停止。',
                  nativeCode: nativeError == 0 ? null : nativeError,
                ));
          }
          return;
        }

        if (observed != lastObserved) {
          lastObserved = observed;
          _publishState(observed);
        }

        if (_spectrumStreamController.hasListener ||
            _frequencySpectrumStreamController.hasListener) {
          _updateSpectrum();
          if (_spectrumStreamController.hasListener) {
            _spectrumStreamController.add(List.unmodifiable(_spectrumLevels));
          }
          if (_frequencySpectrumStreamController.hasListener) {
            _frequencySpectrumStreamController.add(
              List.unmodifiable(_frequencySpectrumLevels),
            );
          }
        }
      },
    );
  }

  // A NONSTOP playable mixer can retain the predecessor's final output after
  // its decoder stopped, even when no successor was prepared. Capture a finite
  // decode boundary once, then wait on the existing observer for playback to
  // drain to it. NoSound and exclusive output have no matching playback cursor.
  bool _waitForSharedCompletionDrain(PlaybackStamp stamp) {
    final mixer = _sharedMixer;
    if (_offlineOutput ||
        wasapiExclusive ||
        !_streamUsesMixer ||
        mixer == null) {
      return false;
    }
    final previous = _sharedCompletionDrain;
    if (previous == null || !_eventBoundary.accepts(previous.stamp)) {
      const decodePosition = 0x10000000;
      final endByte = _bass.BASS_ChannelGetPosition(
          mixer, BASS.BASS_POS_BYTE | decodePosition);
      if (endByte < 0 || endByte == _bassPositionErrorValue) return false;
      _sharedCompletionDrain = (stamp: stamp, endByte: endByte);
    }
    return (_sharedDrainRemainingSeconds ?? 0) > 0;
  }

  /// BASS_SetConfig is outside the generated binding subset.
  late final int Function(int option, int value) _bassSetConfig =
      _bassLib.lookupFunction<ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)>('BASS_SetConfig');

  late final int Function(int channel, int lock) _bassChannelLock =
      _bassLib.lookupFunction<ffi.Int32 Function(ffi.Uint32, ffi.Int32),
          int Function(int, int)>('BASS_ChannelLock');

  /// bass.h: BASS_CONFIG_DEV_DEFAULT
  static const int _bassConfigDevDefault = 36;

  late final int Function(
    int handle,
    ffi.Pointer<ffi.Void> buffer,
    int length,
  ) _bassChannelGetData = _bassLib.lookupFunction<
      ffi.Uint32 Function(
        ffi.Uint32,
        ffi.Pointer<ffi.Void>,
        ffi.Uint32,
      ),
      int Function(
        int,
        ffi.Pointer<ffi.Void>,
        int,
      )>('BASS_ChannelGetData');

  late final int Function() _bassGetDevice = _bassLib
      .lookupFunction<ffi.Uint32 Function(), int Function()>('BASS_GetDevice');

  late final int Function(int) _bassChannelGetDevice = _bassLib.lookupFunction<
      ffi.Uint32 Function(ffi.Uint32),
      int Function(int)>('BASS_ChannelGetDevice');

  late final int Function(ffi.Pointer<ffi.Void>)? _bassStreamCancel =
      _lookupStreamCancel();

  int Function(ffi.Pointer<ffi.Void>)? _lookupStreamCancel() {
    try {
      return _bassLib.lookupFunction<ffi.Int32 Function(ffi.Pointer<ffi.Void>),
          int Function(ffi.Pointer<ffi.Void>)>('BASS_StreamCancel');
    } on ArgumentError {
      return null;
    }
  }

  late final int Function(
    ffi.Pointer<ffi.Void> buffer,
    int length,
  ) _bassWasapiGetData = _bassWasapiLib.lookupFunction<
      ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, int)>('BASS_WASAPI_GetData');

  void _updateSpectrum() {
    if (_fstream == null || playerState != PlayerState.playing) {
      _resetSpectrum(emit: false);
      return;
    }

    const flags = _bassDataFft4096 | _bassDataFftRemoveDc;
    final result = wasapiExclusive
        ? _bassWasapiGetData(_fftBuffer.cast(), flags)
        : _bassChannelGetData(
            _sharedMixer ?? _fstream!, _fftBuffer.cast(), flags);
    if (result == _bassErrorValue) {
      _decaySpectrum();
      return;
    }

    var sampleRate = 48000.0;
    if (!wasapiExclusive &&
        _bass.BASS_ChannelGetAttribute(
              _sharedMixer ?? _fstream!,
              _bassAttribFreq,
              _frequencyBuffer,
            ) ==
            BASS.TRUE) {
      sampleRate = _frequencyBuffer.value;
    }
    if (!sampleRate.isFinite || sampleRate <= 0) sampleRate = 48000.0;

    final fft = _fftBuffer.asTypedList(_fftValueCount);
    // Shared-mode FFT is taken before the output VOL attribute. Preserve its
    // previous audible-volume response; exclusive WASAPI data already includes
    // the mixer's volume and must not be multiplied a second time.
    if (!wasapiExclusive &&
        _bass.BASS_ChannelGetAttribute(_sharedMixer ?? _fstream!,
                BassPlaybackVolume.playbackAttribute, _frequencyBuffer) ==
            BASS.TRUE) {
      final gain = _frequencyBuffer.value;
      if (gain.isFinite && gain >= 0 && gain != 1) {
        for (var index = 0; index < fft.length; index++) {
          fft[index] *= gain;
        }
      }
    }
    _spectrumAnalysis.update(fft, sampleRate,
        frequencyDemand: _frequencySpectrumStreamController.hasListener,
        toneDemand: _spectrumStreamController.hasListener);
  }

  void _decaySpectrum() {
    for (var i = 0; i < _spectrumLevels.length; i++) {
      _spectrumLevels[i] *= 0.82;
    }
    for (var i = 0; i < _frequencySpectrumLevels.length; i++) {
      _frequencySpectrumLevels[i] *= 0.82;
    }
  }

  void _resetSpectrum({bool emit = true}) {
    for (var i = 0; i < _spectrumLevels.length; i++) {
      _spectrumLevels[i] = 0.0;
    }
    for (var i = 0; i < _frequencySpectrumLevels.length; i++) {
      _frequencySpectrumLevels[i] = 0.0;
    }
    if (emit &&
        !_spectrumStreamController.isClosed &&
        _spectrumStreamController.hasListener) {
      _spectrumStreamController.add(List<double>.unmodifiable(_spectrumLevels));
    }
    if (emit &&
        !_frequencySpectrumStreamController.isClosed &&
        _frequencySpectrumStreamController.hasListener) {
      _frequencySpectrumStreamController.add(
        List.unmodifiable(_frequencySpectrumLevels),
      );
    }
  }

  static const List<double> eqBandCenters = BassEqualizer.centers;
  static const double eqMaxGainDb = BassEqualizer.maxGainDb;

  bool _eqEnabled = false;
  bool get eqEnabled => _eqEnabled;

  final List<double> _eqGains = List.filled(eqBandCenters.length, 0.0);
  List<double> get eqGains => List.unmodifiable(_eqGains);

  late BassEqualizer _equalizer =
      BassEqualizer.native(_bassLib, peakingAvailable: _tempo != null);
  bool get eqActive => _equalizer.active;
  List<bool> get eqAvailableBands => _equalizer.availableBands;

  bool _applyEqToStream() {
    if (!_eqEnabled || _fstream == null) return true;
    final applied = _equalizer.apply(_fstream!, _eqGains);
    if (!applied) {
      LOGGER.w("[eq] apply failed: ${_bass.BASS_ErrorGetCode()}");
    }
    return applied;
  }

  void _removeEqFromStream() {
    _equalizer.remove();
  }

  bool setEqEnabled(bool enabled) {
    if (enabled == _eqEnabled) return true;
    cancelPreparedSource();
    _retireTransitionTail();
    if (enabled) {
      _eqEnabled = true;
      if (_fstream != null && !_applyEqToStream()) {
        _eqEnabled = false;
        return false;
      }
      return true;
    }

    _removeEqFromStream();
    _eqEnabled = false;
    return true;
  }

  void setEqBandGain(int band, double gain) {
    if (band < 0 || band >= eqBandCenters.length) return;
    _eqGains[band] =
        gain.isFinite ? gain.clamp(-eqMaxGainDb, eqMaxGainDb).toDouble() : 0.0;
    // Saving disabled/unavailable EQ cannot change this output or its fade.
    // Compare successful native parameters, so a failed edit remains retryable.
    if (!_eqEnabled ||
        !_equalizer.availableBands[band] ||
        _equalizer.appliedGains[band] == _eqGains[band]) return;
    cancelPreparedSource();
    _retireTransitionTail();
    _equalizer.setBandGain(band, _eqGains[band]);
  }

  void setEqGains(List<double> gains) {
    for (var band = 0; band < eqBandCenters.length; band++) {
      final gain = band < gains.length ? gains[band] : 0.0;
      _eqGains[band] = gain.isFinite
          ? gain.clamp(-eqMaxGainDb, eqMaxGainDb).toDouble()
          : 0.0;
    }
    if (!_eqEnabled) return;
    final available = _equalizer.availableBands;
    final applied = _equalizer.appliedGains;
    if (Iterable<int>.generate(eqBandCenters.length)
        .every((band) => !available[band] || applied[band] == _eqGains[band]))
      return;
    cancelPreparedSource();
    _retireTransitionTail();

    for (var band = 0; band < eqBandCenters.length; band++) {
      _equalizer.setBandGain(band, _eqGains[band]);
    }
  }

  void _bassInit() {
    _bassSetConfig(_bassConfigDevDefault, BASS.TRUE);

    if (_bass.BASS_Init(
            _offlineOutput ? 0 : -1, 48000, 0, ffi.nullptr, ffi.nullptr) ==
        0) {
      final code = _bass.BASS_ErrorGetCode();
      if (code != BASS.BASS_ERROR_ALREADY) {
        throw PlaybackProblem(
            code == BASS.BASS_ERROR_BUSY
                ? PlaybackProblemKind.exclusiveDenied
                : PlaybackProblemKind.deviceInitialization,
            '无法初始化音频设备。',
            nativeCode: code);
      }
    }
    if (_bufferedOfflineOutput) {
      // An already initialized device need not become this thread's current
      // device. Explicitly pin the QA path even when BASS_Init reports ALREADY.
      final selectDevice = _bassLib.lookupFunction<
          ffi.Int32 Function(ffi.Uint32), int Function(int)>('BASS_SetDevice');
      final currentDevice =
          _bassLib.lookupFunction<ffi.Uint32 Function(), int Function()>(
              'BASS_GetDevice');
      if (selectDevice(0) == 0 || currentDevice() != 0) {
        throw StateError('Buffered offline output requires NoSound device 0');
      }
    }
  }

  void _startDevice() {
    if (_bufferedOfflineOutput) _bassInit();
    final error = startBassDeviceOnce(
        start: _bass.BASS_Start,
        errorCode: _bass.BASS_ErrorGetCode,
        initialize: _bassInit);
    if (error != 0) {
      throw PlaybackProblem(
          PlaybackProblemKind.deviceInitialization, '音频设备无法恢复。',
          nativeCode: error);
    }
  }

  /// load bass.dll from the exe's path\\BASS
  /// ensure that there's bass.dll at path of .exe\\BASS
  /// leave the device's output freq as it is
  BassPlayer(
      {String? runtimeDirectory,
      bool offlineOutput = false,
      bool bufferedOfflineOutput = false})
      : _offlineOutput = offlineOutput,
        _bufferedOfflineOutput = bufferedOfflineOutput {
    // This native QA mode exercises the real playable mixer buffer while
    // BASS_Init remains pinned to NoSound device 0, never a physical endpoint.
    if (bufferedOfflineOutput && !offlineOutput) {
      throw ArgumentError('bufferedOfflineOutput requires offlineOutput');
    }
    final directory = runtimeDirectory ??
        path.join(path.dirname(Platform.resolvedExecutable), 'BASS');
    _bassLibraryPath = path.join(directory, 'bass.dll');
    _bassLib = ffi.DynamicLibrary.open(_bassLibraryPath);
    _bass = BASS.Bass(_bassLib);
    _playbackVolume = BassPlaybackVolume.native(_bassLib);

    final bassWasapiLibPath = path.join(directory, 'basswasapi.dll');
    _bassWasapiLib = ffi.DynamicLibrary.open(bassWasapiLibPath);
    _bassWasapi = BASS.BassWasapi(_bassWasapiLib);

    // BASSmix owns the persistent decoder mixer used by WASAPI exclusive
    // output. Keep shared playback available when an unpacked/incomplete
    // development tree omits the add-on; selecting exclusive mode will report
    // the actionable error instead of failing BassPlayer construction.
    try {
      _mix = BassMixLibrary.open(path.join(directory, 'bassmix.dll'));
    } catch (error, trace) {
      exclusiveOutputUnavailableReason =
          '独占输出组件不可用，请使用包含 BASS/bassmix.dll 的完整安装包';
      LOGGER.w('[bass mix] $error', stackTrace: trace);
    }

    // A missing optional extension must not prevent ordinary 1x playback.
    // The release assembler supplies and verifies the official x64 bytes.
    try {
      _tempo = BassTempoLibrary.open(path.join(directory, 'bass_fx.dll'));
    } catch (error, trace) {
      tempoUnavailableReason = '倍速组件不可用，请使用包含 BASS/bass_fx.dll 的完整安装包';
      LOGGER.w('[bass tempo] $error', stackTrace: trace);
    }

    // load add-ons to avoid using os codec or support more format
    for (final plugin in BASS_PLUGINS) {
      final pluginPath = path.join(directory, path.basename(plugin));
      final pluginPathP = pluginPath.toNativeUtf16() as ffi.Pointer<ffi.Char>;
      late final int hplugin;
      try {
        hplugin = _bass.BASS_PluginLoad(pluginPathP, BASS.BASS_UNICODE);
      } finally {
        ffi.malloc.free(pluginPathP);
      }

      if (hplugin == 0) {
        switch (_bass.BASS_ErrorGetCode()) {
          case BASS.BASS_ERROR_FILEOPEN:
            throw const FormatException("The file could not be opened.");
          case BASS.BASS_ERROR_FILEFORM:
            throw const FormatException("The file is not a plugin.");
          case BASS.BASS_ERROR_VERSION:
            throw const FormatException(
                "The plugin requires a different BASS version.");
          case BASS.BASS_ERROR_ALREADY:
            throw const FormatException("The plugin is already loaded.");
        }
      } else {
        _loadedPlugins.add(hplugin);
      }
    }

    try {
      _bassInit();
    } catch (err) {
      LOGGER.e("[bass init] $err");
      if (_bufferedOfflineOutput) rethrow;
    }
  }

  /// true: 操作成功；false: 操作失败或被后续操作取消。
  Future<bool> useExclusiveMode(bool exclusive) async {
    if (_freed) return false;
    if (_offlineOutput && exclusive) return false;
    if (exclusive == wasapiExclusive) return true;

    final sourcePath = _fPath;
    final sourceIsUrl = _sourceIsUrl;
    final sourceSegment = _segment;
    final previousMode = wasapiExclusive;
    var lastPos = position;
    var wasPlaying = playerState.keepsPlaybackIntent;
    cancelPendingSource();
    final generation = _sourceGeneration;
    if (sourcePath == null) {
      _outputMode.selectBeforePlayback(exclusive);
      try {
        if (exclusive) {
          _ensureExclusiveOutput(start: true);
        } else {
          _disposeExclusiveOutput();
        }
        _outputMode.confirmActive();
        return true;
      } catch (_) {
        _outputMode.selectBeforePlayback(previousMode);
        if (!previousMode) _disposeExclusiveOutput();
        rethrow;
      }
    }

    final transport = OutputPlaybackIntent();
    _outputPlaybackIntent = transport;
    try {
      // Keep the old stream and mode intact until the replacement is open.
      final applied = await _setSource(
        sourcePath,
        isUrl: sourceIsUrl,
        segment: sourceSegment,
        exclusive: exclusive,
        generation: generation,
        onBeforeCommit: () {
          lastPos = position;
          wasPlaying = playerState.keepsPlaybackIntent;
        },
      );
      if (!applied || !_isCurrentSource(generation)) return false;

      if (exclusive) _bassWasapiInit();
      if (lastPos > 0 || _silenceBounds != null) {
        try {
          seek(lastPos);
        } catch (err, trace) {
          LOGGER.w('[use exclusive mode] 无法恢复播放位置：$err', stackTrace: trace);
          showAppNotice(ui('输出模式已切换，但暂时无法恢复原播放位置'), kind: AppNoticeKind.error);
        }
      }
      if (transport.resolve(wasPlaying)) {
        _resumeCurrentOutput();
      } else {
        _publishState(playerState);
      }
      _outputMode.confirmActive();
      return true;
    } catch (err, trace) {
      if (!_isCurrentSource(generation)) return false;
      LOGGER.e('[use exclusive mode] $err', stackTrace: trace);
      // Opening succeeded but initializing the replacement output may fail.
      // Restore the previous mode/position/play state instead of leaving a
      // failed exclusive decoder behind and silently stopping the old song.
      if (wasapiExclusive != previousMode) {
        try {
          final restored = await _setSource(
              sourceIsUrl ? sourcePath : _fPath ?? sourcePath,
              isUrl: sourceIsUrl,
              segment: sourceSegment,
              exclusive: previousMode,
              generation: generation);
          if (!restored || !_isCurrentSource(generation)) return false;
          if (lastPos > 0 || _silenceBounds != null) seek(lastPos);
          // Reopening the original URL can take time. A pause/play received
          // during that await must win over the pre-failure playback snapshot.
          if (transport.resolve(wasPlaying)) _resumeCurrentOutput();
          _publishState(playerState);
          showAppNotice(bassOutputModeFailureNotice(err, restored: true),
              kind: AppNoticeKind.error);
        } catch (restoreError, restoreTrace) {
          if (!_isCurrentSource(generation)) return false;
          LOGGER.e('[restore output mode] $restoreError',
              stackTrace: restoreTrace);
          showAppNotice(ui('音频设备不可用，原模式也未能恢复；请检查设备后重试'),
              kind: AppNoticeKind.error);
          _publishState(playerState);
        }
      } else {
        showAppNotice(bassOutputModeFailureNotice(err, restored: false),
            kind: AppNoticeKind.error);
      }
      _publishState(playerState,
          problem: err is PlaybackProblem
              ? err
              : const PlaybackProblem(
                  PlaybackProblemKind.deviceInitialization, '音频输出切换失败。'));
      return false;
    } finally {
      if (identical(_outputPlaybackIntent, transport)) {
        _outputPlaybackIntent = null;
      }
    }
  }

  /// Invalidates in-flight opens without disturbing the current stream.
  /// Call this as soon as a newer request begins, including its URL-resolution
  /// phase, rather than waiting until that newer URL has been resolved.
  void cancelPendingSource() {
    cancelPreparedSource();
    _retireTransitionTail();
    _sourceGeneration += 1;
    for (final scan in _silenceScans) scan.cancel();
    _urlOpenGate.cancelStaleWaiters();
    // Discard events already queued by the previous explicit source request.
    // The retained stream may keep playing while another file opens, using a
    // fresh observation stamp; opening cancellation remains independently
    // guarded by _sourceGeneration.
    _eventBoundary.command();
    _positionUpdater = rearmBassPositionUpdater(_positionUpdater,
        freed: _freed, create: _getPositionUpdater);
    if (_pendingUrlOpens.isEmpty) return;

    final cancelStream = _bassStreamCancel;
    if (cancelStream == null) return;
    for (final request in _pendingUrlOpens) {
      request.cancel(cancelStream);
    }
  }

  /// Waits until a cancelled native file open has returned and any stale
  /// handle has been freed, so Windows can safely delete that exact file.
  Future<void> waitForPendingFileOpen(String filePath) async {
    final matching = [
      for (final request in _pendingFileOpens)
        if (path.equals(request.path, filePath)) request.finished.future,
    ];
    if (matching.isNotEmpty) await Future.wait(matching);
  }

  /// Only one future local source is held. No extra HTTP resolution, output
  /// endpoint or periodic timer is created by preparation.
  Future<bool> prepareNextSource(String source,
      {required Object identity,
      required double rate,
      required double pitch,
      bool allowCrossfade = true,
      required bool Function() stillCurrent}) async {
    if (!supportsTransitions ||
        _silenceSkipping.enabled ||
        _silenceBounds != null ||
        !_transitions.enabled ||
        !_streamUsesMixer ||
        _fstream == null ||
        _sourceIsUrl ||
        _segment != null ||
        _activeMixer == null ||
        playerState != PlayerState.playing ||
        _transitionTail != null ||
        !stillCurrent()) {
      return false;
    }
    if (_preparedSource?.identity == identity) return true;
    cancelPreparedSource();
    final preparation = _preparationGeneration;
    final sourceGeneration = _sourceGeneration;
    final currentHandle = _fstream!;
    final mixer = _activeMixer!;
    bool current() =>
        !_freed &&
        preparation == _preparationGeneration &&
        sourceGeneration == _sourceGeneration &&
        currentHandle == _fstream &&
        mixer == _activeMixer &&
        _transitions.enabled &&
        stillCurrent();
    var acquired = false;
    var handle = 0;
    _PendingBassFileOpen? pending;
    BassEqualizer? equalizer;
    try {
      PlaybackRate.validate(rate);
      PlaybackPitch.validate(pitch);
      acquired = await _fileOpenGate.acquire(current);
      if (!acquired || !current()) return false;
      pending = _PendingBassFileOpen(source);
      _pendingFileOpens.add(pending);
      final result = await _openBassFileInBackground(
          _bassLibraryPath,
          source,
          BASS.BASS_UNICODE |
              BASS.BASS_SAMPLE_FLOAT |
              BASS.BASS_ASYNCFILE |
              BASS.BASS_STREAM_DECODE |
              0x20000,
          _bassGetDevice(),
          null);
      handle = result.handle;
      if (!current() || handle == 0) return false;
      final format = readBassChannelFormat(_bassLib, handle);
      if (_tempo != null) {
        final wrapped = _tempo!.createStream(handle, decodingOutput: true);
        if (wrapped == 0) return false;
        handle = wrapped;
        _setNativeTempo(handle, rate);
        _setNativePitch(handle, pitch);
        _bass.BASS_ChannelSetAttribute(
            handle, BassTempoLibrary.preventClickAttribute, 1);
      } else if (rate != 1 || pitch != 0) {
        return false;
      }
      final duration = _bass.BASS_ChannelBytes2Seconds(
          handle, _bass.BASS_ChannelGetLength(handle, BASS.BASS_POS_BYTE));
      // Very short sources can be entirely buffered before the 33ms UI
      // hand-off. Let the existing completion path handle them safely.
      if (!duration.isFinite || duration < 0.75 || !current()) return false;
      equalizer =
          BassEqualizer.native(_bassLib, peakingAvailable: _tempo != null)
            ..sourceFormat(format?.sampleRate);
      if (_eqEnabled && !equalizer.apply(handle, _eqGains)) return false;
      final base = _playbackVolume.initialize(
          handle,
          _hasSharedMuteGate ? _sharedSourceVolume : _userVolumeDsp,
          result.replayGain,
          _replayGain);
      // bass.h BASS_ATTRIB_SRC=8: preserve music quality when a persistent
      // 48kHz mixer receives a source at another sample rate (64-point sinc).
      _bass.BASS_ChannelSetAttribute(handle, 8, 4);
      if (!current() || playerState != PlayerState.playing) return false;
      _transitionMixer ??= BassTransitionMixer(_bassLib, _mix!);
      final schedule = _transitionMixer!.schedule(
          mixer: mixer,
          current: currentHandle,
          next: handle,
          remainingSeconds: () => (length - _boundaryPosition) / _playbackRate,
          fadeSeconds: allowCrossfade &&
                  !wasapiExclusive &&
                  _transitions.mode == PlaybackTransitionMode.crossfade
              ? PlaybackTransitionPreferences.safeSeconds(
                  _transitions.crossfadeSeconds)
              : 0,
          nextDuration: duration / rate);
      if (schedule == null) return false;
      _preparedSource = _PreparedBassSource(
          identity: identity,
          path: source,
          handle: handle,
          replayGain: result.replayGain,
          dspBase: base,
          format: format,
          equalizer: equalizer,
          rate: rate,
          pitch: pitch,
          schedule: schedule);
      _transitionAnnounced = false;
      handle = 0;
      equalizer = null;
      return true;
    } catch (error, trace) {
      // Preparation is optional. The regular, user-visible source-open path
      // remains responsible for reporting an actual playback failure.
      if (current()) LOGGER.w('[prepare transition] $error', stackTrace: trace);
      return false;
    } finally {
      equalizer?.forgetSource();
      if (handle != 0) {
        _mix?.removeChannel(handle);
        _bass.BASS_StreamFree(handle);
      }
      if (pending != null) {
        _pendingFileOpens.remove(pending);
        pending.complete();
      }
      if (acquired) _fileOpenGate.release();
    }
  }

  void cancelPreparedSource() => _cancelPreparedSource();

  void _cancelPreparedSource({bool restoreSharedBuffer = true}) {
    _preparationGeneration++;
    final source = _preparedSource;
    final announced = _transitionAnnounced;
    _preparedSource = null;
    _transitionAnnounced = false;
    final mixer = _activeMixer;
    final current = _fstream;
    final locked = source != null &&
        restoreSharedBuffer &&
        !_decodingOfflineMixer &&
        !wasapiExclusive &&
        mixer != null &&
        mixer == _sharedMixer &&
        current != null &&
        _bassChannelLock(mixer, 1) != 0;
    try {
      final restartAt =
          locked ? _sharedSourceRestartPosition(source, mixer, current) : null;
      if (source != null) {
        if (mixer != null && current != null) {
          _transitionMixer?.cancel(
              mixer: mixer, current: current, next: source.handle);
        }
        source.equalizer.forgetSource();
        _mix?.removeChannel(source.handle);
        _bass.BASS_StreamFree(source.handle);
      }
      if (locked && restartAt != null) {
        final reattach = _mix!.getChannelMixer(current) == 0 ||
            _mix!.channelIsActive(current) == BASS.BASS_ACTIVE_STOPPED;
        // QUEUE can retain position history for an exhausted decoder until
        // reset retires it. Re-add it explicitly before restoring playback.
        if (reattach && _mix!.getChannelMixer(current) != 0) {
          _mix!.removeChannel(current);
        }
        final attached = !reattach ||
            _mix!.addChannel(mixer, current, paused: true, noRampIn: true);
        // Removing a source/envelope does not retract already mixed PCM.
        // After withdrawing the successor, regenerate only the predecessor
        // from its heard position and flush the playable mixer's lookahead.
        // The output channel itself retains its paused/playing state.
        if (attached &&
            _transitionMixer!.clearEnvelope(current) &&
            _mix!.setChannelPosition(
                current,
                restartAt,
                BASS.BASS_POS_BYTE |
                    BassMixLibrary.positionMixerReset |
                    BassMixLibrary.channelNoRampIn)) {
          _sharedCompletionDrain = null;
        } else {
          LOGGER.w(
              '[withdraw buffered transition] BASS ${_bass.BASS_ErrorGetCode()}');
        }
        if (reattach && attached) _mix!.setChannelPaused(current, false);
      }
    } finally {
      if (locked) _bassChannelLock(mixer, 0);
    }
    if (announced) {
      // A stop target or user command can arrive after a crossfade handoff was
      // queued but before its event is delivered. It is not the old track's
      // real EOF: withdraw that event and keep observing its remaining audio.
      _eventBoundary.command(rearm: true);
      _lastEvent = null;
      _positionUpdater = rearmBassPositionUpdater(_positionUpdater,
          freed: _freed, create: _getPositionUpdater);
    }
  }

  int? _sharedSourceRestartPosition(
      _PreparedBassSource prepared, int mixer, int current) {
    if (_mix!.getChannelMixer(current) == mixer) {
      final heard = _mix!.getChannelPosition(current, BASS.BASS_POS_BYTE);
      if (heard >= 0 && heard != _bassPositionErrorValue) {
        return bassSeekPositionBytes(
            _bass, current, _bass.BASS_ChannelBytes2Seconds(current, heard));
      }
    }
    // QUEUE may have detached the exhausted decoder while its final audio is
    // still buffered. The schedule retains that predecessor's output end.
    final played = _bass.BASS_ChannelGetPosition(mixer, BASS.BASS_POS_BYTE);
    if (played < 0 || played == _bassPositionErrorValue) return null;
    final remaining = _bass.BASS_ChannelBytes2Seconds(
        mixer, math.max(0, prepared.schedule.endByte - played));
    if (!remaining.isFinite || remaining < 0 || !length.isFinite) return null;
    return bassSeekPositionBytes(_bass, current,
        (naturalEndPosition - remaining * _playbackRate).clamp(0.0, length));
  }

  /// Called only by the owner of the already-determined automatic next
  /// occurrence. The native mixer keeps running through this metadata hand-off.
  bool takePreparedSource(Object identity) {
    final next = _preparedSource;
    if (_freed ||
        next == null ||
        next.identity != identity ||
        _fstream == null ||
        _activeMixer == null) {
      return false;
    }
    final previousHandle = _fstream!;
    final previousEq = _equalizer;
    _transitionMixer?.complete(
        mixer: _activeMixer!, current: previousHandle, next: next.handle);
    _preparedSource = null;
    _preparationGeneration++;
    _transitionAnnounced = false;
    _retireTransitionTail();
    if (next.schedule.fadeSeconds > 0 &&
        _mix!.channelIsActive(previousHandle) == BASS.BASS_ACTIVE_PLAYING) {
      _transitionTail = _PreparedBassSource(
          identity: identity,
          path: _fPath!,
          handle: previousHandle,
          replayGain: _replayGainTags,
          dspBase: _volumeDspBase,
          format: _sourceFormat,
          equalizer: previousEq,
          rate: _playbackRate,
          pitch: _playbackPitch,
          schedule: next.schedule);
    } else {
      previousEq.forgetSource();
      _mix!.removeChannel(previousHandle);
      _bass.BASS_StreamFree(previousHandle);
    }
    _fstream = next.handle;
    _fPath = next.path;
    _sourceIsUrl = false;
    _segment = null;
    _segmentLength = null;
    _silenceBounds = null;
    _silenceDecoder = null;
    _replayGainTags = next.replayGain;
    _volumeDspBase = next.dspBase;
    _sourceFormat = next.format;
    _equalizer = next.equalizer;
    _playbackRate = next.rate;
    _playbackPitch = next.pitch;
    _eventBoundary.replace();
    _lastEvent = null;
    _deviceInterrupted = false;
    _positionUpdater?.cancel();
    _positionUpdater = _getPositionUpdater();
    _publishPosition();
    return true;
  }

  void _retireFinishedTransitionTail() {
    final tail = _transitionTail;
    if (tail != null &&
        _mix!.channelIsActive(tail.handle) == BASS.BASS_ACTIVE_STOPPED) {
      _retireTransitionTail();
    }
  }

  void _retireTransitionTail() {
    final tail = _transitionTail;
    _transitionTail = null;
    if (tail == null) return;
    _mix?.setChannelPaused(tail.handle, true);
    _mix?.removeChannel(tail.handle);
    tail.equalizer.forgetSource();
    _bass.BASS_StreamFree(tail.handle);
    if (_fstream != null) _transitionMixer?.clearEnvelope(_fstream!);
  }

  bool _isCurrentSource(int generation) =>
      !_freed && generation == _sourceGeneration;

  /// Opens the new source before replacing the current stream. Potentially
  /// blocking file/network opens run outside Flutter's UI isolate.
  /// Returns false when a newer request or shutdown cancels this request.
  Future<bool> setSource(String path,
      {bool isUrl = false, AudioSegment? segment}) {
    if (_freed) return Future.value(false);
    cancelPendingSource();
    return _setSource(
      path,
      isUrl: isUrl,
      segment: segment,
      exclusive: _outputMode.preferred,
      generation: _sourceGeneration,
    );
  }

  Future<bool> _setSource(
    String source, {
    required bool isUrl,
    required bool exclusive,
    required int generation,
    AudioSegment? segment,
    void Function()? onBeforeCommit,
  }) async {
    final priorSourcePath = _fPath;
    const fileFlags =
        BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT | BASS.BASS_ASYNCFILE;
    // On-demand tracks need the downloaded data retained for seek/loop.
    // BASS may still apply BLOCK itself for unknown-length/live streams.
    const urlFlags = BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT;
    var flags = isUrl ? urlFlags : fileFlags;
    if (segment != null) {
      if (isUrl) throw const FormatException('CUE 分轨仅支持本地音频文件。');
      flags |= 0x20000; // BASS_STREAM_PRESCAN: accurate MP3 source positions.
    }
    final silencePreferences = _silenceSkipping;
    final analyseSilence = silencePreferences.enabled &&
        !isUrl &&
        segment == null &&
        (_mix != null || _tempo != null);
    final useMixer =
        exclusive || ((_transitions.enabled || analyseSilence) && _mix != null);
    if (useMixer || _tempo != null) flags |= BASS.BASS_STREAM_DECODE;

    var uncommittedHandle = 0;
    var openedReplayGain = const ReplayGainTags();
    BassSilenceBounds? openedSilence;
    int? silenceDecoder;
    var uncommittedInMixer = false;
    _PendingBassUrlOpen? pending;
    _PendingBassFileOpen? pendingFile;
    var fileSlotAcquired = false;
    var urlSlotAcquired = false;
    try {
      if (isUrl) {
        if (_bassStreamCancel == null) {
          throw const FormatException(
              'BASS 运行库过旧，无法安全取消联网请求，请更新到 2.4.18 或更高版本');
        }
        urlSlotAcquired =
            await _urlOpenGate.acquire(() => _isCurrentSource(generation));
        if (!urlSlotAcquired || !_isCurrentSource(generation)) return false;
        var device = _bassGetDevice();
        if (device == _bassErrorValue) {
          _bassInit();
          device = _bassGetDevice();
        }
        if (device == _bassErrorValue) {
          throw _sourceOpenException(_bass.BASS_ErrorGetCode(), isUrl: true);
        }

        // With no DOWNLOADPROC, user is an opaque identity only. A monotonically
        // increasing non-null value avoids sharing Dart/native memory and avoids
        // accidental identity reuse while a former stream is still alive.
        pending = _PendingBassUrlOpen(_nextNetworkRequestId++);
        _pendingUrlOpens.add(pending);
        late final _BassOpenResult result;
        try {
          // Read the live choice after leaving the queue, not when the old
          // stream first began opening.
          final proxy = bassProxyForUrl(
              Uri.parse(source), AppSettings.instance.networkProxy.value);
          result = await _openBassUrlInBackground(
            _bassLibraryPath,
            source,
            flags,
            device,
            pending.requestId,
            proxy,
          );
        } finally {
          _urlOpenGate.release();
          urlSlotAcquired = false;
        }
        uncommittedHandle = result.handle;
        if (!_isCurrentSource(generation)) return false;
        if (uncommittedHandle == 0) {
          throw _sourceOpenException(result.errorCode, isUrl: true);
        }
      } else {
        fileSlotAcquired =
            await _fileOpenGate.acquire(() => _isCurrentSource(generation));
        if (!fileSlotAcquired || !_isCurrentSource(generation)) return false;

        var device = _bassGetDevice();
        if (device == _bassErrorValue) {
          _bassInit();
          device = _bassGetDevice();
        }
        if (device == _bassErrorValue) {
          throw _sourceOpenException(_bass.BASS_ErrorGetCode(), isUrl: false);
        }

        pendingFile = _PendingBassFileOpen(source);
        _pendingFileOpens.add(pendingFile);
        var result = await _openBassFileInBackground(
          _bassLibraryPath,
          source,
          flags,
          device,
          segment,
        );
        uncommittedHandle = result.handle;
        if (!_isCurrentSource(generation)) return false;
        if (uncommittedHandle == 0 &&
            result.errorCode == BASS.BASS_ERROR_INIT) {
          _bassInit();
          device = _bassGetDevice();
          if (device == _bassErrorValue) {
            throw _sourceOpenException(_bass.BASS_ErrorGetCode(), isUrl: false);
          }
          result = await _openBassFileInBackground(
            _bassLibraryPath,
            source,
            flags,
            device,
            segment,
          );
          uncommittedHandle = result.handle;
          if (!_isCurrentSource(generation)) return false;
        }
        if (uncommittedHandle == 0) {
          throw _sourceOpenException(result.errorCode, isUrl: false);
        }
        openedReplayGain = result.replayGain;
        if (analyseSilence) {
          final scan = BassSilenceScan(
              _bassLibraryPath, uncommittedHandle, silencePreferences);
          _silenceScans.add(scan);
          try {
            openedSilence = await scan.result;
          } finally {
            _silenceScans.remove(scan);
          }
          if (!_isCurrentSource(generation)) return false;
          // Analysis leaves the uncommitted decoder at an edge. Always rewind,
          // including timeout, cancellation or unsupported analysis results.
          if (_bass.BASS_ChannelSetPosition(
                  uncommittedHandle, 0, BASS.BASS_POS_BYTE) ==
              0) {
            throw _sourceOpenException(_bass.BASS_ErrorGetCode(), isUrl: false);
          }
          if (silencePreferences != _silenceSkipping) openedSilence = null;
          final bounds = openedSilence;
          if (bounds != null) {
            final ended = bounds.end >= bounds.duration ||
                _bass.BASS_ChannelSetPosition(
                        uncommittedHandle,
                        _bass.BASS_ChannelSeconds2Bytes(
                            uncommittedHandle, bounds.end),
                        0x10) !=
                    0;
            final moved = ended &&
                _bass.BASS_ChannelSetPosition(
                        uncommittedHandle,
                        _bass.BASS_ChannelSeconds2Bytes(
                            uncommittedHandle, bounds.start),
                        BASS.BASS_POS_BYTE) !=
                    0;
            if (moved) {
              silenceDecoder = uncommittedHandle;
            } else {
              if (_bass.BASS_ChannelSetPosition(uncommittedHandle, 0, 0x10) ==
                      0 ||
                  _bass.BASS_ChannelSetPosition(
                          uncommittedHandle, 0, BASS.BASS_POS_BYTE) ==
                      0) {
                throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
                    isUrl: false);
              }
              openedSilence = null;
            }
          }
        }
      }

      if (!_isCurrentSource(generation)) return false;
      final openedFormat = readBassChannelFormat(_bassLib, uncommittedHandle);
      if (_tempo != null) {
        final wrapped =
            _tempo!.createStream(uncommittedHandle, decodingOutput: useMixer);
        if (wrapped == 0) {
          throw FormatException(
              '无法创建保音高播放流（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
        }
        // The wrapper owns the original decoder from this point onwards.
        uncommittedHandle = wrapped;
        _setNativeTempo(uncommittedHandle, _playbackRate);
        _setNativePitch(uncommittedHandle, _playbackPitch);
        _bass.BASS_ChannelSetAttribute(
            uncommittedHandle, BassTempoLibrary.preventClickAttribute, 1);
      }
      if (useMixer) {
        if (_transitions.enabled) {
          _bass.BASS_ChannelSetAttribute(uncommittedHandle, 8, 4);
        }
        if (exclusive) {
          _ensureExclusiveMixer();
        } else {
          _ensureSharedMixer();
        }
        final mixer = exclusive ? _exclusiveMixer! : _sharedMixer!;
        if (!_mix!.addChannel(mixer, uncommittedHandle, paused: true)) {
          throw FormatException(
              ui('无法将音频接入输出（BASS 错误码 {0}）', [_bass.BASS_ErrorGetCode()]));
        }
        uncommittedInMixer = true;
      }
      final segmentLength = segment?.duration(_bass.BASS_ChannelBytes2Seconds(
          uncommittedHandle,
          _bass.BASS_ChannelGetLength(uncommittedHandle, BASS.BASS_POS_BYTE)));
      // Only the final stream receives these factors, never both its decoder
      // and tempo wrapper. Set the target before publishing/playing the source
      // so a previous stream's unfinished slide cannot leak into the new song.
      final openedDspBase = _playbackVolume.initialize(
          uncommittedHandle,
          useMixer && !exclusive && !_decodingOfflineMixer
              ? _sharedSourceVolume
              : _userVolumeDsp,
          openedReplayGain,
          _replayGain);
      onBeforeCommit?.call();
      // A metadata rename may land while this same source is rebuilding its
      // output. Keep the verified new location rather than restoring a stale
      // filename captured before the await. Unrelated new tracks are untouched.
      final committedPath = sourcePathAfterLocalRelink(
          requested: source,
          previousCurrent: priorSourcePath,
          current: _fPath,
          isUrl: isUrl);
      freeFStream();
      if (!exclusive) _disposeExclusiveOutput();
      if (!useMixer || exclusive) _disposeSharedMixer();
      _outputMode.commitStream(exclusive);
      _streamUsesMixer = useMixer;
      _fstream = uncommittedHandle;
      uncommittedInMixer = false;
      uncommittedHandle = 0; // ownership has moved to the active stream
      _fPath = committedPath;
      _sourceIsUrl = isUrl;
      _segment = segment;
      _segmentLength = segmentLength;
      _silenceBounds = openedSilence;
      _silenceDecoder = silenceDecoder;
      _replayGainTags = openedReplayGain;
      _volumeDspBase = openedDspBase;
      _sourceFormat = openedFormat;
      _equalizer.sourceFormat(openedFormat?.sampleRate);
      _eventBoundary.replace();
      _lastEvent = null;
      _deviceInterrupted = false;
      if (openedSilence != null && openedSilence.start > 0) {
        _seekNative(openedSilence.start);
      }
      if (_eqEnabled) _applyEqToStream();
      return true;
    } catch (_) {
      if (!_isCurrentSource(generation)) return false;
      rethrow;
    } finally {
      try {
        // Even an already cancelled native call can succeed just before its
        // cancellation arrives. Such late handles must never replace new audio.
        if (uncommittedHandle != 0) {
          if (uncommittedInMixer) _mix?.removeChannel(uncommittedHandle);
          _bass.BASS_StreamFree(uncommittedHandle);
        }
      } finally {
        if (pending != null) {
          _pendingUrlOpens.remove(pending);
          pending.complete();
        }
        if (pendingFile != null) {
          _pendingFileOpens.remove(pendingFile);
          pendingFile.complete();
        }
        if (fileSlotAcquired) _fileOpenGate.release();
        if (urlSlotAcquired) _urlOpenGate.release();
      }
    }
  }

  static PlaybackProblem _sourceOpenException(int code, {required bool isUrl}) {
    final message = switch (code) {
      BASS.BASS_ERROR_INIT => '音频设备未初始化，请检查输出设备后重试',
      BASS.BASS_ERROR_DEVICE => '音频输出设备无效或已断开',
      BASS.BASS_ERROR_NOTAVAIL => '当前音频流的播放配置不受支持',
      32 => '无法连接网络，请检查网络连接或代理设置', // BASS_ERROR_NONET
      BASS.BASS_ERROR_ILLPARAM => isUrl ? '在线音频地址无效' : '音频文件路径或参数无效',
      48 => '不支持该在线音频地址的协议', // BASS_ERROR_PROTOCOL
      10 => 'HTTPS/SSL 支持不可用，请检查 BASS 运行库及系统网络组件', // BASS_ERROR_SSL
      40 => '连接音频服务器超时，请稍后重试', // BASS_ERROR_TIMEOUT
      51 => '在线音频请求已取消', // BASS_ERROR_CANCEL
      49 => '音频服务器拒绝访问，可能需要登录或播放授权', // BASS_ERROR_DENIED
      BASS.BASS_ERROR_FILEOPEN =>
        isUrl ? '无法打开在线音频，地址可能已失效或服务器不可用' : '无法打开音频文件，请检查文件是否存在及访问权限',
      BASS.BASS_ERROR_FILEFORM => '音频格式无法识别或不受支持',
      47 => '该文件不支持流式播放，可尝试下载后本地播放', // BASS_ERROR_UNSTREAMABLE
      BASS.BASS_ERROR_NOTAUDIO => isUrl ? '服务器返回的内容不是可播放音频' : '该文件不包含可播放的音频',
      BASS.BASS_ERROR_CODEC => '缺少该音频格式所需的解码器',
      BASS.BASS_ERROR_FORMAT => '音频采样格式不受支持',
      BASS.BASS_ERROR_SPEAKER => '音频输出声道配置无效',
      BASS.BASS_ERROR_MEM => '内存不足，无法打开音频',
      BASS.BASS_ERROR_NO3D => '无法初始化 3D 音频',
      _ => '打开${isUrl ? '在线' : '本地'}音频失败（BASS 错误码 $code）',
    };
    return PlaybackProblem(
        switch (code) {
          BASS.BASS_ERROR_INIT ||
          BASS.BASS_ERROR_DEVICE ||
          BASS.BASS_ERROR_DRIVER =>
            PlaybackProblemKind.deviceInitialization,
          BASS.BASS_ERROR_FILEFORM ||
          BASS.BASS_ERROR_NOTAUDIO ||
          BASS.BASS_ERROR_CODEC ||
          BASS.BASS_ERROR_FORMAT =>
            PlaybackProblemKind.decodeFailure,
          BASS.BASS_ERROR_HANDLE => PlaybackProblemKind.invalidHandle,
          _ => PlaybackProblemKind.sourceUnavailable,
        },
        message,
        nativeCode: code);
  }

  /// Apply user volume at playback/mixing, after buffered decoding. The legacy
  /// method name and stored preference remain compatible with existing data.
  void setVolumeDsp(double volume) {
    if (!volume.isFinite || volume < 0) {
      throw ArgumentError.value(
          volume, 'volume', 'Must be finite and nonnegative');
    }
    if (_hasSharedMuteGate && volume == 0) {
      _playbackVolume.muteOutput(_sharedMixer!, muted: true);
      // Keep mixing/consuming the same timeline at the last nonzero source
      // gain. Queuing zero PCM here would produce delayed silence after a
      // quick unmute. Never flush, rewind or pause the mixer for a mute.
      _userVolumeDsp = 0;
      return;
    }
    if (_fstream != null) {
      _playbackVolume.target(_fstream!, volume, _replayGainTags, _replayGain,
          dspBase: _volumeDspBase, smooth: playerState == PlayerState.playing);
    }
    for (final source in [_preparedSource, _transitionTail]) {
      if (source != null) {
        _playbackVolume.target(
            source.handle, volume, source.replayGain, _replayGain,
            dspBase: source.dspBase,
            smooth: playerState == PlayerState.playing);
      }
    }
    if (_hasSharedMuteGate) {
      _playbackVolume.muteOutput(_sharedMixer!, muted: false);
    }
    _userVolumeDsp = volume;
    if (volume > 0) _lastAudibleVolumeDsp = volume;
  }

  /// The decoder position diagnoses the cause of an inactive stream. In
  /// exclusive mode the UI clock compensates mixer buffering, and therefore
  /// must not be mistaken for the raw decoder's end marker (or vice versa).
  double get _boundaryPosition => _readPosition(decoding: true) ?? double.nan;

  /// Transactional and safe during source opening: the commit uses the latest
  /// preferences. Persist only after true; a failed native call keeps old prefs.
  bool configureReplayGain(ReplayGainPreferences preferences) {
    cancelPreparedSource();
    _retireTransitionTail();
    if (_freed) return false;
    try {
      if (_fstream != null) {
        // Keep the source's DSP base fixed: decoded buffers retain that gain.
        // Only change the final factor, so buffered old samples and newly
        // decoded samples can never receive mismatched ReplayGain factors.
        _playbackVolume.target(
            _fstream!,
            _hasSharedMuteGate ? _sharedSourceVolume : _userVolumeDsp,
            _replayGainTags,
            preferences,
            dspBase: _volumeDspBase,
            smooth: playerState == PlayerState.playing);
      }
      _replayGain = preferences;
      return true;
    } catch (error, trace) {
      LOGGER.w('[replay gain] $error', stackTrace: trace);
      return false;
    }
  }

  void _setNativeTempo(int stream, double rate) {
    if (_bass.BASS_ChannelSetAttribute(stream, BassTempoLibrary.tempoAttribute,
            PlaybackRate.tempoPercent(rate)) ==
        BASS.FALSE) {
      throw FormatException('调整播放速度失败（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
    }
  }

  /// Changes tempo without restarting the source, changing pitch or rewriting
  /// lyric timestamps. BASS_FX exposes positions in the original media timeline.
  bool setPlaybackRate(double rate) {
    PlaybackRate.validate(rate);
    if (_freed) return false;
    if (rate == _playbackRate) return true;
    cancelPreparedSource();
    _retireTransitionTail();
    if (_tempo == null) {
      throw StateError(tempoUnavailableReason ?? '倍速组件未加载');
    }
    if (_fstream != null) _setNativeTempo(_fstream!, rate);
    _playbackRate = rate;
    if (_fstream != null) _publishPosition();
    return true;
  }

  void _setNativePitch(int stream, double pitch) {
    if (_bass.BASS_ChannelSetAttribute(
            stream, BassTempoLibrary.pitchAttribute, pitch) ==
        BASS.FALSE) {
      throw FormatException(
          ui('调整音高失败（BASS 错误码 {0}）', [_bass.BASS_ErrorGetCode()]));
    }
  }

  /// Changes only pitch on the existing tempo stream. Source position, tempo,
  /// playback state and lyric timing remain unchanged.
  bool setPlaybackPitch(double pitch) {
    PlaybackPitch.validate(pitch);
    if (_freed) return false;
    if (pitch == _playbackPitch) return true;
    cancelPreparedSource();
    _retireTransitionTail();
    if (_tempo == null) {
      throw StateError(ui('音高组件不可用，请使用包含 BASS/bass_fx.dll 的完整安装包'));
    }
    if (_fstream != null) _setNativePitch(_fstream!, pitch);
    _playbackPitch = pitch;
    return true;
  }

  void _ensureExclusiveMixer() {
    if (_exclusiveMixer != null) return;
    final mix = _mix;
    if (mix == null) {
      throw StateError(
          exclusiveOutputUnavailableReason ?? '独占输出组件 BASSmix 不可用');
    }
    final mixer = mix.createStream(
      48000,
      2,
      BASS.BASS_SAMPLE_FLOAT |
          BASS.BASS_STREAM_DECODE |
          BassMixLibrary.resume |
          BassMixLibrary.nonstop,
    );
    if (mixer == 0) {
      throw FormatException(
          '无法创建独占输出混音器（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
    }
    _exclusiveMixer = mixer;
  }

  void _ensureSharedMixer() {
    if (_sharedMixer != null) return;
    final mixer = _mix!.createStream(
        48000,
        2,
        BASS.BASS_SAMPLE_FLOAT |
            (_decodingOfflineMixer ? BASS.BASS_STREAM_DECODE : 0) |
            BassMixLibrary.nonstop |
            BassMixLibrary.resume);
    if (mixer == 0) {
      throw _sourceOpenException(_bass.BASS_ErrorGetCode(), isUrl: false);
    }
    try {
      if (!_decodingOfflineMixer) {
        _playbackVolume.muteOutput(mixer, muted: _userVolumeDsp == 0);
      }
    } catch (_) {
      _bass.BASS_StreamFree(mixer);
      rethrow;
    }
    _sharedMixer = mixer;
  }

  void _disposeSharedMixer() {
    final mixer = _sharedMixer;
    _sharedMixer = null;
    if (mixer != null) _bass.BASS_StreamFree(mixer);
  }

  void _bassWasapiInit() {
    if (_wasapiInitialized) return;
    _ensureExclusiveMixer();
    final result = initializeWasapiOutput(
      attempt: (compatible) {
        final initialized = _bassWasapi.BASS_WASAPI_Init(
          -1,
          0,
          0,
          BASS.BASS_WASAPI_EXCLUSIVE |
              BASS.BASS_WASAPI_EVENT |
              _bassWasapiBuffer |
              (compatible ? _bassWasapiAutoFormat : 0),
          0.05,
          0,
          ffi.Pointer<BASS.WASAPIPROC>.fromAddress(-1),
          ffi.Pointer<ffi.Void>.fromAddress(_exclusiveMixer!),
        );
        if (initialized != BASS.FALSE) return 0;
        final code = _bass.BASS_ErrorGetCode();
        return code == 0 ? -1 : code;
      },
      resetExisting: () => _bassWasapi.BASS_WASAPI_Free(),
    );
    if (!result.succeeded) {
      final reason = switch (result.errorCode) {
        BASS.BASS_ERROR_BUSY => '设备正被其他程序占用，请关闭占用程序或使用共享模式',
        BASS.BASS_ERROR_DEVICE => '输出设备无效或已断开',
        BASS.BASS_ERROR_FORMAT => '设备不支持当前采样格式，兼容格式也不可用',
        BASS.BASS_ERROR_NOTAVAIL => '设备不支持独占或事件驱动输出，请使用共享模式',
        BASS.BASS_ERROR_WASAPI_DENIED => '系统拒绝访问音频设备',
        BASS.BASS_ERROR_DRIVER => '音频驱动无法初始化',
        BASS.BASS_ERROR_WASAPI_BUFFER => '设备不支持所需的输出缓冲区',
        _ => 'WASAPI 初始化失败（错误码 ${result.errorCode}）',
      };
      throw PlaybackProblem(
          result.errorCode == BASS.BASS_ERROR_BUSY ||
                  result.errorCode == BASS.BASS_ERROR_WASAPI_DENIED
              ? PlaybackProblemKind.exclusiveDenied
              : PlaybackProblemKind.deviceInitialization,
          reason,
          nativeCode: result.errorCode);
    }
    _wasapiInitialized = true;
  }

  void _ensureExclusiveOutput({required bool start}) {
    _bassWasapiInit();
    if (!start || _bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE) return;

    var started = _bassWasapi.BASS_WASAPI_Start();
    if (started == BASS.FALSE &&
        _bass.BASS_ErrorGetCode() == BASS.BASS_ERROR_INIT) {
      _wasapiInitialized = false;
      _bassWasapiInit();
      started = _bassWasapi.BASS_WASAPI_Start();
    }
    if (started == BASS.FALSE) {
      throw FormatException('无法启动独占输出（错误码 ${_bass.BASS_ErrorGetCode()}）');
    }
  }

  void _start_wasapiExclusive() {
    final stream = _fstream!;
    if (_mix!.setChannelPaused(stream, false) == BassMixLibrary.errorValue) {
      throw FormatException('无法恢复独占解码源（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
    }
    try {
      _ensureExclusiveOutput(start: true);
    } catch (_) {
      _mix!.setChannelPaused(stream, true);
      rethrow;
    }
    _publishState(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  /// start/resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void start() {
    _outputPlaybackIntent?.request(true);
    _resumeCurrentOutput();
  }

  // Internal buffer/output recovery is not a new user transport command.
  void _resumeCurrentOutput() {
    if (_fstream == null) return;

    try {
      _startCurrentStream();
    } catch (error) {
      final problem = error is PlaybackProblem
          ? error
          : PlaybackProblem(
              PlaybackProblemKind.deviceInitialization, '无法启动音频输出。',
              nativeCode: _bass.BASS_ErrorGetCode());
      _publishState(playerState, problem: problem);
      rethrow;
    }
  }

  void _startCurrentStream() {
    final interrupted = _deviceInterrupted;
    _deviceInterrupted = false;
    // Capture completion before rearming invalidates its event stamp. Mixer
    // sources do not rewind at EOF when their PAUSE flag is cleared. CUE
    // sources must rewind to their segment start, not the containing file.
    final duration = length;
    final event = _lastEvent;
    final completed =
        event != null && event.completed && _eventBoundary.accepts(event.stamp);
    final restartSource = duration.isFinite &&
        duration > 0 &&
        ((_streamUsesMixer && completed) ||
            (_segment != null &&
                (position >= duration ||
                    (playerState == PlayerState.stopped &&
                        classifyPlaybackStop(
                              validHandle: true,
                              deviceAvailable: true,
                              position: _boundaryPosition,
                              duration: _silenceBounds?.end ?? duration,
                              segment: true,
                            ) ==
                            PlaybackEndReason.segmentEnd))));
    _eventBoundary.command(rearm: true);

    if (restartSource) _seekNative(_silenceBounds?.start ?? 0);

    _positionUpdater?.cancel();

    if (wasapiExclusive) {
      return _start_wasapiExclusive();
    }
    if (_streamUsesMixer && _sharedMixer != null) {
      if (_mix!.getChannelMixer(_fstream!) == 0 &&
          !_mix!.addChannel(_sharedMixer!, _fstream!, paused: true)) {
        throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
            isUrl: _sourceIsUrl);
      }
      if (_mix!.setChannelPaused(_fstream!, false) ==
              BassMixLibrary.errorValue ||
          (!_decodingOfflineMixer &&
              _bass.BASS_ChannelStart(_sharedMixer!) == 0)) {
        throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
            isUrl: _sourceIsUrl);
      }
      _publishState(playerState);
      _positionUpdater = _getPositionUpdater();
      return;
    }
    if (interrupted) _startDevice();
    var started = _bass.BASS_ChannelStart(_fstream!);
    if (started == 0 && _bass.BASS_ErrorGetCode() == BASS.BASS_ERROR_START) {
      _startDevice();
      started = _bass.BASS_ChannelStart(_fstream!);
    }
    if (started == 0) {
      throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
          isUrl: _sourceIsUrl);
    }

    _publishState(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  void _pause_wasapiExclusive() {
    if (_mix!.setChannelPaused(_fstream!, true) == BassMixLibrary.errorValue) {
      throw FormatException('无法暂停独占解码源（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
    }
    _eventBoundary.command();
    _publishState(playerState);
    _positionUpdater?.cancel();
    _positionUpdater = null;
  }

  /// pause channel, call [start] to resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void pause() {
    _outputPlaybackIntent?.request(false);
    if (_fstream == null) return;
    cancelPreparedSource();
    _retireTransitionTail();

    if (wasapiExclusive) {
      _pause_wasapiExclusive();
      _resetSpectrum();
      return;
    }

    final paused = _decodingOfflineMixer && _streamUsesMixer
        ? _mix!.setChannelPaused(_fstream!, true) != BassMixLibrary.errorValue
        : _bass.BASS_ChannelPause(_sharedMixer ?? _fstream!) != 0;
    if (!paused) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played or paused.");
        case BASS.BASS_ERROR_NOPLAY:
          // EOF may win immediately before an A–B interval or user pause.
          // Already inactive is a successful pause; still invalidate queued
          // completion below so this command cannot accidentally auto-advance.
          break;
      }
    }

    _eventBoundary.command();
    _publishState(playerState);
    _positionUpdater?.cancel();
    _positionUpdater = null;
    _resetSpectrum();
  }

  /// set channel's position to given [position]
  /// don't check if the position is valid.
  ///
  /// do nothing if [setSource] hasn't been called
  void seek(double position) {
    if (_fstream == null) return;
    restoreFullSilenceRange();
    _cancelPreparedSource(restoreSharedBuffer: false);
    _retireTransitionTail();
    final stateBeforeSeek = playerState;

    if (wasapiExclusive && _wasapiInitialized) {
      seekWasapiOutput(
        wasPlaying: stateBeforeSeek.keepsPlaybackIntent,
        flush: () {
          // A paused mixer source leaves the resident endpoint running. Stop
          // only a currently started endpoint to flush pre-seek device data;
          // the paused source remains paused until an explicit start().
          if (_bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE &&
              _bassWasapi.BASS_WASAPI_Stop(BASS.TRUE) == BASS.FALSE) {
            throw FormatException(
                '无法刷新独占输出缓冲区（错误码 ${_bass.BASS_ErrorGetCode()}）');
          }
          _positionUpdater?.cancel();
          _positionUpdater = null;
        },
        move: () => _seekNative(position),
        resume: _resumeCurrentOutput,
      );
    } else {
      _seekNative(position);
      if (_streamUsesMixer &&
          _sharedMixer != null &&
          stateBeforeSeek.keepsPlaybackIntent) {
        if (_mix!.setChannelPaused(_fstream!, false) ==
            BassMixLibrary.errorValue) {
          throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
              isUrl: _sourceIsUrl);
        }
      }
    }

    // Pause cancels the periodic updater. Publish only after native success so
    // paused sliders/lyrics update without resuming playback, and report BASS's
    // real (possibly sample-rounded) position rather than an optimistic target.
    _eventBoundary.command(rearm: true);
    _positionUpdater = rearmBassPositionUpdaterAfterSeek(
      _positionUpdater,
      stateBeforeSeek: stateBeforeSeek,
      create: _getPositionUpdater,
    );
    _publishPosition();
    _publishState(playerState);
  }

  void _seekNative(double position) {
    final stream = _fstream!;
    if (_streamUsesMixer && _activeMixer != null) {
      final attached = _mix!.getChannelMixer(stream);
      final exhaustedShared = _activeMixer == _sharedMixer &&
          _mix!.channelIsActive(stream) == BASS.BASS_ACTIVE_STOPPED;
      if (attached == 0 || exhaustedShared) {
        if (attached != 0) _mix!.removeChannel(stream);
        if (!_mix!.addChannel(_activeMixer!, stream, paused: true)) {
          throw _sourceOpenException(_bass.BASS_ErrorGetCode(),
              isUrl: _sourceIsUrl);
        }
      }
    }
    final sourcePosition =
        _segment?.sourcePosition(position, length) ?? position;
    final bytes = bassSeekPositionBytes(_bass, stream, sourcePosition);
    // MIXER_RESET flushes the playable mixer's buffer with this source seek.
    // A second mixer reset can discard newly decoded target PCM if the output
    // worker refills between the calls. Decoding mixers have no buffer to flush.
    final moved = _streamUsesMixer && _activeMixer != null
        ? _mix!.setChannelPosition(
            stream,
            bytes,
            BASS.BASS_POS_BYTE | BassMixLibrary.positionMixerReset,
          )
        : _bass.BASS_ChannelSetPosition(
              stream,
              bytes,
              BASS.BASS_POS_BYTE,
            ) !=
            0;
    if (!moved) {
      final errorCode = _bass.BASS_ErrorGetCode();
      switch (errorCode) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_NOTFILE:
          throw const FormatException("The stream is not a file stream.");
        case BASS.BASS_ERROR_POSITION:
          throw const FormatException(
              "The requested position is invalid, eg. it is beyond the end or the download has not yet reached it.");
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The requested mode is not available. Invalid flags are ignored and do not result in this error.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
        default:
          throw FormatException('调整播放位置失败（BASS 错误码 $errorCode）');
      }
    }
  }

  /// It is not necessary to individually free the samples/streams/musics
  /// as these are all automatically freed after [setSource] or [free] is called.
  ///
  /// do nothing if [setSource] hasn't been called
  void freeFStream() {
    _cancelPreparedSource(restoreSharedBuffer: false);
    _retireTransitionTail();
    if (_fstream == null) return;

    _eventBoundary.replace();

    _positionUpdater?.cancel();
    _positionUpdater = null;

    _equalizer.forgetSource();
    final handle = _fstream!;
    if (_streamUsesMixer && _activeMixer != null) {
      // Detach only the decoder. The silent NONSTOP mixer and WASAPI device
      // remain resident, so normal track changes never Stop/Free/Init the
      // exclusive endpoint on Flutter's UI isolate.
      _mix?.removeChannel(handle);
    }
    if (_sharedMixer != null) {
      _bass.BASS_ChannelPause(_sharedMixer!);
      _bass.BASS_ChannelSetPosition(_sharedMixer!, 0, BASS.BASS_POS_BYTE);
    }
    _fstream = null;
    _streamUsesMixer = false;
    _fPath = null;
    _sourceIsUrl = false;
    _segment = null;
    _segmentLength = null;
    _silenceBounds = null;
    _silenceDecoder = null;
    _replayGainTags = const ReplayGainTags();
    _sourceFormat = null;
    _deviceInterrupted = false;
    _publishState(PlayerState.stopped, reason: PlaybackEndReason.userStop);
    _resetSpectrum();

    if (_bass.BASS_StreamFree(handle) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          LOGGER.w("StreamFree is called on a invalid handle.");
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Device streams (STREAMPROC_DEVICE) cannot be freed.");
      }
    }
  }

  void _disposeExclusiveOutput() {
    if (_wasapiInitialized) {
      if (_bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE) {
        _bassWasapi.BASS_WASAPI_Stop(BASS.TRUE);
      }
      if (_bassWasapi.BASS_WASAPI_Free() == BASS.FALSE) {
        LOGGER.w(
          '[wasapi free] BASS error ${_bass.BASS_ErrorGetCode()}',
        );
      }
      _wasapiInitialized = false;
    }

    final mixer = _exclusiveMixer;
    _exclusiveMixer = null;
    if (mixer != null && _bass.BASS_StreamFree(mixer) == BASS.FALSE) {
      LOGGER.w('[mixer free] BASS error ${_bass.BASS_ErrorGetCode()}');
    }
  }

  /// Releases the active native stream only when it owns [filePath]. This also
  /// covers the narrow hand-off window after a worker commits its HSTREAM but
  /// before PlaybackService publishes the corresponding nowPlaying value.
  bool freeSourceIfPath(String filePath) {
    var releasedPrepared = false;
    if (_preparedSource != null &&
        path.equals(_preparedSource!.path, filePath)) {
      cancelPreparedSource();
      releasedPrepared = true;
    }
    if (_transitionTail != null &&
        path.equals(_transitionTail!.path, filePath)) {
      _retireTransitionTail();
      releasedPrepared = true;
    }
    final currentPath = _fPath;
    if (currentPath == null || !path.equals(currentPath, filePath)) {
      return releasedPrepared;
    }
    freeFStream();
    return true;
  }

  /// Frees all resources used by the output device,
  /// including all its samples, streams and MOD musics.
  ///
  /// Also free the bass.dll.
  Future<void> free() => _freeFuture ??= _free();

  Future<void> _free() async {
    _freed = true;
    cancelPendingSource();
    _fileOpenGate.cancelWaiters();

    _positionUpdater?.cancel();
    _positionUpdater = null;
    freeFStream();
    _disposeExclusiveOutput();
    _disposeSharedMixer();
    // StreamCancel only signals cancellation. Keep BASS and its device loaded
    // until every worker has returned and its uncommitted handle has been freed.
    await Future.wait([
      for (final request in _pendingUrlOpens) request.finished.future,
      for (final request in _pendingFileOpens) request.finished.future,
    ]);
    if (_bass.BASS_Free() == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          LOGGER.w("BASS_Free is called before BASS_Init complete normally.");
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is currently being reinitialized.");
      }
    }

    // BASS_Free releases device streams, but not codec plugins. Releasing
    // only our own handles lets a closed player be constructed again without
    // leaving DLL references behind or unloading someone else's codecs.
    for (final plugin in _loadedPlugins.reversed) {
      _bass.BASS_PluginFree(plugin);
    }
    _loadedPlugins.clear();
    _bassWasapiLib.close();
    _mix?.close();
    _mix = null;
    _tempo?.close();
    _tempo = null;
    _bassLib.close();

    _resetSpectrum();
    _playerStateStreamController.close();
    _positionStreamController.close();
    _spectrumStreamController.close();
    _frequencySpectrumStreamController.close();
    ffi.malloc.free(_fftBuffer);
    ffi.malloc.free(_frequencyBuffer);
  }
}
