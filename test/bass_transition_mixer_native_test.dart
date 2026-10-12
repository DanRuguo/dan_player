import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_transition_mixer.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicit NoSound device 0 and generated in-memory PCM. These checks prove
/// native mixed samples, not a physical endpoint, latency or listening quality.
void main() {
  final directory = Platform.environment['DAN_PLAYER_TRANSITION_BASS_DIR'];
  final skip = !Platform.isWindows || directory == null
      ? 'Set DAN_PLAYER_TRANSITION_BASS_DIR for device-0 native sample checks.'
      : false;

  for (final channels in [1, 2]) {
    test(
        'native FIFO joins every sample without a silent frame channels=$channels',
        () {
      final fixture = _Fixture(directory!, channels: channels);
      try {
        fixture.prepare(frames: 4800);
        final prefix = fixture.read(900);
        final mixer = fixture.mixer;
        final scheduled = fixture.schedule();
        expect(scheduled, isNotNull);
        expect(scheduled!.isGapless, isTrue);
        expect(fixture.mix.getChannelMixer(fixture.next), mixer);
        expect(fixture.mix.channelIsActive(fixture.next), 6); // QUEUED
        expect(fixture.api.BASS_ChannelGetPosition(fixture.next, BASS_POS_BYTE),
            0);
        final oldRemainder = fixture.read(3900);
        expect(fixture.api.BASS_ChannelGetPosition(fixture.next, BASS_POS_BYTE),
            0);
        final next = fixture.read(4800);
        fixture.expectSamples([...prefix, ...oldRemainder], .25);
        fixture.expectSamples(next, .5);
        expect(fixture.mixer, mixer);
        expect(fixture.mix.getChannelMixer(fixture.current), 0);
      } finally {
        fixture.close();
      }
    }, skip: skip);
  }

  test('native queued pause does not decode its successor before resumption',
      () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 4800);
      expect(fixture.schedule(), isNotNull);
      expect(fixture.mix.setChannelPaused(fixture.next, true),
          isNot(BassMixLibrary.errorValue));
      fixture.expectSamples(fixture.read(4800), .25);
      expect(fixture.readAvailable(100), isEmpty);
      expect(
          fixture.api.BASS_ChannelGetPosition(fixture.next, BASS_POS_BYTE), 0);
      expect(fixture.mix.setChannelPaused(fixture.next, false),
          isNot(BassMixLibrary.errorValue));
      fixture.expectSamples(fixture.read(4800), .5);
    } finally {
      fixture.close();
    }
  }, skip: skip);

  test('native FIFO follows a rate change using the new source output length',
      () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 4800);
      expect(fixture.schedule(), isNotNull);
      expect(fixture.api.BASS_ChannelSetAttribute(fixture.current, 1, 96000),
          isNot(0));
      fixture.expectSamples(fixture.read(2400), .25);
      fixture.expectSamples(fixture.read(4800), .5);
      expect(fixture.readAvailable(1), isEmpty);
    } finally {
      fixture.close();
    }
  }, skip: skip);

  test(
      'native crossfade uses complementary sample envelopes without a gain boost',
      () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 19200);
      fixture.expectSamples(fixture.read(4800), .25);
      final scheduled = fixture.schedule(fadeSeconds: .1)!;
      expect(scheduled.startByte, 14400 * fixture.frameBytes);
      expect(scheduled.endByte, 19200 * fixture.frameBytes);
      fixture.expectSamples(fixture.read(9600), .25);
      final fade = fixture.read(4800);
      for (var frame = 0; frame < 4800; frame++) {
        final expected = .25 + .25 * frame / 4800;
        for (var channel = 0; channel < fixture.channels; channel++) {
          expect(fade[frame * fixture.channels + channel],
              closeTo(expected, .0002));
        }
      }
      fixture.expectSamples(fixture.read(14400), .5);
      expect(fixture.readAvailable(1), isEmpty);
    } finally {
      fixture.close();
    }
  }, skip: skip);

  test('native audible handoff preserves both fades until the tail completes',
      () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 19200);
      fixture.schedule(fadeSeconds: .1);
      fixture.read(14400);
      fixture.read(1200);
      expect(
          fixture.transitions.complete(
              mixer: fixture.mixer,
              current: fixture.current,
              next: fixture.next),
          isTrue);
      expect(
          fixture.transitions.cancel(
              mixer: fixture.mixer,
              current: fixture.current,
              next: fixture.next),
          isFalse);
      final midpoint = fixture.read(1200);
      expect(midpoint.first, closeTo(.3125, .0002));
      expect(midpoint.last, closeTo(.375, .0002));
      fixture.read(2400);
      fixture.expectSamples(fixture.read(100), .5);
      expect(fixture.transitions.clearEnvelope(fixture.next), isTrue);
      fixture.expectSamples(fixture.read(100), .5);
    } finally {
      fixture.close();
    }
  }, skip: skip);

  for (final duringFade in [false, true]) {
    test(
        'native cancellation removes next and restores current gain duringFade=$duringFade',
        () {
      final fixture = _Fixture(directory!);
      try {
        fixture.prepare(frames: 19200);
        fixture.schedule(fadeSeconds: .1);
        fixture.read(duringFade ? 16800 : 4800);
        expect(
            fixture.transitions.cancel(
                mixer: fixture.mixer,
                current: fixture.current,
                next: fixture.next + 1),
            isFalse);
        expect(fixture.transitions.active, isNotNull);
        expect(
            fixture.transitions.cancel(
                mixer: fixture.mixer,
                current: fixture.current,
                next: fixture.next),
            isTrue);
        expect(fixture.mix.getChannelMixer(fixture.next), 0);
        expect(fixture.transitions.active, isNull);
        fixture.expectSamples(fixture.read(duringFade ? 2400 : 14400), .25);
      } finally {
        fixture.close();
      }
    }, skip: skip);
  }

  test('native cancel then pause and seek cannot leak the staged track', () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 19200);
      fixture.schedule(fadeSeconds: .1);
      fixture.read(4800);
      expect(
          fixture.transitions.cancel(
              mixer: fixture.mixer,
              current: fixture.current,
              next: fixture.next),
          isTrue);
      fixture.mix.setChannelPaused(fixture.current, true);
      expect(fixture.readAvailable(100), isEmpty);
      expect(
          fixture.api.BASS_ChannelGetPosition(fixture.next, BASS_POS_BYTE), 0);
      expect(
          fixture.mix.setChannelPosition(
              fixture.current, 9600 * fixture.frameBytes, BASS_POS_BYTE),
          isTrue);
      fixture.mix.setChannelPaused(fixture.current, false);
      fixture.expectSamples(fixture.read(9600), .25);
      expect(fixture.readAvailable(1), isEmpty);
    } finally {
      fixture.close();
    }
  }, skip: skip);

  test(
      'native failed scheduling rolls back FIFO flags and keeps the current stream',
      () {
    final fixture = _Fixture(directory!);
    try {
      fixture.prepare(frames: 4800);
      final original = fixture.flags(fixture.mixer, 0, 0);
      final failed = fixture.transitions.schedule(
          mixer: fixture.mixer,
          current: fixture.current,
          next: 0x7ffffff0,
          remainingSeconds: () => .1);
      expect(failed, isNull);
      expect(fixture.flags(fixture.mixer, 0, 0), original);
      expect(fixture.transitions.active, isNull);
      fixture.expectSamples(fixture.read(4800), .25);
      expect(fixture.mix.getChannelMixer(fixture.next), 0);
    } finally {
      fixture.close();
    }
  }, skip: skip);
}

