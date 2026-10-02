import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_volume.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Real BASS + BASSmix, device 0 and generated PCM; no audio endpoint or
/// Windows volume is opened. The production controller applies both gains.
void main() {
  final runtime = Platform.environment['DAN_PLAYER_REPLAYGAIN_GAIN_BASS_DIR'];
  final unavailable = runtime == null
      ? 'Set DAN_PLAYER_REPLAYGAIN_GAIN_BASS_DIR for actual device-0 decode'
      : false;
  late _Probe probe;
  setUp(() async => probe = await _Probe.open(runtime!));
  tearDown(() async => await probe.close());

  test('native tagged preamp sums before the single peak limit', () {
    const tags = ReplayGainTags(trackGainDb: 12, trackPeak: 1);
    const prefs = ReplayGainPreferences(
        mode: ReplayGainMode.track, preampDb: -12, fallbackGainDb: -24);
    final base = probe.volume.initialize(probe.stream, .8, tags, prefs);
    expect(base, closeTo(1, 1e-12));
    expect(probe.attribute(19), closeTo(base, 1e-6));
    expect(probe.decode(), closeTo(.25 * .8, .0002));
    probe.volume.target(probe.stream, .8, tags, prefs.copyWith(preampDb: 3),
        dspBase: base, smooth: false);
    expect(probe.attribute(19), closeTo(base, 1e-6));
    expect(probe.decode(), closeTo(.25, .0002));
    probe.volume.target(probe.stream, 1.5, tags, prefs.copyWith(preampDb: 3),
        dspBase: base, smooth: false);
    expect(probe.decode(), closeTo(.25, .0002));
  }, skip: unavailable);

  test(
      'native missing tags live preamp fallback off and mute use fixed DSP base',
      () async {
    const tags = ReplayGainTags();
    const prefs = ReplayGainPreferences(
        mode: ReplayGainMode.track, preampDb: 3, fallbackGainDb: -9);
    final base = probe.volume.initialize(probe.stream, .8, tags, prefs);
    expect(probe.decode(), closeTo(.25 * .8 * math.pow(10, -6 / 20), .0002));
    final live =
        prefs.copyWith(preampDb: 6, fallbackGainDb: 0, preventClipping: false);
    probe.volume
        .target(probe.stream, .8, tags, live, dspBase: base, smooth: true);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(probe.attribute(19), closeTo(base, 1e-6));
    expect(probe.decode(), closeTo(.25 * .8 * math.pow(10, 6 / 20), .0002));
    final off = live.copyWith(mode: ReplayGainMode.off);
    probe.volume
        .target(probe.stream, .8, tags, off, dspBase: base, smooth: false);
    expect(probe.decode(), closeTo(.2, .0002));
    probe.volume
        .target(probe.stream, 0, tags, live, dspBase: base, smooth: true);
    expect(probe.attribute(2), 0);
    expect(probe.decode(), closeTo(0, 1e-8));
  }, skip: unavailable);

  test('native untagged positive sum remains blocked with unknown peak', () {
    const tags = ReplayGainTags();
    const prefs = ReplayGainPreferences(
        mode: ReplayGainMode.album, preampDb: 3, fallbackGainDb: 3);
    final base = probe.volume.initialize(probe.stream, .8, tags, prefs);
    expect(base, 1);
    expect(probe.decode(), closeTo(.2, .0002));
    probe.volume.target(
        probe.stream, .8, tags, prefs.copyWith(preventClipping: false),
        dspBase: base, smooth: false);
    expect(probe.decode(), closeTo(.25 * .8 * math.pow(10, 6 / 20), .0002));
  }, skip: unavailable);
}

class _Probe {
  _Probe(this.folder, this.library, this.bass, this.mix, this.volume,
      this.stream, this.mixer);
  final Directory folder;
  final DynamicLibrary library;
  final Bass bass;
  final BassMixLibrary mix;
  final BassPlaybackVolume volume;
  final int stream, mixer;
  final scalar = calloc<Float>();
  final samples = calloc<Float>(4096);
  late final getData = library.lookupFunction<
      Uint32 Function(Uint32, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
  static final parent = p.normalize(p.join(Directory.current.path, '..', 'tool',
      'qa-local', 'replaygain-gain-next', 'native'));

  static Future<_Probe> open(String runtime) async {
    await Directory(parent).create(recursive: true);
    final folder = await Directory(parent).createTemp('pcm-');
    const frames = 44100 * 3;
    final bytes = ByteData(44 + frames * 2);
    void ascii(int offset, String value) =>
        bytes.buffer.asUint8List().setAll(offset, value.codeUnits);
    ascii(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    ascii(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 44100, Endian.little);
    bytes.setUint32(28, 88200, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, frames * 2, Endian.little);
    for (var frame = 0; frame < frames; frame++) {
      bytes.setInt16(44 + frame * 2, 8192, Endian.little);
    }
    final file = await File(p.join(folder.path, 'constant.wav'))
        .writeAsBytes(bytes.buffer.asUint8List());
    final library = DynamicLibrary.open(p.join(runtime, 'bass.dll'));
    final bass = Bass(library);
    final mix = BassMixLibrary.open(p.join(runtime, 'bassmix.dll'));
    final volume = BassPlaybackVolume.native(library);
    expect(bass.BASS_Init(0, 44100, 0, nullptr, nullptr), 1);
    final filename = file.path.toNativeUtf16();
    final int stream;
    try {
      stream = bass.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
          BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
    } finally {
      malloc.free(filename);
    }
    expect(stream, isNot(0));
    final mixer =
        mix.createStream(44100, 1, BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
    expect(mixer, isNot(0));
    expect(mix.addChannel(mixer, stream, paused: false), isTrue);
    return _Probe(folder, library, bass, mix, volume, stream, mixer);
  }

  double attribute(int attribute) {
    expect(bass.BASS_ChannelGetAttribute(stream, attribute, scalar), 1);
    return scalar.value;
  }

  double decode() {
    expect(getData(mixer, samples.cast(), 4096 * 4), 4096 * 4);
    return samples[4095];
  }

  Future<void> close() async {
    bass.BASS_StreamFree(mixer);
    bass.BASS_StreamFree(stream);
    bass.BASS_Free();
    mix.close();
    library.close();
    calloc.free(samples);
    calloc.free(scalar);
    expect(p.isWithin(parent, await folder.resolveSymbolicLinks()), isTrue);
    await folder.delete(recursive: true);
  }
}
