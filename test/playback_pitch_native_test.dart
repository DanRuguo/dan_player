import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

const _sampleRate = 44100;
const _sourceSeconds = 8.0;
const _sourceFrequency = 440.0;

/// Optional DSP regression. BASS device 0 renders synthetic PCM without opening
/// a sound card. Set DAN_PLAYER_PITCH_BASS_DIR to the shipped BASS DLL folder.
/// This checks the native attributes and media clock, not BassPlayer lifecycle
/// persistence or listening quality on a physical output device.
void main() {
  final bassDirectory = Platform.environment['DAN_PLAYER_PITCH_BASS_DIR'];
  final skip = !Platform.isWindows || bassDirectory == null
      ? 'Requires an explicit shipped BASS DLL folder; uses NoSound device 0.'
      : false;

  test('native pitch shifts frequency without changing tempo or source clock',
      () async {
    final probe = await _PitchProbe.open(bassDirectory!);
    try {
      for (final rate in [1.0, 1.5]) {
        for (final pitch in [-12.0, -3.0, 0.0, 3.0, 12.0]) {
          final handle = probe.createStream(rate: rate, pitch: pitch);
          try {
            expect(probe.mediaLength(handle), closeTo(_sourceSeconds, 1e-6));
            final samples = probe.readToEnd(handle);
            final duration = samples.length / _sampleRate;
            final frequency = _frequency(samples);
            final expected = _sourceFrequency * math.pow(2, pitch / 12);
            expect(duration, closeTo(_sourceSeconds / rate, 1 / _sampleRate),
                reason: 'Pitch $pitch must preserve rate $rate.');
            expect(frequency, closeTo(expected, 2),
                reason:
                    'Pitch must be measured in semitones, independent of tempo.');
            // Keep the actual DSP measurements in the optional native QA log.
            // ignore: avoid_print
            print('native-pitch rate=$rate pitch=$pitch '
                'frequencyHz=$frequency expectedHz=$expected '
                'frames=${samples.length} mediaLength=${probe.mediaLength(handle)}');
          } finally {
            probe.api.BASS_StreamFree(handle);
          }
        }
      }
    } finally {
      probe.close();
    }
  }, skip: skip);

  test('live native pitch changes preserve seek and the tempo attribute',
      () async {
    final probe = await _PitchProbe.open(bassDirectory!);
    try {
      for (final (initialPitch, pitch) in [
        (0.0, -12.0),
        (0.0, 3.0),
        (-12.0, 12.0),
        (12.0, 0.0),
      ]) {
        final handle = probe.createStream(rate: 1.5, pitch: initialPitch);
        try {
          expect(
              probe.api.BASS_ChannelSetPosition(
                  handle, probe.api.BASS_ChannelSeconds2Bytes(handle, 2), 0),
              isNot(0));
          expect(probe.mediaPosition(handle), closeTo(2, 1 / _sampleRate));
          // Start processing before the change, so it also exercises a live DSP
          // buffer instead of setting an attribute only before the first read.
          final warmBytes = probe.getData(
              handle, probe.buffer.cast(), 4096 * sizeOf<Float>());
          expect(warmBytes, 4096 * sizeOf<Float>());
          final position = probe.api.BASS_ChannelGetPosition(handle, 0);
          expect(
              probe.api.BASS_ChannelSetAttribute(
                  handle, BassTempoLibrary.pitchAttribute, pitch),
              isNot(0));
          expect(probe.api.BASS_ChannelGetPosition(handle, 0), position,
              reason: 'Changing pitch must not relocate the media cursor.');
          expect(probe.attribute(handle, BassTempoLibrary.tempoAttribute), 50);
          expect(
              probe.attribute(handle, BassTempoLibrary.pitchAttribute), pitch);
          expect(probe.mediaLength(handle), closeTo(_sourceSeconds, 1e-6));
          final samples = probe.readToEnd(handle);
          final frequency = _frequency(samples);
          final expected = _sourceFrequency * math.pow(2, pitch / 12);
          expect((samples.length + warmBytes ~/ sizeOf<Float>()) / _sampleRate,
              closeTo((_sourceSeconds - 2) / 1.5, 1 / _sampleRate));
          expect(frequency, closeTo(expected, 2));
          // Keep the actual DSP measurements in the optional native QA log.
          // ignore: avoid_print
          print('native-pitch-seek initialPitch=$initialPitch pitch=$pitch '
              'frequencyHz=$frequency '
              'positionBeforeBytes=$position '
              'warmFrames=${warmBytes ~/ sizeOf<Float>()} '
              'remainingFrames=${samples.length} tempoPercent=50');
        } finally {
          probe.api.BASS_StreamFree(handle);
        }
      }
    } finally {
      probe.close();
    }
  }, skip: skip);
}