class _Fixture {
  _Fixture(String directory, {this.channels = 2}) {
    library = DynamicLibrary.open('$directory/bass.dll');
    api = Bass(library);
    if (api.BASS_Init(0, 48000, 0, nullptr, nullptr) == 0) {
      library.close();
      throw StateError('NoSound BASS initialization failed');
    }
    try {
      mix = BassMixLibrary.open('$directory/bassmix.dll');
    } catch (_) {
      api.BASS_Free();
      library.close();
      rethrow;
    }
    transitions = BassTransitionMixer(library, mix);
    getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    flags = library.lookupFunction<Uint32 Function(Uint32, Uint32, Uint32),
        int Function(int, int, int)>('BASS_ChannelFlags');
    buffer = calloc<Float>(4096 * channels);
    mixer = mix.createStream(
        48000,
        channels,
        BASS_SAMPLE_FLOAT |
            BASS_STREAM_DECODE |
            BassMixLibrary.resume);
    expect(mixer, isNot(0));
  }

  final int channels;
  int get frameBytes => 4 * channels;
  late final DynamicLibrary library;
  late final Bass api;
  late final BassMixLibrary mix;
  late final BassTransitionMixer transitions;
  late final int Function(int, Pointer<Void>, int) getData;
  late final int Function(int, int, int) flags;
  late final Pointer<Float> buffer;
  late final int mixer;
  late final int current, next;
  late final int frames;
  final _memory = <Pointer<Uint8>>[];

