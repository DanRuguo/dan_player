// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dan_player/app_preference.dart';
import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
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

typedef _BassOpenResult = ({int handle, int errorCode});

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
      return (handle: 0, errorCode: getError());
    }
    final handle = createUrl(
      urlPointer,
      0,
      flags,
      ffi.nullptr,
      ffi.Pointer<ffi.Void>.fromAddress(requestId),
    );
    final errorCode = handle == 0 ? getError() : 0;
    return (handle: handle, errorCode: errorCode);
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

class BassPlayer {
  static const int _bassAttribFreq = 1;
  static const int _bassDataFft4096 = 0x80000004;
  static const int _bassDataFftRemoveDc = 0x40;
  static const int _bassWasapiBuffer = 4;
  static const int _bassWasapiAutoFormat = 2;
  static const int _fftSize = 4096;
  static const int _fftValueCount = _fftSize ~/ 2;
  static const int _bassErrorValue = 0xFFFFFFFF;
  static int _nextNetworkRequestId = 1;

  late final String _bassLibraryPath;
  late final ffi.DynamicLibrary _bassLib;
  late final ffi.DynamicLibrary _bassWasapiLib;
  late final BASS.Bass _bass;
  late final BASS.BassWasapi _bassWasapi;
  BassTempoLibrary? _tempo;
  String? tempoUnavailableReason;
  double _playbackRate = 1.0;
  bool _wasapiInitialized = false;

  double get playbackRate => _playbackRate;
  bool get supportsPlaybackRate => !_freed && _tempo != null;

  String? _fPath;
  bool _sourceIsUrl = false;
  int? _fstream;

  final _outputMode = WasapiOutputMode();

  /// Current decoder/output mode. Configure this before loading a source;
  /// live changes go through the transactional [useExclusiveMode] method.
  bool get wasapiExclusive => _outputMode.active;
  set wasapiExclusive(bool value) => _outputMode.selectBeforePlayback(value);

  Timer? _positionUpdater;
  final _positionStreamController = StreamController<double>.broadcast();
  final _playerStateStreamController =
      StreamController<PlayerState>.broadcast();
  final _spectrumStreamController = StreamController<List<double>>.broadcast();
  final _frequencySpectrumStreamController =
      StreamController<List<double>>.broadcast();
  final List<double> _spectrumLevels = List.filled(7, 0.0);
  final List<double> _frequencySpectrumLevels = List.filled(48, 0.0);
  final ffi.Pointer<ffi.Float> _fftBuffer =
      ffi.malloc.allocate<ffi.Float>(_fftValueCount * ffi.sizeOf<ffi.Float>());
  final ffi.Pointer<ffi.Float> _frequencyBuffer =
      ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
  bool _freed = false;
  Future<void>? _freeFuture;
  int _sourceGeneration = 0;
  final Set<_PendingBassUrlOpen> _pendingUrlOpens = {};

  /// audio's length in seconds
  double get length => _fstream == null
      ? 1.0
      : _bass.BASS_ChannelBytes2Seconds(_fstream!,
          _bass.BASS_ChannelGetLength(_fstream!, BASS.BASS_POS_BYTE));

  /// current position in seconds
  double get position => _fstream == null
      ? 0.0
      : _bass.BASS_ChannelBytes2Seconds(_fstream!,
          _bass.BASS_ChannelGetPosition(_fstream!, BASS.BASS_POS_BYTE));

