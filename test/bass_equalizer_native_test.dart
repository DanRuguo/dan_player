import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_equalizer.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:dan_player/src/bass/bass_volume.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicit device 0 and generated PCM. This exercises the same EQ controller
/// as BassPlayer, without an output endpoint, user files, or listening claims.
void main() {
  final bassDir = Platform.environment['DAN_PLAYER_EQ_BASS_DIR'];
  final fxDll = Platform.environment['DAN_PLAYER_EQ_FX_DLL'];
  final skip = !Platform.isWindows || bassDir == null || fxDll == null
      ? 'Set DAN_PLAYER_EQ_BASS_DIR and DAN_PLAYER_EQ_FX_DLL for NoSound EQ.'
      : false;
  late _Fixture native;
  setUp(() {
    if (skip == false) native = _Fixture(bassDir!, fxDll!);
  });
  tearDown(() {
    if (skip == false) native.close();
  });

  test('native 44.1k true 16k response on raw, tempo and mixer paths', () {
    for (final pipeline in [(false, false), (true, false), (true, true)]) {
      final gains = List<double>.filled(10, 0)..[9] = 6;
      final at16k = native.response(44100, 16000, gains,
          tempo: pipeline.$1, mixer: pipeline.$2);
      expect(at16k, closeTo(6, .015), reason: 'pipeline=$pipeline');
      // DX8 reports 16k in its parameters but peaks at 14.7k. This strict
      // shoulder check also catches that original silent centre clamp.
      final at14700 = native.response(44100, 14700, gains,
          tempo: pipeline.$1, mixer: pipeline.$2);
      expect(at14700, closeTo(5.7863, .015));
      expect(at14700, lessThan(5.9));
    }
  }, skip: skip);

  test('native low-rate unavailable bands produce no aliased gain', () {
    for (final frequency in [8000, 11025, 16000, 22050, 32000]) {
      final support =
          BassEqualizer.supportFor(frequency, peakingAvailable: true);
      final gains = [for (final available in support) available ? 0.0 : 6.0];
      final saved = List<double>.of(gains);
      final db = native.response(frequency, frequency / 3, gains,
          tempo: true, mixer: true);
      expect(db, closeTo(0, .015), reason: 'frequency=$frequency');
      expect(gains, saved);
    }
  }, skip: skip);

  test('native low-band curve and 48k high-band curve retain prior width', () {
    for (final sample in [
      (48000, 500.0, 1.1374),
      (48000, 2000.0, 1.1277),
      (8000, 500.0, 1.2159),
      (8000, 2000.0, .8483)
    ]) {
      final gains = List<double>.filled(10, 0)..[4] = 6;
      expect(native.response(sample.$1, sample.$2, gains),
          closeTo(sample.$3, .015));
    }
    final gains = List<double>.filled(10, 0)..[9] = 6;
    expect(native.response(48000, 18000, gains), closeTo(5.2749, .015));
  }, skip: skip);

  test('native remove, live edit, reapply and source format recovery', () {
    final gains = List<double>.filled(10, 0)..[4] = 6;
    final stream = native.open(8000, 1000, tempo: true);
    final eq = BassEqualizer.native(native.library, peakingAvailable: true)
      ..sourceFormat(8000);
    try {
      expect(eq.apply(stream, gains), true);
      expect(eq.active, true);
      expect(eq.appliedGains[9], null);
      expect(eq.setBandGain(4, 3), true);
      expect(native.relativeDb(stream, 8000, 1000), closeTo(3, .015));
      eq.remove();
      native.rewind(stream);
      expect(eq.active, false);
      expect(native.relativeDb(stream, 8000, 1000), closeTo(0, .015));
      native.rewind(stream);
      expect(eq.apply(stream, gains), true);
      expect(native.relativeDb(stream, 8000, 1000), closeTo(6, .015));
      eq.forgetSource();
    } finally {
      native.api.BASS_StreamFree(stream);
    }
    final next = native.open(44100, 16000, tempo: true);
    final restored = List<double>.filled(10, 0)..[9] = 6;
    try {
      eq.sourceFormat(44100);
      expect(eq.apply(next, restored), true);
      expect(eq.availableBands.last, true);
      expect(eq.appliedGains.last, 6);
      expect(native.relativeDb(next, 44100, 16000), closeTo(6, .015));
    } finally {
      eq.remove();
      native.api.BASS_StreamFree(next);
    }
  }, skip: skip);

  test('native DX8 fallback skips clamped bands but keeps valid low EQ', () {
    for (final frequency in [8000, 44100, 48000]) {
      final stream = native.open(frequency, 1000);
      final eq = BassEqualizer.native(native.library, peakingAvailable: false)
        ..sourceFormat(frequency);
      final gains = List<double>.filled(10, 0)..[4] = 6;
      if (frequency < 48000) gains[9] = 6;
      try {
        expect(eq.apply(stream, gains), true);
        expect(eq.availableBands.last, frequency == 48000);
        expect(eq.appliedGains.last, frequency == 48000 ? 0 : null);
        expect(native.relativeDb(stream, frequency, 1000), closeTo(6, .015));
        expect(gains[9], frequency < 48000 ? 6 : 0);
      } finally {
        eq.remove();
        native.api.BASS_StreamFree(stream);
      }
    }
  }, skip: skip);

  test('native EQ preserves one ReplayGain DSP base and post-buffer volume',
      () {
    final gains = List<double>.filled(10, 0)..[9] = 6;
    expect(
        native.response(44100, 16000, gains,
            tempo: true,
            mixer: true,
            volume: .5,
            tags: const ReplayGainTags(trackGainDb: -6),
            preferences: const ReplayGainPreferences(
                mode: ReplayGainMode.track, preventClipping: false)),
        closeTo(-6.0206, .02));
  }, skip: skip);
}

