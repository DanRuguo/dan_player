import 'spectrum_analysis.dart';
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/src/bass/bass_diagnostics.dart';
import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass_replay_gain.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
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

const int BASS_FX_DX8_PARAMEQ = 7;

final class BassDx8ParamEq extends ffi.Struct {
  @ffi.Float()
  external double fCenter;

  @ffi.Float()
  external double fBandwidth;

  @ffi.Float()
  external double fGain;
}

typedef _BassOpenResult = ({
  int handle,
  int errorCode,
  ReplayGainTags replayGain,
});

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
) {
  return Isolate.run(
    () => _openBassUrl(libraryPath, url, flags, device, requestId),
    debugName: 'bass-url-open',
  );
}

_BassOpenResult _openBassUrl(
  String libraryPath,
  String url,
  int flags,
  int device,
  int requestId,
) {
  final library = ffi.DynamicLibrary.open(libraryPath);
  ffi.Pointer<ffi.Void>? urlPointer;
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
    if (setConfig(netTimeout | configThread, 8000) == BASS.FALSE ||
        setConfig(netReadTimeout | configThread, 12000) == BASS.FALSE) {
      throw StateError('无法设置联网音频超时（BASS 错误码 ${getError()}）');
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

class BassPlayer {
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
  late final BASS.BassWasapi _bassWasapi;
  BassMixLibrary? _mix;
  BassTempoLibrary? _tempo;
  String? exclusiveOutputUnavailableReason;
  String? tempoUnavailableReason;
  double _playbackRate = 1.0;
  bool _wasapiInitialized = false;
  int? _exclusiveMixer;

  double get playbackRate => _playbackRate;
  bool get supportsPlaybackRate => !_freed && _tempo != null;

  String? _fPath;
  bool _sourceIsUrl = false;
  AudioSegment? _segment;
  double? _segmentLength;
  int? _fstream;
  double _userVolumeDsp = 1;
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
  Map<String, Object?> outputDiagnostics() => {
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
        'mixerFormat': wasapiExclusive && _exclusiveMixer != null
            ? readBassChannelFormat(_bassLib, _exclusiveMixer!)?.toJson()
            : null,
        'userVolume': _userVolumeDsp,
        'effectiveDspMultiplier': _readEffectiveVolume(),
        'replayGainRequested': _replayGain.mode.name,
        'replayGainApplied': _fstream == null
            ? null
            : _replayGainTags.appliedMode(_replayGain)?.name,
        'replayGainEffectiveDb': _effectiveReplayGainDb,
        'peakProtection': _replayGain.preventClipping,
        'eqRequested': _eqEnabled,
        'eqAppliedBands': _eqAppliedGains.whereType<double>().length,
        'eqRequestedGainsDb': _eqEnabled ? eqGains : null,
        'eqGainsDb': _eqFxHandles.isEmpty ? null : List.of(_eqAppliedGains),
        'eqSettingsApplied': !_eqEnabled ||
            List.generate(_eqGains.length, (index) => index)
                .every((index) => _eqAppliedGains[index] == _eqGains[index]),
        'playbackRate': _playbackRate,
        'tempoAvailable': supportsPlaybackRate,
        'physicalOutputDrained': null,
        'bitPerfectVerified': false,
        'gaplessOutputVerified': false,
      };

  int? get _diagnosticDeviceNumber {
    final value = wasapiExclusive && _wasapiInitialized
        ? _bassWasapiLib.lookupFunction<ffi.Uint32 Function(), int Function()>(
            'BASS_WASAPI_GetDevice')()
        : _fstream == null
            ? null
            : _bassChannelGetDevice(_fstream!);
    return value == _bassErrorValue ? null : value;
  }

  double? get _effectiveReplayGainDb {
    if (_userVolumeDsp <= 0 ||
        _replayGainTags.appliedMode(_replayGain) == null) {
      return null;
    }
    final native = _readEffectiveVolume();
    if (native == null || native <= 0) return null;
    return 20 * math.log(native / _userVolumeDsp) / math.ln10;
  }

  final _outputMode = WasapiOutputMode();

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
      return length;
    return _readPosition(decoding: false) ?? 0.0;
  }

  double? _readPosition({required bool decoding}) {
    final stream = _fstream;
    if (stream == null) return null;
    // BASS_POS_DECODE bypasses the tempo/output playback buffer. Only the UI
    // clock uses mixer compensation; a stopped channel is diagnosed against
    // the decoder clock, including when the tempo wrapper is playing at 1x.
    const positionDecode = 0x10000000;
    final bytes = !decoding && wasapiExclusive && _exclusiveMixer != null
        ? _mix!.getChannelPosition(stream, BASS.BASS_POS_BYTE)
        : _bass.BASS_ChannelGetPosition(
            stream, BASS.BASS_POS_BYTE | (decoding ? positionDecode : 0));
    if (bytes == _bassPositionErrorValue) return null;
    final absolute = _bass.BASS_ChannelBytes2Seconds(stream, bytes);
    if (!absolute.isFinite || absolute < 0) return null;
    return _segment?.relativePosition(absolute, length) ?? absolute;
  }

  PlayerState get playerState {
    if (_fstream == null) {
      return PlayerState.unknown;
    }
    if (_deviceInterrupted) return PlayerState.pausedDevice;

    final active = wasapiExclusive && _exclusiveMixer != null
        ? _mix!.channelIsActive(_fstream!)
        : _bass.BASS_ChannelIsActive(_fstream!);
    switch (active) {
      case BASS.BASS_ACTIVE_STOPPED:
        return PlayerState.stopped;
      case BASS.BASS_ACTIVE_PLAYING:
        if (wasapiExclusive &&
            _bassWasapi.BASS_WASAPI_IsStarted() != BASS.TRUE) {
          return PlayerState.pausedDevice;
        }
        return PlayerState.playing;
      case BASS.BASS_ACTIVE_PAUSED:
        return PlayerState.paused;
      case BASS.BASS_ACTIVE_PAUSED_DEVICE:
        return PlayerState.pausedDevice;
      case BASS.BASS_ACTIVE_STALLED:
        return PlayerState.stalled;
      default:
        return PlayerState.unknown;
    }
  }

  /// User volume stays independent of the current song's ReplayGain tags.
  double get volumeDsp => _fstream == null ? 0 : _userVolumeDsp;

  /// Actual native DSP multiplier, useful for output diagnostics.
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
      return read != 0 && volDsp.value.isFinite ? volDsp.value : null;
    } finally {
      ffi.malloc.free(volDsp);
    }
  }

  /// Normal playback updates every 33ms. Successful seeks additionally publish
  /// the actual native position immediately, including while paused.
  Stream<double> get positionStream => _eventBoundary
      .currentEvents(_positionStreamController.stream, (event) => event.stamp)
      .map((event) => event.position);

  Stream<PlayerState> get playerStateStream =>
      playbackEvents.map((event) => event.state);

  Stream<BassPlaybackEvent> get playbackEvents => _eventBoundary.currentEvents(
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

  Timer _getPositionUpdater() {
    final stamp = _eventBoundary.stamp;
    var lastObserved = playerState;
    final initialDevice = !wasapiExclusive && _fstream != null
        ? _bassChannelGetDevice(_fstream!)
        : null;
    return Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        if (_freed || !_eventBoundary.accepts(stamp)) {
          timer.cancel();
          return;
        }
        _publishPosition();

        final changedDevice = initialDevice != null &&
            _fstream != null &&
            _bassChannelGetDevice(_fstream!) != initialDevice;
        final observed = changedDevice ? PlayerState.pausedDevice : playerState;
        // BASS reports STOPPED for an invalid handle as well as a valid
        // inactive channel. Read its error immediately, before any other FFI.
        final nativeError = _bass.BASS_ErrorGetCode();
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
            duration: length,
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
                _bass.BASS_ChannelPause(_fstream!);
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
          final levels = _updateSpectrum();
          if (_spectrumStreamController.hasListener) {
            _spectrumStreamController.add(levels);
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

  /// BASS_SetConfig is outside the generated binding subset.
  late final int Function(int option, int value) _bassSetConfig =
      _bassLib.lookupFunction<ffi.Uint32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)>('BASS_SetConfig');

  /// bass.h: BASS_CONFIG_DEV_DEFAULT
  static const int _bassConfigDevDefault = 36;

  late final int Function(int handle, int type, int priority)
      _bassChannelSetFX = _bassLib.lookupFunction<
          ffi.Uint32 Function(ffi.Uint32, ffi.Uint32, ffi.Int32),
          int Function(int, int, int)>('BASS_ChannelSetFX');

  late final int Function(int handle, int fx) _bassChannelRemoveFX =
      _bassLib.lookupFunction<ffi.Int32 Function(ffi.Uint32, ffi.Uint32),
          int Function(int, int)>('BASS_ChannelRemoveFX');

  late final int Function(int fx, ffi.Pointer<ffi.Void> params)
      _bassFXSetParameters = _bassLib.lookupFunction<
          ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>),
          int Function(int, ffi.Pointer<ffi.Void>)>('BASS_FXSetParameters');

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

  List<double> _updateSpectrum() {
    if (_fstream == null || playerState != PlayerState.playing) {
      return _resetSpectrum(emit: false);
    }

    const flags = _bassDataFft4096 | _bassDataFftRemoveDc;
    final result = wasapiExclusive
        ? _bassWasapiGetData(_fftBuffer.cast(), flags)
        : _bassChannelGetData(_fstream!, _fftBuffer.cast(), flags);
    if (result == _bassErrorValue) {
      return _decaySpectrum();
    }

    var sampleRate = 48000.0;
    if (!wasapiExclusive &&
        _bass.BASS_ChannelGetAttribute(
              _fstream!,
              _bassAttribFreq,
              _frequencyBuffer,
            ) ==
            BASS.TRUE) {
      sampleRate = _frequencyBuffer.value;
    }
    if (!sampleRate.isFinite || sampleRate <= 0) sampleRate = 48000.0;

    final fft = _fftBuffer.asTypedList(_fftValueCount);
    _spectrumAnalysis.update(fft, sampleRate,
        frequencyDemand: _frequencySpectrumStreamController.hasListener,
        toneDemand: _spectrumStreamController.hasListener);
    return List.unmodifiable(_spectrumLevels);
  }

  List<double> _decaySpectrum() {
    for (var i = 0; i < _spectrumLevels.length; i++) {
      _spectrumLevels[i] *= 0.82;
    }
    for (var i = 0; i < _frequencySpectrumLevels.length; i++) {
      _frequencySpectrumLevels[i] *= 0.82;
    }
    return List.unmodifiable(_spectrumLevels);
  }

  List<double> _resetSpectrum({bool emit = true}) {
    for (var i = 0; i < _spectrumLevels.length; i++) {
      _spectrumLevels[i] = 0.0;
    }
    for (var i = 0; i < _frequencySpectrumLevels.length; i++) {
      _frequencySpectrumLevels[i] = 0.0;
    }
    final result = List<double>.unmodifiable(_spectrumLevels);
    if (emit && !_spectrumStreamController.isClosed) {
      _spectrumStreamController.add(result);
    }
    if (emit && !_frequencySpectrumStreamController.isClosed) {
      _frequencySpectrumStreamController.add(
        List.unmodifiable(_frequencySpectrumLevels),
      );
    }
    return result;
  }

  static const List<double> eqBandCenters = [
    80,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    12000,
    16000,
  ];
  static const double eqMaxGainDb = 15.0;
  static const double _eqBandwidthSemitones = 12.0;

  bool _eqEnabled = false;
  bool get eqEnabled => _eqEnabled;

  final List<double> _eqGains = List.filled(eqBandCenters.length, 0.0);
  List<double> get eqGains => List.unmodifiable(_eqGains);

  final List<int> _eqFxHandles = [];
  final List<double?> _eqAppliedGains = List.filled(eqBandCenters.length, null);
  bool get eqActive => _eqFxHandles.isNotEmpty;

  bool _setEqFxParams(int fx, int band) {
    final parameters =
        ffi.malloc.allocate<BassDx8ParamEq>(ffi.sizeOf<BassDx8ParamEq>());
    try {
      parameters.ref.fCenter = eqBandCenters[band];
      parameters.ref.fBandwidth = _eqBandwidthSemitones;
      parameters.ref.fGain = _eqGains[band];
      if (_bassFXSetParameters(fx, parameters.cast()) == BASS.FALSE) {
        LOGGER.w(
          "[eq] set parameters failed for band $band: "
          "${_bass.BASS_ErrorGetCode()}",
        );
        return false;
      }
      _eqAppliedGains[band] = _eqGains[band];
      return true;
    } finally {
      ffi.malloc.free(parameters);
    }
  }

  bool _applyEqToStream() {
    _eqFxHandles.clear();
    if (!_eqEnabled || _fstream == null) return true;

    for (var band = 0; band < eqBandCenters.length; band++) {
      final fx = _bassChannelSetFX(_fstream!, BASS_FX_DX8_PARAMEQ, 0);
      if (fx == 0) {
        LOGGER.w("[eq] attach failed: ${_bass.BASS_ErrorGetCode()}");
        _removeEqFromStream();
        return false;
      }
      _eqFxHandles.add(fx);
      if (!_setEqFxParams(fx, band)) {
        _removeEqFromStream();
        return false;
      }
    }
    return true;
  }

  void _removeEqFromStream() {
    if (_fstream != null) {
      for (final fx in _eqFxHandles) {
        _bassChannelRemoveFX(_fstream!, fx);
      }
    }
    _eqFxHandles.clear();
    _eqAppliedGains.fillRange(0, _eqAppliedGains.length, null);
  }

  bool setEqEnabled(bool enabled) {
    if (enabled == _eqEnabled) return true;
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
    _eqGains[band] = gain.clamp(-eqMaxGainDb, eqMaxGainDb).toDouble();
    if (_eqEnabled && band < _eqFxHandles.length) {
      _setEqFxParams(_eqFxHandles[band], band);
    }
  }

  void setEqGains(List<double> gains) {
    for (var band = 0; band < eqBandCenters.length; band++) {
      final gain = band < gains.length ? gains[band] : 0.0;
      _eqGains[band] = gain.clamp(-eqMaxGainDb, eqMaxGainDb).toDouble();
    }
    if (!_eqEnabled) return;

    final count = _eqFxHandles.length < eqBandCenters.length
        ? _eqFxHandles.length
        : eqBandCenters.length;
    for (var band = 0; band < count; band++) {
      _setEqFxParams(_eqFxHandles[band], band);
    }
  }

  void _bassInit() {
    _bassSetConfig(_bassConfigDevDefault, BASS.TRUE);

    if (_bass.BASS_Init(-1, 48000, 0, ffi.nullptr, ffi.nullptr) == 0) {
      final code = _bass.BASS_ErrorGetCode();
      if (code == BASS.BASS_ERROR_ALREADY) return;
      throw PlaybackProblem(
          code == BASS.BASS_ERROR_BUSY
              ? PlaybackProblemKind.exclusiveDenied
              : PlaybackProblemKind.deviceInitialization,
          '无法初始化音频设备。',
          nativeCode: code);
    }
  }

  void _startDevice() {
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
  BassPlayer() {
    _bassLibraryPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "bass.dll",
    );
    _bassLib = ffi.DynamicLibrary.open(_bassLibraryPath);
    _bass = BASS.Bass(_bassLib);

    final bassWasapiLibPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "basswasapi.dll",
    );
    _bassWasapiLib = ffi.DynamicLibrary.open(bassWasapiLibPath);
    _bassWasapi = BASS.BassWasapi(_bassWasapiLib);

    // BASSmix owns the persistent decoder mixer used by WASAPI exclusive
    // output. Keep shared playback available when an unpacked/incomplete
    // development tree omits the add-on; selecting exclusive mode will report
    // the actionable error instead of failing BassPlayer construction.
    try {
      _mix = BassMixLibrary.open(path.join(
          path.dirname(Platform.resolvedExecutable), 'BASS', 'bassmix.dll'));
    } catch (error, trace) {
      exclusiveOutputUnavailableReason =
          '独占输出组件不可用，请使用包含 BASS/bassmix.dll 的完整安装包';
      LOGGER.w('[bass mix] $error', stackTrace: trace);
    }

    // A missing optional extension must not prevent ordinary 1x playback.
    // The release assembler supplies and verifies the official x64 bytes.
    try {
      _tempo = BassTempoLibrary.open(path.join(
          path.dirname(Platform.resolvedExecutable), 'BASS', 'bass_fx.dll'));
    } catch (error, trace) {
      tempoUnavailableReason = '倍速组件不可用，请使用包含 BASS/bass_fx.dll 的完整安装包';
      LOGGER.w('[bass tempo] $error', stackTrace: trace);
    }

    // load add-ons to avoid using os codec or support more format
    for (final plugin in BASS_PLUGINS) {
      final pluginPath = path.join(
        path.dirname(Platform.resolvedExecutable),
        plugin,
      );
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
    }
  }

  /// true: 操作成功；false: 操作失败或被后续操作取消。
  Future<bool> useExclusiveMode(bool exclusive) async {
    if (_freed) return false;
    if (exclusive == wasapiExclusive) return true;

    final sourcePath = _fPath;
    final sourceIsUrl = _sourceIsUrl;
    final sourceSegment = _segment;
    final previousMode = wasapiExclusive;
    var lastPos = position;
    var wasPlaying = playerState == PlayerState.playing;
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
          wasPlaying = playerState == PlayerState.playing;
        },
      );
      if (!applied || !_isCurrentSource(generation)) return false;

      if (exclusive) _bassWasapiInit();
      if (lastPos > 0) {
        try {
          seek(lastPos);
        } catch (err, trace) {
          LOGGER.w('[use exclusive mode] 无法恢复播放位置：$err', stackTrace: trace);
          showTextOnSnackBar('输出模式已切换，但暂时无法恢复原播放位置');
        }
      }
      if (wasPlaying) {
        start();
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
          if (lastPos > 0) seek(lastPos);
          if (wasPlaying) start();
          _publishState(playerState);
          showTextOnSnackBar('输出模式切换失败，已恢复原模式：{0}', arguments: [err]);
        } catch (restoreError, restoreTrace) {
          if (!_isCurrentSource(generation)) return false;
          LOGGER.e('[restore output mode] $restoreError',
              stackTrace: restoreTrace);
          showTextOnSnackBar('音频设备不可用，原模式也未能恢复；请检查设备后重试');
          _publishState(playerState);
        }
      } else {
        showTextOnSnackBar('切换音频输出失败，原模式保持不变：{0}', arguments: [err]);
      }
      _publishState(playerState,
          problem: err is PlaybackProblem
              ? err
              : const PlaybackProblem(
                  PlaybackProblemKind.deviceInitialization, '音频输出切换失败。'));
      return false;
    }
  }

  /// Invalidates in-flight opens without disturbing the current stream.
  /// Call this as soon as a newer request begins, including its URL-resolution
  /// phase, rather than waiting until that newer URL has been resolved.
  void cancelPendingSource() {
    _sourceGeneration += 1;
    // Discard events already queued by the previous explicit source request.
    // The retained stream may keep playing while another file opens, using a
    // fresh observation stamp; opening cancellation remains independently
    // guarded by _sourceGeneration.
    _eventBoundary.command();
    if (_positionUpdater != null) {
      _positionUpdater!.cancel();
      _positionUpdater = _freed ? null : _getPositionUpdater();
    }
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
    if (exclusive || _tempo != null) flags |= BASS.BASS_STREAM_DECODE;

    var uncommittedHandle = 0;
    var openedReplayGain = const ReplayGainTags();
    var uncommittedInMixer = false;
    _PendingBassUrlOpen? pending;
    _PendingBassFileOpen? pendingFile;
    var fileSlotAcquired = false;
    try {
      if (isUrl) {
        if (_bassStreamCancel == null) {
          throw const FormatException(
              'BASS 运行库过旧，无法安全取消联网请求，请更新到 2.4.18 或更高版本');
        }
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
        final result = await _openBassUrlInBackground(
          _bassLibraryPath,
          source,
          flags,
          device,
          pending.requestId,
        );
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
      }

      if (!_isCurrentSource(generation)) return false;
      final openedFormat = readBassChannelFormat(_bassLib, uncommittedHandle);
      if (_tempo != null) {
        final wrapped =
            _tempo!.createStream(uncommittedHandle, decodingOutput: exclusive);
        if (wrapped == 0) {
          throw FormatException(
              '无法创建保音高播放流（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
        }
        // The wrapper owns the original decoder from this point onwards.
        uncommittedHandle = wrapped;
        _setNativeTempo(uncommittedHandle, _playbackRate);
        _bass.BASS_ChannelSetAttribute(
            uncommittedHandle, BassTempoLibrary.preventClickAttribute, 1);
      }
      if (exclusive) {
        _ensureExclusiveMixer();
        final mixer = _exclusiveMixer!;
        if (!_mix!.addChannel(mixer, uncommittedHandle, paused: true)) {
          throw FormatException(
              '无法将音频接入独占输出（BASS 错误码 ${_bass.BASS_ErrorGetCode()}）');
        }
        uncommittedInMixer = true;
      }
      final segmentLength = segment?.duration(_bass.BASS_ChannelBytes2Seconds(
          uncommittedHandle,
          _bass.BASS_ChannelGetLength(uncommittedHandle, BASS.BASS_POS_BYTE)));
      // Only the final stream receives the composed multiplier. Applying it
      // to both the raw decoder and its tempo wrapper would double the gain.
      _setNativeVolume(uncommittedHandle,
          openedReplayGain.volume(_userVolumeDsp, _replayGain));
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
      _outputMode.commitStream(exclusive);
      _fstream = uncommittedHandle;
      uncommittedInMixer = false;
      uncommittedHandle = 0; // ownership has moved to the active stream
      _fPath = committedPath;
      _sourceIsUrl = isUrl;
      _segment = segment;
      _segmentLength = segmentLength;
      _replayGainTags = openedReplayGain;
      _sourceFormat = openedFormat;
      _eventBoundary.replace();
      _lastEvent = null;
      _deviceInterrupted = false;
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

  /// [BASS_ATTRIB_VOLDSP] attribute does have direct effect on decoding/recording channels.
  void setVolumeDsp(double volume) {
    if (!volume.isFinite || volume < 0) {
      throw ArgumentError.value(
          volume, 'volume', 'Must be finite and nonnegative');
    }
    if (_fstream != null) {
      _setNativeVolume(_fstream!, _replayGainTags.volume(volume, _replayGain));
    }
    _userVolumeDsp = volume;
  }

  /// The decoder position diagnoses the cause of an inactive stream. In
  /// exclusive mode the UI clock compensates mixer buffering, and therefore
  /// must not be mistaken for the raw decoder's end marker (or vice versa).
  double get _boundaryPosition => _readPosition(decoding: true) ?? double.nan;

  /// Transactional and safe during source opening: the commit uses the latest
  /// preferences. Persist only after true; a failed native call keeps old prefs.
  bool configureReplayGain(ReplayGainPreferences preferences) {
    if (_freed) return false;
    try {
      if (_fstream != null) {
        _setNativeVolume(
            _fstream!, _replayGainTags.volume(_userVolumeDsp, preferences));
      }
      _replayGain = preferences;
      return true;
    } catch (error, trace) {
      LOGGER.w('[replay gain] $error', stackTrace: trace);
      return false;
    }
  }

  void _setNativeVolume(int stream, double volume) {
    if (_bass.BASS_ChannelSetAttribute(
          stream,
          BASS.BASS_ATTRIB_VOLDSP,
          volume,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_ILLTYPE:
          throw const FormatException("attrib is not valid.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException("value is not valid.");
        default:
          throw const FormatException('Unable to apply DSP volume.');
      }
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
    if (_tempo == null) {
      throw StateError(tempoUnavailableReason ?? '倍速组件未加载');
    }
    if (_fstream != null) _setNativeTempo(_fstream!, rate);
    _playbackRate = rate;
    if (_fstream != null) _publishPosition();
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
    // Capture completion before rearming invalidates its event stamp. A CUE
    // source must restart at its segment start, not the containing file start.
    final restartSegment = _segment != null &&
        (position >= length ||
            (playerState == PlayerState.stopped &&
                classifyPlaybackStop(
                      validHandle: true,
                      deviceAvailable: true,
                      position: _boundaryPosition,
                      duration: length,
                      segment: true,
                    ) ==
                    PlaybackEndReason.segmentEnd));
    _eventBoundary.command(rearm: true);

    if (restartSegment) _seekNative(0);

    _positionUpdater?.cancel();

    if (wasapiExclusive) {
      return _start_wasapiExclusive();
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
    if (_fstream == null) return;

    if (wasapiExclusive) {
      _pause_wasapiExclusive();
      _resetSpectrum();
      return;
    }

    if (_bass.BASS_ChannelPause(_fstream!) == 0) {
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
    _resetSpectrum();
  }

  /// set channel's position to given [position]
  /// don't check if the position is valid.
  ///
  /// do nothing if [setSource] hasn't been called
  void seek(double position) {
    if (_fstream == null) return;
    final wasPlaying = playerState == PlayerState.playing;

    if (wasapiExclusive && _wasapiInitialized) {
      seekWasapiOutput(
        wasPlaying: playerState == PlayerState.playing,
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
        resume: start,
      );
    } else {
      _seekNative(position);
    }

    // Pause cancels the periodic updater. Publish only after native success so
    // paused sliders/lyrics update without resuming playback, and report BASS's
    // real (possibly sample-rounded) position rather than an optimistic target.
    _eventBoundary.command(rearm: true);
    _positionUpdater?.cancel();
    _positionUpdater = wasPlaying ? _getPositionUpdater() : null;
    _publishPosition();
    _publishState(playerState);
  }

  void _seekNative(double position) {
    final stream = _fstream!;
    final sourcePosition =
        _segment?.sourcePosition(position, length) ?? position;
    final bytes = _bass.BASS_ChannelSeconds2Bytes(stream, sourcePosition);
    final moved = wasapiExclusive && _exclusiveMixer != null
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
    if (_fstream == null) return;

    _eventBoundary.replace();

    _positionUpdater?.cancel();
    _positionUpdater = null;

    _eqFxHandles.clear();
    _eqAppliedGains.fillRange(0, _eqAppliedGains.length, null);
    final handle = _fstream!;
    if (wasapiExclusive && _exclusiveMixer != null) {
      // Detach only the decoder. The silent NONSTOP mixer and WASAPI device
      // remain resident, so normal track changes never Stop/Free/Init the
      // exclusive endpoint on Flutter's UI isolate.
      _mix?.removeChannel(handle);
    }
    _fstream = null;
    _fPath = null;
    _sourceIsUrl = false;
    _segment = null;
    _segmentLength = null;
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
    final currentPath = _fPath;
    if (currentPath == null || !path.equals(currentPath, filePath)) {
      return false;
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