  PlayerState get playerState {
    if (_fstream == null) {
      return PlayerState.unknown;
    }

    switch (_bass.BASS_ChannelIsActive(_fstream!)) {
      case BASS.BASS_ACTIVE_STOPPED:
        return PlayerState.stopped;
      case BASS.BASS_ACTIVE_PLAYING:
        if (wasapiExclusive) {
          /// wasapi exclusive's channel is a decoding channel,
          /// will be BASS_ACTIVE_PLAYING as long as there is still data to decode.
          /// So here we check BASS_WASAPI_IsStarted to
          /// judge between BASS_ACTIVE_PLAYING and BASS_ACTIVE_PAUSED
          return _bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE
              ? PlayerState.playing
              : PlayerState.paused;
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

  double get volumeDsp {
    if (_fstream == null) return 0;

    final volDsp = ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
    try {
      _bass.BASS_ChannelGetAttribute(
        _fstream!,
        BASS.BASS_ATTRIB_VOLDSP,
        volDsp,
      );
      return volDsp.value;
    } finally {
      ffi.malloc.free(volDsp);
    }
  }

  /// Normal playback updates every 33ms. Successful seeks additionally publish
  /// the actual native position immediately, including while paused.
  Stream<double> get positionStream => _positionStreamController.stream;

  Stream<PlayerState> get playerStateStream =>
      _playerStateStreamController.stream;

  Stream<List<double>> get spectrumStream => _spectrumStreamController.stream;

  Stream<List<double>> get frequencySpectrumStream =>
      _frequencySpectrumStreamController.stream;

  List<double> get spectrumLevels => List.unmodifiable(_spectrumLevels);

  List<double> get frequencySpectrumLevels =>
      List.unmodifiable(_frequencySpectrumLevels);

  Timer _getPositionUpdater() {
    return Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        _positionStreamController.add(position);

        /// check if the channel has completed
        if (playerState == PlayerState.stopped) {
          _resetSpectrum();
          timer.cancel();
          if (identical(_positionUpdater, timer)) {
            _positionUpdater = null;
          }
          _playerStateStreamController.add(PlayerState.completed);
          return;
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
    if (_bass.BASS_ChannelGetAttribute(
          _fstream!,
          _bassAttribFreq,
          _frequencyBuffer,
        ) ==
        BASS.TRUE) {
      sampleRate = _frequencyBuffer.value;
    }
    if (!sampleRate.isFinite || sampleRate <= 0) sampleRate = 48000.0;

    final fft = _fftBuffer.asTypedList(_fftValueCount);
    _updateFrequencyBands(fft, sampleRate);
    final chroma = List.filled(12, 0.0);
    final counts = List.filled(12, 0);
    for (var midi = 33; midi <= 119; midi++) {
      final frequency = 440.0 * math.pow(2.0, (midi - 69) / 12.0);
      final center = (frequency * _fftSize / sampleRate).round();
      if (center < 1 || center >= _fftValueCount) continue;

      var magnitude = 0.0;
      final start = math.max(1, center - 2);
      final end = math.min(_fftValueCount - 1, center + 2);
      for (var bin = start; bin <= end; bin++) {
        magnitude = math.max(magnitude, fft[bin].toDouble());
      }
      final pitchClass = midi % 12;
      chroma[pitchClass] += math.sqrt(math.max(0.0, magnitude));
      counts[pitchClass]++;
    }
    for (var i = 0; i < chroma.length; i++) {
      if (counts[i] > 0) chroma[i] /= counts[i];
    }

    final tones = <double>[
      chroma[0] + chroma[1] * 0.5,
      chroma[2] + (chroma[1] + chroma[3]) * 0.5,
      chroma[4] + chroma[3] * 0.5,
      chroma[5] + chroma[6] * 0.5,
      chroma[7] + (chroma[6] + chroma[8]) * 0.5,
      chroma[9] + (chroma[8] + chroma[10]) * 0.5,
      chroma[11] + chroma[10] * 0.5,
    ];

    for (var i = 0; i < _spectrumLevels.length; i++) {
      var target = (tones[i] * 3.2).clamp(0.0, 1.0).toDouble();
      if (target < 0.025) target = 0.0;
      final smoothing = target > _spectrumLevels[i] ? 0.58 : 0.14;
      _spectrumLevels[i] += (target - _spectrumLevels[i]) * smoothing;
    }
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

  void _updateFrequencyBands(Float32List fft, double sampleRate) {
    const minimumFrequency = 40.0;
    const maximumFrequency = 16000.0;
    const ratio = maximumFrequency / minimumFrequency;
    for (var band = 0; band < _frequencySpectrumLevels.length; band++) {
      final low = minimumFrequency *
          math.pow(ratio, band / _frequencySpectrumLevels.length);
      final high = minimumFrequency *
          math.pow(ratio, (band + 1) / _frequencySpectrumLevels.length);
      final start = (low * _fftSize / sampleRate)
          .floor()
          .clamp(1, _fftValueCount - 1)
          .toInt();
      final end = (high * _fftSize / sampleRate)
          .ceil()
          .clamp(start + 1, _fftValueCount)
          .toInt();
      var peak = 0.0;
      for (var bin = start; bin < end; bin++) {
        peak = math.max(peak, fft[bin].toDouble());
      }
      var target =
          math.pow(peak * 11.0, 0.55).toDouble().clamp(0.0, 1.0).toDouble();
      if (target < 0.018) target = 0.0;
      final current = _frequencySpectrumLevels[band];
      final smoothing = target > current ? 0.34 : 0.15;
      _frequencySpectrumLevels[band] += (target - current) * smoothing;
    }
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
  bool get eqActive => _eqFxHandles.isNotEmpty;

  void _setEqFxParams(int fx, int band) {
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
      }
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
      _setEqFxParams(fx, band);
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
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_ALREADY:
          return;
        case BASS.BASS_ERROR_DEVICE:
          throw const FormatException("device is invalid.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException("win is not a valid window handle.");
        case BASS.BASS_ERROR_DRIVER:
          throw const FormatException("There is no available device driver.");
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "Something else has exclusive use of the device.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException(
              "The specified format is not supported by the device. Try changing the freq parameter.");
        case BASS.BASS_ERROR_MEM:
          throw const FormatException("There is insufficient memory.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException(
              "Some other mystery problem! Maybe Something else has exclusive use of the device.");
      }
    }
  }

  void _startDevice() {
    if (_bass.BASS_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _startDevice();
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The app's audio has been interrupted and cannot be resumed yet. (iOS only)");
        case BASS.BASS_ERROR_REINIT:
          throw const FormatException(
              "The device is currently being reinitialized or needs to be.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException(
              "Some other mystery problem! Maybe Something else has exclusive use of the device.");
      }
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
    final previousMode = wasapiExclusive;
    var lastPos = position;
    var wasPlaying = playerState == PlayerState.playing;
    cancelPendingSource();
    final generation = _sourceGeneration;
    if (sourcePath == null) {
      wasapiExclusive = exclusive;
      return true;
    }

    try {
      // Keep the old stream and mode intact until the replacement is open.
      final applied = await _setSource(
        sourcePath,
        isUrl: sourceIsUrl,
        exclusive: exclusive,
        generation: generation,
        onBeforeCommit: () {
          lastPos = position;
          wasPlaying = playerState == PlayerState.playing;
        },
      );
      if (!applied || !_isCurrentSource(generation)) return false;

      setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
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
        _playerStateStreamController.add(playerState);
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
          final restored = await _setSource(sourcePath,
              isUrl: sourceIsUrl,
              exclusive: previousMode,
              generation: generation);
          if (!restored || !_isCurrentSource(generation)) return false;
          setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
          if (lastPos > 0) seek(lastPos);
          if (wasPlaying) start();
          _playerStateStreamController.add(playerState);
          showTextOnSnackBar('输出模式切换失败，已恢复原模式：$err');
        } catch (restoreError, restoreTrace) {
          if (!_isCurrentSource(generation)) return false;
          LOGGER.e('[restore output mode] $restoreError',
              stackTrace: restoreTrace);
          showTextOnSnackBar('音频设备不可用，原模式也未能恢复；请检查设备后重试');
          _playerStateStreamController.add(playerState);
        }
      } else {
        showTextOnSnackBar('切换音频输出失败，原模式保持不变：$err');
      }
      return false;
    }
  }

  /// Invalidates in-flight opens without disturbing the current stream.
  /// Call this as soon as a newer request begins, including its URL-resolution
  /// phase, rather than waiting until that newer URL has been resolved.
  void cancelPendingSource() {
    _sourceGeneration += 1;
    if (_pendingUrlOpens.isEmpty) return;

    final cancelStream = _bassStreamCancel;
    if (cancelStream == null) return;
    for (final request in _pendingUrlOpens) {
      request.cancel(cancelStream);
    }
  }

  bool _isCurrentSource(int generation) =>
      !_freed && generation == _sourceGeneration;

  /// Opens the new source before replacing the current stream. Local files are
  /// still opened synchronously; only the blocking URL open runs in an isolate.
  /// Returns false when a newer request or shutdown cancels this request.
  Future<bool> setSource(String path, {bool isUrl = false}) {
    if (_freed) return Future.value(false);
    cancelPendingSource();
    return _setSource(
      path,
      isUrl: isUrl,
      exclusive: _outputMode.preferred,
      generation: _sourceGeneration,
    );
  }

  Future<bool> _setSource(
    String source, {
    required bool isUrl,
    required bool exclusive,
    required int generation,
    void Function()? onBeforeCommit,
  }) async {
    const fileFlags =
        BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT | BASS.BASS_ASYNCFILE;
    // On-demand tracks need the downloaded data retained for seek/loop.
    // BASS may still apply BLOCK itself for unknown-length/live streams.
    const urlFlags = BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT;
    var flags = isUrl ? urlFlags : fileFlags;
    if (exclusive || _tempo != null) flags |= BASS.BASS_STREAM_DECODE;

    var uncommittedHandle = 0;
    _PendingBassUrlOpen? pending;
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
        uncommittedHandle = _openLocalSource(source, flags);
      }

      if (!_isCurrentSource(generation)) return false;
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
      onBeforeCommit?.call();
      freeFStream();
      _outputMode.commitStream(exclusive);
      _fstream = uncommittedHandle;
      uncommittedHandle = 0; // ownership has moved to the active stream
      _fPath = source;
      _sourceIsUrl = isUrl;
      if (_eqEnabled) _applyEqToStream();
      return true;
    } catch (_) {
      if (!_isCurrentSource(generation)) return false;
      rethrow;
    } finally {
      try {
        // Even an already cancelled native call can succeed just before its
        // cancellation arrives. Such late handles must never replace new audio.
        if (uncommittedHandle != 0) _bass.BASS_StreamFree(uncommittedHandle);
      } finally {
        if (pending != null) {
          _pendingUrlOpens.remove(pending);
          pending.complete();
        }
      }
    }
  }

  int _openLocalSource(String source, int flags) {
    final pointer = source.toNativeUtf16().cast<ffi.Void>();
    try {
      var handle =
          _bass.BASS_StreamCreateFile(BASS.FALSE, pointer, 0, 0, flags);
      var errorCode = handle == 0 ? _bass.BASS_ErrorGetCode() : 0;
      if (handle == 0 && errorCode == BASS.BASS_ERROR_INIT) {
        _bassInit();
        handle = _bass.BASS_StreamCreateFile(BASS.FALSE, pointer, 0, 0, flags);
        errorCode = handle == 0 ? _bass.BASS_ErrorGetCode() : 0;
      }
      if (handle == 0) throw _sourceOpenException(errorCode, isUrl: false);
      return handle;
    } finally {
      ffi.malloc.free(pointer);
    }
  }

  static FormatException _sourceOpenException(int code, {required bool isUrl}) {
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
    return FormatException(message);
  }

  /// [BASS_ATTRIB_VOLDSP] attribute does have direct effect on decoding/recording channels.
  void setVolumeDsp(double volume) {
    if (_fstream == null) return;

    if (_bass.BASS_ChannelSetAttribute(
          _fstream!,
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
    if (_fstream != null) _positionStreamController.add(position);
    return true;
  }

  void _bassWasapiInit() {
    if (_wasapiInitialized) return;
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
          ffi.Pointer<ffi.Void>.fromAddress(_fstream!),
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
      throw FormatException(reason);
    }
    _wasapiInitialized = true;
  }

  void _start_wasapiExclusive() {
    _bassWasapiInit();

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
    _playerStateStreamController.add(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  /// start/resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void start() {
    if (_fstream == null) return;

    _positionUpdater?.cancel();

    if (wasapiExclusive) {
      return _start_wasapiExclusive();
    }
    if (_bass.BASS_ChannelStart(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played.");
        case BASS.BASS_ERROR_START:
          _startDevice();
          start();
          break;
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  void _pause_wasapiExclusive() {
    if (_bassWasapi.BASS_WASAPI_Stop(BASS.FALSE) == BASS.TRUE) {
      _playerStateStreamController.add(playerState);
      _positionUpdater?.cancel();
    }
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
          throw const FormatException("The channel is not playing.");
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater?.cancel();
    _resetSpectrum();
  }

  /// set channel's position to given [position]
  /// don't check if the position is valid.
  ///
  /// do nothing if [setSource] hasn't been called
  void seek(double position) {
    if (_fstream == null) return;

    if (wasapiExclusive && _wasapiInitialized) {
      seekWasapiOutput(
        wasPlaying: playerState == PlayerState.playing,
        flush: () {
          if (_bassWasapi.BASS_WASAPI_Stop(BASS.TRUE) == BASS.FALSE) {
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
    _positionStreamController.add(this.position);
  }

  void _seekNative(double position) {
    if (_bass.BASS_ChannelSetPosition(
          _fstream!,
          _bass.BASS_ChannelSeconds2Bytes(_fstream!, position),
          BASS.BASS_POS_BYTE,
        ) ==
        0) {
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

    _positionUpdater?.cancel();
    _positionUpdater = null;
    if (wasapiExclusive) {
      _bassWasapi.BASS_WASAPI_Stop(BASS.TRUE);
      _bassWasapi.BASS_WASAPI_Free();
    }
    _wasapiInitialized = false;

    _eqFxHandles.clear();
    final handle = _fstream!;
    _fstream = null;
    _fPath = null;
    _sourceIsUrl = false;
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

  /// Frees all resources used by the output device,
  /// including all its samples, streams and MOD musics.
  ///
  /// Also free the bass.dll.
  Future<void> free() => _freeFuture ??= _free();

  Future<void> _free() async {
    _freed = true;
    cancelPendingSource();

    _positionUpdater?.cancel();
    _positionUpdater = null;
    freeFStream();
    // StreamCancel only signals cancellation. Keep BASS and its device loaded
    // until every worker has returned and its uncommitted handle has been freed.
    await Future.wait([
      for (final request in _pendingUrlOpens) request.finished.future,
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

    _bassWasapiLib.close();
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