class _Fixture {
  _Fixture(String bassDir, String fxDll) {
    library = DynamicLibrary.open('$bassDir/bass.dll');
    api = Bass(library);
    expect(api.BASS_Init(0, 48000, 0, nullptr, nullptr), isNot(0));
    tempo = BassTempoLibrary.open(fxDll);
    mix = BassMixLibrary.open('$bassDir/bassmix.dll');
    getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    directory = Directory('${Directory.current.parent.path}/tool/qa-local/'
        'research-polish-2606/equalizer/native');
    directory.createSync(recursive: true);
    buffer = calloc<Float>(4096);
  }
  late final DynamicLibrary library;
  late final Bass api;
  late final BassTempoLibrary tempo;
  late final BassMixLibrary mix;
  late final Directory directory;
  late final Pointer<Float> buffer;
  late final int Function(int, Pointer<Void>, int) getData;

  int open(int frequency, double tone, {bool tempo = false}) {
    final file = File('${directory.path}/eq-$frequency-$tone.wav');
    if (!file.existsSync()) {
      final frames = frequency * 2;
      final data = ByteData(44 + frames * 4);
      void text(int offset, String value) =>
          data.buffer.asUint8List().setAll(offset, value.codeUnits);
      text(0, 'RIFF');
      data.setUint32(4, data.lengthInBytes - 8, Endian.little);
      text(8, 'WAVEfmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(22, 2, Endian.little);
      data.setUint32(24, frequency, Endian.little);
      data.setUint32(28, frequency * 4, Endian.little);
      data.setUint16(32, 4, Endian.little);
      data.setUint16(34, 16, Endian.little);
      text(36, 'data');
      data.setUint32(40, frames * 4, Endian.little);
      for (var frame = 0; frame < frames; frame++) {
        final sample =
            (math.sin(2 * math.pi * tone * frame / frequency) * 4096).round();
        data.setInt16(44 + frame * 4, sample, Endian.little);
        data.setInt16(46 + frame * 4, sample, Endian.little);
      }
      file.writeAsBytesSync(data.buffer.asUint8List());
    }
    final filename = file.path.toNativeUtf16();
    late final int raw;
    try {
      raw = api.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
          BASS_UNICODE | BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT);
    } finally {
      calloc.free(filename);
    }
    expect(raw, isNot(0));
    final stream =
        tempo ? this.tempo.createStream(raw, decodingOutput: true) : raw;
    expect(stream, isNot(0));
    return stream;
  }

  void rewind(int stream) =>
      expect(api.BASS_ChannelSetPosition(stream, 0, BASS_POS_BYTE), isNot(0));

  double rms(int stream, int frequency) {
    var seen = 0, count = 0;
    var sum = 0.0;
    while (true) {
      final bytes = getData(stream, buffer.cast(), 4096 * 4);
      if (bytes == 0 || bytes == 0xffffffff) break;
      final samples = buffer.asTypedList(bytes ~/ 4);
      for (final sample in samples) {
        if (++seen > frequency / 2) {
          sum += sample * sample;
          count++;
        }
      }
    }
    expect(count, greaterThan(0));
    expect(sum.isFinite, true);
    return math.sqrt(sum / count);
  }

  double relativeDb(int stream, int frequency, double tone) {
    final dry = open(frequency, tone);
    try {
      return 20 *
          math.log(rms(stream, frequency) / rms(dry, frequency)) /
          math.ln10;
    } finally {
      api.BASS_StreamFree(dry);
    }
  }

  double response(int frequency, double tone, List<double> gains,
      {bool tempo = false,
      bool mixer = false,
      double volume = 1,
      ReplayGainTags tags = const ReplayGainTags(),
      ReplayGainPreferences preferences = const ReplayGainPreferences()}) {
    final stream = open(frequency, tone, tempo: tempo);
    final eq = BassEqualizer.native(library, peakingAvailable: true)
      ..sourceFormat(frequency);
    final out = mixer
        ? mix.createStream(frequency, 2, BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT)
        : stream;
    try {
      final dspBase = BassPlaybackVolume.native(library)
          .initialize(stream, volume, tags, preferences);
      expect(eq.apply(stream, gains), true);
      expect(eq.availableBands,
          BassEqualizer.supportFor(frequency, peakingAvailable: true));
      for (var band = 0; band < gains.length; band++) {
        expect(eq.appliedGains[band],
            eq.availableBands[band] ? gains[band] : null);
      }
      final actualBase = calloc<Float>();
      try {
        expect(api.BASS_ChannelGetAttribute(stream, 19, actualBase), isNot(0));
        expect(actualBase.value, closeTo(dspBase, 1e-6));
      } finally {
        calloc.free(actualBase);
      }
      if (mixer) {
        expect(out, isNot(0));
        expect(mix.addChannel(out, stream, paused: false), true);
      }
      return relativeDb(out, frequency, tone);
    } finally {
      eq.remove();
      if (mixer) {
        mix.removeChannel(stream);
        api.BASS_StreamFree(out);
      }
      api.BASS_StreamFree(stream);
    }
  }

  void close() {
    calloc.free(buffer);
    api.BASS_Free();
    mix.close();
    tempo.close();
    library.close();
  }
}
