// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dan_player/app_preference.dart';
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

class BassPlayer {
  static const int _bassAttribFreq = 1;
  static const int _bassDataFft4096 = 0x80000004;
  static const int _bassDataFftRemoveDc = 0x40;
  static const int _bassWasapiBuffer = 4;
  static const int _fftSize = 4096;
  static const int _fftValueCount = _fftSize ~/ 2;
  static const int _bassErrorValue = 0xFFFFFFFF;

  late final ffi.DynamicLibrary _bassLib;
  late final ffi.DynamicLibrary _bassWasapiLib;
  late final BASS.Bass _bass;
  late final BASS.BassWasapi _bassWasapi;

  String? _fPath;
  int? _fstream;

  /// 是否启用 wasapi 独占模式
  bool wasapiExclusive = false;

  Timer? _positionUpdater;
  final _positionStreamController = StreamController<double>.broadcast();
  final _playerStateStreamController =
      StreamController<PlayerState>.broadcast();
  final _spectrumStreamController = StreamController<List<double>>.broadcast();
  final List<double> _spectrumLevels = List.filled(7, 0.0);
  final ffi.Pointer<ffi.Float> _fftBuffer =
      ffi.malloc.allocate<ffi.Float>(_fftValueCount * ffi.sizeOf<ffi.Float>());
  final ffi.Pointer<ffi.Float> _frequencyBuffer =
      ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
  bool _freed = false;

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

  /// update every 33ms
  Stream<double> get positionStream => _positionStreamController.stream;

  Stream<PlayerState> get playerStateStream =>
      _playerStateStreamController.stream;

  Stream<List<double>> get spectrumStream => _spectrumStreamController.stream;

  List<double> get spectrumLevels => List.unmodifiable(_spectrumLevels);

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

        if (_spectrumStreamController.hasListener) {
          _spectrumStreamController.add(_updateSpectrum());
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
    return List.unmodifiable(_spectrumLevels);
  }