  void prepare({required int frames}) {
    this.frames = frames;
    current = _pcm(frames, 8192);
    next = _pcm(frames, 16384);
    expect(
        mix.addChannel(mixer, current, paused: false, noRampIn: true), isTrue);
  }

  int _pcm(int frames, int value) {
    final bytes = ByteData(44 + frames * channels * 2);
    void text(int at, String value) =>
        bytes.buffer.asUint8List().setAll(at, value.codeUnits);
    text(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, 48000, Endian.little);
    bytes.setUint32(28, 48000 * channels * 2, Endian.little);
    bytes.setUint16(32, channels * 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, frames * channels * 2, Endian.little);
    for (var sample = 0; sample < frames * channels; sample++) {
      bytes.setInt16(44 + sample * 2, value, Endian.little);
    }
    final memory = calloc<Uint8>(bytes.lengthInBytes);
    memory
        .asTypedList(bytes.lengthInBytes)
        .setAll(0, bytes.buffer.asUint8List());
    _memory.add(memory);
    final source = api.BASS_StreamCreateFile(1, memory.cast(), 0,
        bytes.lengthInBytes, BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
    expect(source, isNot(0));
    return source;
  }

  BassTransitionSchedule? schedule({double fadeSeconds = 0}) =>
      transitions.schedule(
          mixer: mixer,
          current: current,
          next: next,
          remainingSeconds: () => api.BASS_ChannelBytes2Seconds(
              current,
              api.BASS_ChannelGetLength(current, BASS_POS_BYTE) -
                  api.BASS_ChannelGetPosition(current, BASS_POS_BYTE)),
          fadeSeconds: fadeSeconds,
          nextDuration: frames / 48000);

  List<double> readAvailable(int frames) {
    final requested = frames.clamp(1, 4096);
    final bytes = getData(mixer, buffer.cast(), requested * frameBytes);
    if (bytes == BassMixLibrary.errorValue || bytes == 0) return [];
    expect(bytes % frameBytes, 0);
    return buffer.asTypedList(bytes ~/ 4).toList();
  }

  List<double> read(int frames) {
    final result = <double>[];
    while (result.length < frames * channels) {
      final chunk = readAvailable(frames - result.length ~/ channels);
      expect(chunk, isNotEmpty,
          reason: 'native output ended before the requested PCM frame');
      result.addAll(chunk);
    }
    expect(result.length, frames * channels);
    return result;
  }

  void expectSamples(List<double> values, double expected) {
    expect(values, isNotEmpty);
    for (var sample = 0; sample < values.length; sample++) {
      expect(values[sample], closeTo(expected, .0002),
          reason: 'PCM sample $sample');
    }
  }

  void close() {
    api.BASS_Free();
    mix.close();
    library.close();
    calloc.free(buffer);
    for (final memory in _memory) {
      calloc.free(memory);
    }
  }
}
