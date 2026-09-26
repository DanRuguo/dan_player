import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart' as bass_api;
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

// Explicit packaged-runtime regression. Only BASS's no-sound device and
// generated PCM are used; no physical output or user files/settings are opened.
class _MixerProbe {
  _MixerProbe(String directory) {
    bassLibrary = ffi.DynamicLibrary.open(path.join(directory, 'bass.dll'));
    mixLibrary = ffi.DynamicLibrary.open(path.join(directory, 'bassmix.dll'));
    bass = bass_api.Bass(bassLibrary);
    mix = BassMixLibrary.open(path.join(directory, 'bassmix.dll'));
    getData = bassLibrary.lookupFunction<
        ffi.Uint32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Uint32),
        int Function(int, ffi.Pointer<ffi.Void>, int)>('BASS_ChannelGetData');
    expect(
        bass.BASS_Init(0, 48000, 0, ffi.nullptr, ffi.nullptr), bass_api.TRUE);
    expect(mix.version, 0x02040d00,
        reason: 'Exercise the reviewed BASSmix 2.4.13 runtime.');
    mixer = mix.createStream(
      48000,
      2,
      bass_api.BASS_SAMPLE_FLOAT |
          bass_api.BASS_STREAM_DECODE |
          BassMixLibrary.nonstop |
          BassMixLibrary.resume,
    );
    expect(mixer, isNonZero);
  }

  late final ffi.DynamicLibrary bassLibrary;
  late final ffi.DynamicLibrary mixLibrary;
  late final bass_api.Bass bass;
  late final BassMixLibrary mix;
  late final int mixer;
  late final int Function(int, ffi.Pointer<ffi.Void>, int) getData;
  final sources = <int>[];
  final buffers = <ffi.Pointer<ffi.Uint8>>[];

  int addWave(List<double> channels, {int rate = 48000, bool matrix = false}) {
    final frames = rate * 2;
    final bytes = Uint8List(44 + frames * channels.length * 2);
    final data = ByteData.sublistView(bytes);
    void text(int offset, String value) =>
        bytes.setRange(offset, offset + value.length, ascii.encode(value));
    text(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    text(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels.length, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * channels.length * 2, Endian.little);
    data.setUint16(32, channels.length * 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, bytes.length - 44, Endian.little);
    for (var frame = 0; frame < frames; frame++) {
      for (var channel = 0; channel < channels.length; channel++) {
        data.setInt16(44 + (frame * channels.length + channel) * 2,
            (channels[channel] * 32768).round(), Endian.little);
      }
    }
    final memory = calloc<ffi.Uint8>(bytes.length);
    buffers.add(memory);
    memory.asTypedList(bytes.length).setAll(0, bytes);
    final source = bass.BASS_StreamCreateFile(
      bass_api.TRUE,
      memory.cast(),
      0,
      bytes.length,
      bass_api.BASS_STREAM_DECODE | bass_api.BASS_SAMPLE_FLOAT,
    );
    expect(source, isNonZero, reason: 'BASS ${bass.BASS_ErrorGetCode()}');
    sources.add(source);
    if (matrix) {
      final add = mixLibrary.lookupFunction<
          ffi.Int32 Function(ffi.Uint32, ffi.Uint32, ffi.Uint32),
          int Function(int, int, int)>('BASS_Mixer_StreamAddChannel');
      expect(add(mixer, source, 0x10000 | BassMixLibrary.channelPaused),
          bass_api.TRUE);
    } else {
      expect(mix.addChannel(mixer, source), isTrue);
    }
    return source;
  }

  List<double> read([int frames = 2048]) {
    final output = calloc<ffi.Float>(frames * 2);
    try {
      expect(getData(mixer, output.cast(), frames * 8), frames * 8,
          reason: 'BASS ${bass.BASS_ErrorGetCode()}');
      final values = output.asTypedList(frames * 2).toList();
      expect(
          values.every((value) => value.isFinite && value.abs() <= 1), isTrue);
      return values;
    } finally {
      calloc.free(output);
    }
  }

  void close() {
    bass.BASS_StreamFree(mixer);
    for (final source in sources) {
      bass.BASS_StreamFree(source);
    }
    bass.BASS_Free();
    for (final buffer in buffers) {
      calloc.free(buffer);
    }
    mix.close();
    mixLibrary.close();
    bassLibrary.close();
  }
}