  List<double> _resetSpectrum({bool emit = true}) {
    for (var i = 0; i < _spectrumLevels.length; i++) {
      _spectrumLevels[i] = 0.0;
    }
    final result = List<double>.unmodifiable(_spectrumLevels);
    if (emit && !_spectrumStreamController.isClosed) {
      _spectrumStreamController.add(result);
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
    final bassLibPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "bass.dll",
    );
    _bassLib = ffi.DynamicLibrary.open(bassLibPath);
    _bass = BASS.Bass(_bassLib);

    final bassWasapiLibPath = path.join(
      path.dirname(Platform.resolvedExecutable),
      "BASS",
      "basswasapi.dll",
    );
    _bassWasapiLib = ffi.DynamicLibrary.open(bassWasapiLibPath);
    _bassWasapi = BASS.BassWasapi(_bassWasapiLib);

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

  /// true: 操作成功；false: 操作失败
  bool useExclusiveMode(bool exclusive) {
    if (exclusive == wasapiExclusive) return true;

    final prevState = wasapiExclusive;
    final sourcePath = _fPath;
    final lastPos = position;
    final wasPlaying = playerState == PlayerState.playing;
    try {
      _positionUpdater?.cancel();
      freeFStream();
      wasapiExclusive = exclusive;
      if (sourcePath != null) {
        setSource(sourcePath);
        setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
        seek(lastPos);
        if (wasPlaying) {
          start();
        } else {
          _playerStateStreamController.add(playerState);
        }
      }
      return true;
    } catch (err) {
      LOGGER.e("[use exclusive mode] $err");
      showTextOnSnackBar(err.toString());
    }

    try {
      freeFStream();
      wasapiExclusive = prevState;
      if (sourcePath != null) {
        setSource(sourcePath);
        setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
        seek(lastPos);
        if (wasPlaying) start();
      }
    } catch (rollbackError, trace) {
      LOGGER.e(
        "[use exclusive mode rollback] $rollbackError",
        stackTrace: trace,
      );
    }
    return false;
  }

  /// if setSource has been called once,
  /// it will pause current channel and free current stream.
  void setSource(String path) {
    if (_fstream != null) {
      _positionUpdater?.cancel();
      _resetSpectrum();
      freeFStream();
    }
    final pathPointer = path.toNativeUtf16() as ffi.Pointer<ffi.Void>;

    /// 设置 flags 为 BASS_UNICODE 才可以找到文件。
    const flags =
        BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT | BASS.BASS_ASYNCFILE;
    const exclusiveFlags = flags | BASS.BASS_STREAM_DECODE;
    late final int handle;
    try {
      handle = _bass.BASS_StreamCreateFile(
        BASS.FALSE,
        pathPointer,
        0,
        0,
        wasapiExclusive ? exclusiveFlags : flags,
      );
    } finally {
      ffi.malloc.free(pathPointer);
    }

    if (handle != 0) {
      _fstream = handle;
      _fPath = path;
      if (_eqEnabled) _applyEqToStream();
    } else {
      _fstream = null;
      _fPath = null;
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          setSource(path);
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The BASS_STREAM_AUTOFREE flag cannot be combined with the BASS_STREAM_DECODE flag.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException(
              "The length must be specified when streaming from memory.");
        case BASS.BASS_ERROR_FILEOPEN:
          throw const FormatException("The file could not be opened.");
        case BASS.BASS_ERROR_FILEFORM:
          throw const FormatException(
              "The file's format is not recognised/supported.");
        case BASS.BASS_ERROR_NOTAUDIO:
          throw const FormatException(
              "The file does not contain audio, or it also contains video and videos are disabled.");
        case BASS.BASS_ERROR_CODEC:
          throw const FormatException(
              "The file uses a codec that is not available/supported. This can apply to WAV and AIFF files.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException("The sample format is not supported.");
        case BASS.BASS_ERROR_SPEAKER:
          throw const FormatException(
              "The specified SPEAKER flags are invalid.");
        case BASS.BASS_ERROR_MEM:
          throw const FormatException("There is insufficient memory.");
        case BASS.BASS_ERROR_NO3D:
          throw const FormatException("Could not initialize 3D support.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
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

  void _bassWasapiInit() {
    if (_bassWasapi.BASS_WASAPI_Init(
          -1,
          0,
          0,
          BASS.BASS_WASAPI_EXCLUSIVE |
              BASS.BASS_WASAPI_EVENT |
              _bassWasapiBuffer,
          0.05,
          0,
          ffi.Pointer<BASS.WASAPIPROC>.fromAddress(-1),
          ffi.Pointer<ffi.Void>.fromAddress(_fstream!),
        ) ==
        BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_WASAPI:
          throw const FormatException("WASAPI is not available.");
        case BASS.BASS_ERROR_DEVICE:
          throw const FormatException("device is invalid.");
        case BASS.BASS_ERROR_ALREADY:
          _bassWasapi.BASS_WASAPI_Free();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Exclusive mode and/or event-driven buffering is unavailable on the device, or WASAPIPROC_PUSH is unavailable on input devices and when using event-driven buffering.");
        case BASS.BASS_ERROR_DRIVER:
          throw const FormatException("The driver could not be initialized.");
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException(
              "The BASS channel handle in user is invalid, or not of the required type.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException(
              "The specified format (or that of the BASS channel) is not supported by the device. If the BASS_WASAPI_AUTOFORMAT flag was specified, no other format could be found either.");
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is already in use, eg. another process may have initialized it in exclusive mode.");
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_WASAPI_BUFFER:
          throw const FormatException(
              "buffer is too large or small (exclusive mode only).");
        case BASS.BASS_ERROR_WASAPI_CATEGORY:
          throw const FormatException(
              "The category/raw mode could not be set.");
        case BASS.BASS_ERROR_WASAPI_DENIED:
          throw const FormatException(
              "Access to the device is denied. This could be due to privacy settings.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  void _start_wasapiExclusive() {
    _bassWasapiInit();

    if (_bassWasapi.BASS_WASAPI_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassWasapiInit();
          _start_wasapiExclusive();
          break;
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
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

    if (_bass.BASS_ChannelSetPosition(
          _fstream!,
          _bass.BASS_ChannelSeconds2Bytes(_fstream!, position),
          BASS.BASS_POS_BYTE,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
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

    _eqFxHandles.clear();
    final handle = _fstream!;
    _fstream = null;
    _fPath = null;
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
  void free() {
    if (_freed) return;
    _freed = true;

    _positionUpdater?.cancel();
    _positionUpdater = null;
    freeFStream();
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
    _bassLib.close();

    _resetSpectrum();
    _playerStateStreamController.close();
    _positionStreamController.close();
    _spectrumStreamController.close();
    ffi.malloc.free(_fftBuffer);
    ffi.malloc.free(_frequencyBuffer);
  }
}
