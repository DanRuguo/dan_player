import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// The fixed ten-band EQ uses the already bundled BASS_FX peaking filter.
/// DX8 silently clamps centres above sampleRate / 3 on Windows; use it only
/// within that range when the optional extension is unavailable.
class BassEqualizer {
  BassEqualizer.native(DynamicLibrary library, {required this.peakingAvailable})
      : _setFx = library.lookupFunction<Uint32 Function(Uint32, Uint32, Int32),
            int Function(int, int, int)>('BASS_ChannelSetFX'),
        _removeFx = library.lookupFunction<Int32 Function(Uint32, Uint32),
            int Function(int, int)>('BASS_ChannelRemoveFX'),
        _setParameters = library.lookupFunction<
            Int32 Function(Uint32, Pointer<Void>),
            int Function(int, Pointer<Void>)>('BASS_FXSetParameters');

  static const centers = <double>[
    80,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    12000,
    16000
  ];
  static const maxGainDb = 15.0;
  static const _peakingEffect = 0x10004;
  static const _dx8Effect = 7;

  final bool peakingAvailable;
  final int Function(int, int, int) _setFx;
  final int Function(int, int) _removeFx;
  final int Function(int, Pointer<Void>) _setParameters;
  final _effects = <int, int>{};
  final _applied = List<double?>.filled(centers.length, null);
  int? _stream;
  List<bool> _available =
      List<bool>.unmodifiable(List<bool>.filled(centers.length, true));

  List<bool> get availableBands => _available;
  List<double?> get appliedGains => List<double?>.unmodifiable(_applied);
  bool get active => _effects.isNotEmpty;
  String get implementation => peakingAvailable ? 'peaking' : 'dx8';

  static List<bool> supportFor(int? sampleRate,
          {required bool peakingAvailable}) =>
      List<bool>.unmodifiable(centers.map((center) =>
          sampleRate != null &&
          sampleRate > 0 &&
          (peakingAvailable
              ? center < sampleRate / 2
              : center <= sampleRate / 3)));

  /// Called once on source commit, even while EQ is off. UI reads this cached
  /// mask and never queries native format on a layout/position frame.
  void sourceFormat(int? sampleRate) {
    _available = supportFor(sampleRate, peakingAvailable: peakingAvailable);
  }

  bool apply(int stream, List<double> gains) {
    if (gains.length != centers.length) {
      throw ArgumentError.value(gains.length, 'gains', 'Ten EQ bands required');
    }
    remove();
    _stream = stream;
    for (var band = 0; band < centers.length; band++) {
      if (!_available[band]) continue;
      final effect =
          _setFx(stream, peakingAvailable ? _peakingEffect : _dx8Effect, 0);
      if (effect == 0) {
        remove();
        return false;
      }
      _effects[band] = effect;
      if (!setBandGain(band, gains[band])) {
        remove();
        return false;
      }
    }
    return _effects.isNotEmpty;
  }

  bool setBandGain(int band, double gain) {
    final effect = _effects[band];
    if (effect == null) {
      return true; // Retain the user's unavailable-band value.
    }
    final sanitized =
        gain.isFinite ? gain.clamp(-maxGainDb, maxGainDb).toDouble() : 0.0;
    final bool success;
    if (peakingAvailable) {
      final parameters = calloc<BassPeakingEq>();
      try {
        parameters.ref
          ..band = 0
          ..bandwidth = 1 // Existing 12-semitone width, expressed in octaves.
          ..q = 0
          ..center = centers[band]
          ..gain = sanitized
          ..channel = -1;
        success = _setParameters(effect, parameters.cast()) != 0;
      } finally {
        calloc.free(parameters);
      }
    } else {
      final parameters = calloc<BassDx8Eq>();
      try {
        parameters.ref
          ..center = centers[band]
          ..bandwidth = 12
          ..gain = sanitized;
        success = _setParameters(effect, parameters.cast()) != 0;
      } finally {
        calloc.free(parameters);
      }
    }
    if (success) _applied[band] = sanitized;
    return success;
  }

  void remove() {
    final stream = _stream;
    if (stream != null) {
      for (final effect in _effects.values) {
        _removeFx(stream, effect);
      }
    }
    _stream = null;
    _effects.clear();
    _applied.fillRange(0, _applied.length, null);
  }

  /// StreamFree owns native destruction; discard its ledger before that call.
  void forgetSource() {
    _stream = null;
    _effects.clear();
    _applied.fillRange(0, _applied.length, null);
    _available =
        List<bool>.unmodifiable(List<bool>.filled(centers.length, true));
  }
}

/// ABI verified against the bundled BASS_FX 2.4.12.6 C/bass_fx.h.
final class BassPeakingEq extends Struct {
  @Int32()
  external int band;
  @Float()
  external double bandwidth;
  @Float()
  external double q;
  @Float()
  external double center;
  @Float()
  external double gain;
  @Int32()
  external int channel;
}

final class BassDx8Eq extends Struct {
  @Float()
  external double center;
  @Float()
  external double bandwidth;
  @Float()
  external double gain;
}