void main() {
  final configured = Platform.environment['DAN_PLAYER_BASS_RUNTIME'];
  final nativeSkip = !Platform.isWindows || configured == null
      ? 'Set DAN_PLAYER_BASS_RUNTIME to the verified packaged BASS directory.'
      : false;

  _MixerProbe probe() {
    final directory = path.normalize(path.absolute(configured!));
    final repo = Directory.current.absolute.path;
    final workspaceTool = path.join(path.dirname(repo), 'tool');
    final ciTool = path.join(repo, 'tool');
    if (!path.isWithin(workspaceTool, directory) &&
        !path.isWithin(ciTool, directory)) {
      throw StateError(
          'Use a dedicated workspace tool runtime, never user data.');
    }
    final result = _MixerProbe(directory);
    addTearDown(result.close);
    return result;
  }

  test('reviewed mixer retains resampling, pause, seek and resident identity',
      () {
    final p = probe();
    final identity = p.mixer;
    for (final rate in [44100, 48000]) {
      final source = p.addWave([.25, .125], rate: rate);
      final position = p.bass.BASS_ChannelSeconds2Bytes(source, .25);
      expect(
          p.mix.setChannelPosition(source, position,
              bass_api.BASS_POS_BYTE | BassMixLibrary.positionMixerReset),
          isTrue);
      p.read();
      expect(
          p.mix.getChannelPosition(source, bass_api.BASS_POS_BYTE), position);
      expect(p.mix.setChannelPaused(source, false),
          isNot(BassMixLibrary.errorValue));
      final values = p.read();
      expect(values[values.length - 2], closeTo(.25, .002));
      expect(values.last, closeTo(.125, .002));
      expect(p.mix.getChannelPosition(source, bass_api.BASS_POS_BYTE),
          greaterThan(position));
      expect(p.mix.setChannelPaused(source, true),
          isNot(BassMixLibrary.errorValue));
      final paused = p.mix.getChannelPosition(source, bass_api.BASS_POS_BYTE);
      expect(p.read().every((value) => value == 0), isTrue);
      expect(p.mix.getChannelPosition(source, bass_api.BASS_POS_BYTE), paused);
      expect(p.mix.removeChannel(source), isTrue);
      expect(p.mixer, identity);
    }
  }, skip: nativeSkip);

  test('six channel downmix retains stereo routing and balanced center energy',
      () {
    final p = probe();
    for (final input in [0, 1, 2]) {
      final channels = List<double>.filled(6, 0)..[input] = .25;
      final source = p.addWave(channels);
      expect(p.mix.setChannelPaused(source, false),
          isNot(BassMixLibrary.errorValue));
      final values = p.read();
      final left = values[values.length - 2];
      final right = values.last;
      if (input == 0) {
        expect(left, greaterThan(.05));
        expect(right.abs(), lessThan(.001));
      } else if (input == 1) {
        expect(right, greaterThan(.05));
        expect(left.abs(), lessThan(.001));
      } else {
        expect(left, greaterThan(.05));
        expect(left, closeTo(right, .001));
      }
      expect(p.mix.removeChannel(source), isTrue);
    }
  }, skip: nativeSkip);

  test('default matrix ramp converges to new routing without invalid samples',
      () {
    final p = probe();
    final source = p.addWave([.25, .125], matrix: true);
    expect(p.mix.setChannelPaused(source, false),
        isNot(BassMixLibrary.errorValue));
    final before = p.read();
    expect(before[before.length - 2], closeTo(.25, .001));
    expect(before.last, closeTo(.125, .001));
    final setMatrix = p.mixLibrary.lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Pointer<ffi.Float>),
        int Function(
            int, ffi.Pointer<ffi.Float>)>('BASS_Mixer_ChannelSetMatrix');
    final matrix = calloc<ffi.Float>(4);
    try {
      matrix.asTypedList(4).setAll(0, [0, 1, 1, 0]);
      expect(setMatrix(source, matrix), bass_api.TRUE);
      final after = p.read();
      expect(after[after.length - 2], closeTo(.125, .001));
      expect(after.last, closeTo(.25, .001));
      expect(after.every((value) => value >= .124 && value <= .251), isTrue);
    } finally {
      calloc.free(matrix);
    }
  }, skip: nativeSkip);

  test('stalled push source resumes with finite ramp and keeps the same mixer',
      () {
    final p = probe();
    final createPush = p.bassLibrary.lookupFunction<
        ffi.Uint32 Function(ffi.Uint32, ffi.Uint32, ffi.Uint32,
            ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>),
        int Function(int, int, int, ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>)>('BASS_StreamCreate');
    final put = p.bassLibrary.lookupFunction<
        ffi.Uint32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Uint32),
        int Function(int, ffi.Pointer<ffi.Void>, int)>('BASS_StreamPutData');
    final source = createPush(
        48000,
        2,
        bass_api.BASS_SAMPLE_FLOAT | bass_api.BASS_STREAM_DECODE,
        ffi.Pointer<ffi.Void>.fromAddress(-1),
        ffi.nullptr);
    expect(source, isNonZero);
    p.sources.add(source);
    expect(p.mix.addChannel(p.mixer, source, paused: false), isTrue);
    final pcm = calloc<ffi.Float>(8192);
    try {
      pcm.asTypedList(8192).fillRange(0, 8192, .25);
      expect(put(source, pcm.cast(), 1024 * 8), 1024 * 8);
      final first = p.read();
      expect(first.any((value) => value > .1), isTrue);
      expect(p.read().every((value) => value == 0), isTrue);
      expect(p.mix.channelIsActive(source), bass_api.BASS_ACTIVE_STALLED);
      final identity = p.mixer;
      expect(put(source, pcm.cast(), 4096 * 8), 4096 * 8);
      final resumed = p.read();
      expect(resumed.last, closeTo(.25, .001));
      expect(resumed.first, lessThan(.05),
          reason: 'Stall recovery should ramp into the constant PCM signal.');
      expect(resumed.every((value) => value >= 0 && value <= .252), isTrue,
          reason: 'resumed range ${resumed.reduce((a, b) => a < b ? a : b)}'
              '..${resumed.reduce((a, b) => a > b ? a : b)}');
      expect(p.mix.channelIsActive(source), bass_api.BASS_ACTIVE_PLAYING);
      expect(p.mixer, identity);
    } finally {
      calloc.free(pcm);
    }
  }, skip: nativeSkip);
}