double _frequency(List<double> samples) {
  // Exclude the DSP startup/end windows, then measure many positive crossings.
  // Linear interpolation avoids rounding each period to an integer frame.
  final trim = (_sampleRate * 0.4).round();
  final crossings = <double>[];
  expect(samples.every((sample) => sample.isFinite), isTrue);
  for (var i = trim; i < samples.length - trim - 1; i++) {
    final current = samples[i];
    final next = samples[i + 1];
    if (current <= 0 && next > 0) {
      crossings.add(i - current / (next - current));
    }
  }
  expect(crossings.length, greaterThan(100),
      reason: 'The decoder must produce a non-silent, measurable signal.');
  return (crossings.length - 1) *
      _sampleRate /
      (crossings.last - crossings.first);
}

class _PitchProbe {
  _PitchProbe(this.library, this.api, this.tempo, this.filename)
      : buffer = calloc<Float>(4096),
        getData = library.lookupFunction<
            Uint32 Function(Uint32, Pointer<Void>, Uint32),
            int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');

  final DynamicLibrary library;
  final Bass api;
  final BassTempoLibrary tempo;
  final Pointer<Utf16> filename;
  final Pointer<Float> buffer;
  final int Function(int, Pointer<Void>, int) getData;

  static Future<_PitchProbe> open(String directory) async {
    final fixtureDirectory = Directory(
        '${Directory.current.parent.path}/tool/qa-local/playback-pitch/fixtures');
    await fixtureDirectory.create(recursive: true);
    final wav = File('${fixtureDirectory.path}/sine-440hz.wav');
    final frames = (_sourceSeconds * _sampleRate).round();
    final data = ByteData(44 + frames * 2);
    void label(int offset, String value) =>
        data.buffer.asUint8List().setAll(offset, value.codeUnits);
    label(0, 'RIFF');
    data.setUint32(4, data.lengthInBytes - 8, Endian.little);
    label(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _sampleRate, Endian.little);
    data.setUint32(28, _sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    label(36, 'data');
    data.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      data.setInt16(
          44 + i * 2,
          (8191 * math.sin(2 * math.pi * _sourceFrequency * i / _sampleRate))
              .round(),
          Endian.little);
    }
    await wav.writeAsBytes(data.buffer.asUint8List());
    final library = DynamicLibrary.open('$directory/bass.dll');
    final api = Bass(library);
    expect(api.BASS_Init(0, _sampleRate, 0, nullptr, nullptr), isNot(0),
        reason:
            'Native DSP tests use the NoSound device, never a real endpoint.');
    final tempo = BassTempoLibrary.open('$directory/bass_fx.dll');
    return _PitchProbe(library, api, tempo, wav.path.toNativeUtf16());
  }

  int createStream({required double rate, required double pitch}) {
    final raw = api.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
        BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | 0x20000);
    expect(raw, isNot(0));
    final handle = tempo.createStream(raw, decodingOutput: true);
    if (handle == 0) api.BASS_StreamFree(raw);
    expect(handle, isNot(0));
    expect(
        api.BASS_ChannelSetAttribute(
            handle, BassTempoLibrary.tempoAttribute, (rate - 1) * 100),
        isNot(0));
    expect(
        api.BASS_ChannelSetAttribute(
            handle, BassTempoLibrary.pitchAttribute, pitch),
        isNot(0));
    return handle;
  }

  List<double> readToEnd(int handle) {
    final samples = <double>[];
    for (var attempt = 0; attempt < 200; attempt++) {
      final bytes = getData(handle, buffer.cast(), 4096 * sizeOf<Float>());
      if (bytes == 0xffffffff || bytes == 0) return samples;
      expect(bytes % sizeOf<Float>(), 0);
      samples.addAll(buffer.asTypedList(bytes ~/ sizeOf<Float>()));
    }
    fail('The synthetic 8-second native stream did not reach EOF.');
  }

  double mediaLength(int handle) => api.BASS_ChannelBytes2Seconds(
      handle, api.BASS_ChannelGetLength(handle, 0));

  double mediaPosition(int handle) => api.BASS_ChannelBytes2Seconds(
      handle, api.BASS_ChannelGetPosition(handle, 0));

  double attribute(int handle, int key) {
    final value = calloc<Float>();
    try {
      expect(api.BASS_ChannelGetAttribute(handle, key, value), isNot(0));
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  void close() {
    api.BASS_Free();
    malloc.free(filename);
    calloc.free(buffer);
    tempo.close();
    library.close();
  }
}
