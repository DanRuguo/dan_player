import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_volume.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Real shipped BASS/BASSmix with device 0 and generated constant PCM. No sound
/// device is opened and no Windows system/session volume is read or changed.
void main() {
  final runtime = Platform.environment['DAN_PLAYER_VOLUME_BASS_DIR'];
  test('native volume retargets/cancels and mixer applies output gain once',
      () async {
    final parent =
        await Directory(p.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    final folder = await parent.createTemp('bass-volume-');
    final file = File(p.join(folder.path, 'constant.wav'));
    const frames = 44100 * 3;
    final bytes = ByteData(44 + frames * 2);
    void ascii(int offset, String text) =>
        bytes.buffer.asUint8List().setAll(offset, text.codeUnits);
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
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final library = DynamicLibrary.open(p.join(runtime!, 'bass.dll'));
    final bass = Bass(library);
    final mix = BassMixLibrary.open(p.join(runtime, 'bassmix.dll'));
    final controller = BassPlaybackVolume.native(library);
    final filename = file.path.toNativeUtf16();
    final scalar = calloc<Float>();
    final samples = calloc<Float>(4096);
    final sliding = library.lookupFunction<Int32 Function(Uint32, Uint32),
        int Function(int, int)>('BASS_ChannelIsSliding');
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    var stream = 0, mixer = 0;
    double read(int attribute) {
      expect(bass.BASS_ChannelGetAttribute(stream, attribute, scalar), 1);
      return scalar.value;
    }

    double mixedTail() {
      expect(getData(mixer, samples.cast(), 4096 * 4), 4096 * 4);
      return samples[4095];
    }

    const tags = ReplayGainTags(trackGainDb: 6, trackPeak: .8);
    const gain = ReplayGainPreferences(mode: ReplayGainMode.track);
    const off = ReplayGainPreferences();
    try {
      expect(bass.BASS_Init(0, 44100, 0, nullptr, nullptr), 1);
      stream = bass.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
          BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
      expect(stream, isNot(0));
      final base = controller.initialize(stream, .4, tags, gain);
      expect(read(19), closeTo(base, 1e-6));
      final initial = read(2);
      controller.target(stream, .1, tags, gain, dspBase: base, smooth: true);
      expect(sliding(stream, 2), 1);
      expect(read(2), closeTo(initial, .04),
          reason:
              'The native ramp begins at the current gain, not the target.');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final midway = read(2);
      controller.target(stream, .6, tags, gain, dspBase: base, smooth: true);
      expect(read(2), closeTo(midway, .04));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(read(2) * base, closeTo(tags.volume(.6, gain), 1e-5));
      controller.target(stream, 0, tags, gain, dspBase: base, smooth: true);
      expect(read(2), 0);
      expect(sliding(stream, 2), 0);

      mixer =
          mix.createStream(44100, 1, BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
      expect(mixer, isNot(0));
      expect(mix.addChannel(mixer, stream, paused: false), isTrue);
      controller.target(stream, .4, tags, gain, dspBase: base, smooth: false);
      expect(mixedTail(), closeTo(.25 * tags.volume(.4, gain), .0002));
      controller.target(stream, .4, tags, off, dspBase: base, smooth: false);
      expect(read(19), closeTo(base, 1e-6),
          reason: 'Live ReplayGain changes never rewrite buffered DSP gain.');
      expect(mixedTail(), closeTo(.1, .0002));
      controller.target(stream, 0, tags, off, dspBase: base, smooth: true);
      expect(read(2), 0);
      expect(mixedTail(), closeTo(0, 1e-8));
    } finally {
      if (stream != 0) bass.BASS_StreamFree(stream);
      if (mixer != 0) bass.BASS_StreamFree(mixer);
      bass.BASS_Free();
      mix.close();
      library.close();
      calloc.free(samples);
      calloc.free(scalar);
      malloc.free(filename);
      final resolved = await folder.resolveSymbolicLinks();
      if (!p.isWithin(parent.path, resolved) ||
          !p.basename(resolved).startsWith('bass-volume-')) {
        throw StateError('Refusing to remove an unverified fixture');
      }
      await Directory(resolved).delete(recursive: true);
    }
  },
      skip: runtime == null
          ? 'Set DAN_PLAYER_VOLUME_BASS_DIR for native probe'
          : false);
}
