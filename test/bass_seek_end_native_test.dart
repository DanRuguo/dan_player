import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Explicit NoSound device 0, generated PCM and production seek coordinates.
/// No endpoint is started and no listening/latency claim is made.
void main() {
  final dlls = Platform.environment['DAN_PLAYER_SEEK_BASS_DIR'];
  final skip = !Platform.isWindows || dlls == null
      ? 'Set DAN_PLAYER_SEEK_BASS_DIR for an isolated device-0 native check.'
      : false;
  for (final format in [(44100, 1, 16), (48000, 2, 24), (96000, 2, 32)]) {
    for (final useTempo in [false, true]) {
      test(
          'native 100% seek ${format.$1}Hz/${format.$2}ch/${format.$3}bit tempo=$useTempo',
          () {
        final fixture = _NativeSeekFixture(dlls!, format, useTempo);
        try {
          // Ordinary EOF, final CUE EOF, and an interior CUE boundary. The
          // latter must keep its exact byte coordinate, without a last-frame
          // adjustment or leaking audio from the following source section.
          for (final segment in [
            null,
            const AudioSegment(1, 2),
            const AudioSegment(1, 1.5),
          ]) {
            for (final mixerOutput in [false, true]) {
              fixture.check(segment: segment, mixerOutput: mixerOutput);
            }
          }
        } finally {
          fixture.close();
        }
      }, skip: skip);
    }
  }
  test('native single-frame source has a legal seek at 100%', () {
    for (final useTempo in [false, true]) {
      final fixture =
          _NativeSeekFixture(dlls!, (44100, 1, 16), useTempo, frames: 1);
      try {
        for (final mixerOutput in [false, true]) {
          fixture.check(mixerOutput: mixerOutput);
        }
      } finally {
        fixture.close();
      }
    }
  }, skip: skip);
}

class _NativeSeekFixture {
  _NativeSeekFixture(String dlls, this.format, this.useTempo, {int? frames}) {
    directory = Directory(
        '${Directory.current.parent.path}/tool/qa-local/delivery-playback-eof/native-test');
    directory.createSync(recursive: true);
    final sampleFrames = frames ?? format.$1 * 2;
    final wave = File(
        '${directory.path}/seek-${format.$1}-${format.$2}-${format.$3}-$sampleFrames.wav');
    final bytesPerSample = format.$3 ~/ 8;
    final frameBytes = format.$2 * bytesPerSample;
    final data = ByteData(44 + sampleFrames * frameBytes);
    void text(int offset, String value) =>
        data.buffer.asUint8List().setAll(offset, value.codeUnits);
    text(0, 'RIFF');
    data.setUint32(4, data.lengthInBytes - 8, Endian.little);
    text(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, format.$2, Endian.little);
    data.setUint32(24, format.$1, Endian.little);
    data.setUint32(28, format.$1 * frameBytes, Endian.little);
    data.setUint16(32, frameBytes, Endian.little);
    data.setUint16(34, format.$3, Endian.little);
    text(36, 'data');
    data.setUint32(40, sampleFrames * frameBytes, Endian.little);
    for (var frame = 0; frame < sampleFrames; frame++) {
      // After 1.5s use 0.75 as a following-section sentinel. Earlier is 0.25.
      final value = (frame >= format.$1 * 1.5 ? 3 : 1) * (1 << (format.$3 - 3));
      for (var channel = 0; channel < format.$2; channel++) {
        final offset = 44 + frame * frameBytes + channel * bytesPerSample;
        for (var byte = 0; byte < bytesPerSample; byte++) {
          data.setUint8(offset + byte, (value >> (byte * 8)) & 0xff);
        }
      }
    }
    wave.writeAsBytesSync(data.buffer.asUint8List());
    filename = wave.path.toNativeUtf16();
    library = DynamicLibrary.open('$dlls/bass.dll');
    api = Bass(library);
    expect(api.BASS_Init(0, format.$1, 0, nullptr, nullptr), isNot(0));
    mix = BassMixLibrary.open('$dlls/bassmix.dll');
    tempo = BassTempoLibrary.open('$dlls/bass_fx.dll');
    getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    buffer = calloc<Float>(8192);
  }

  final (int, int, int) format;
  final bool useTempo;
  late final Directory directory;
  late final Pointer<Utf16> filename;
  late final DynamicLibrary library;
  late final Bass api;
  late final BassMixLibrary mix;
  late final BassTempoLibrary tempo;
  late final Pointer<Float> buffer;
  late final int Function(int, Pointer<Void>, int) getData;

  void check({AudioSegment? segment, required bool mixerOutput}) {
    final raw = api.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
        BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | 0x20000);
    expect(raw, isNot(0));
    if (segment != null) prepareBassSegment(api, raw, segment);
    final source =
        useTempo ? tempo.createStream(raw, decodingOutput: true) : raw;
    expect(source, isNot(0));
    final mixer = mixerOutput
        ? mix.createStream(format.$1, 2,
            BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | BassMixLibrary.nonstop)
        : 0;
    try {
      if (mixerOutput) {
        expect(mixer, isNot(0));
        expect(mix.addChannel(mixer, source), isTrue);
      }
      bool seek(double seconds) {
        final bytes = bassSeekPositionBytes(api, source, seconds);
        return mixerOutput
            ? mix.setChannelPosition(source, bytes,
                BASS_POS_BYTE | BassMixLibrary.positionMixerReset)
            : api.BASS_ChannelSetPosition(source, bytes, BASS_POS_BYTE) != 0;
      }

      final sourceLength = api.BASS_ChannelGetLength(source, BASS_POS_BYTE);
      final fullDuration = api.BASS_ChannelBytes2Seconds(source, sourceLength);
      final start = segment?.start ?? 0.0;
      final end = segment?.end ?? fullDuration;
      expect(seek(start), isTrue);
      if (end - start > .1) expect(seek(start + (end - start) / 2), isTrue);
      expect(seek(fullDuration + .1), isFalse);
      expect(api.BASS_ErrorGetCode(), BASS_ERROR_POSITION);
      expect(seek(end), isTrue,
          reason: 'The production 100% coordinate must be accepted natively.');
      final position = api.BASS_ChannelGetPosition(source, BASS_POS_BYTE);
      final sampleBytes = 4 * format.$2;
      final endBytes = api.BASS_ChannelSeconds2Bytes(source, end);
      if (end == fullDuration) {
        expect(position, endBytes - sampleBytes);
      } else {
        expect(position, endBytes);
      }
      if (mixerOutput) {
        expect(mix.channelIsActive(source), BASS_ACTIVE_PAUSED,
            reason: 'A successful endpoint seek must preserve paused intent.');
        expect(getData(mixer, buffer.cast(), 8192 * 4), 8192 * 4);
        expect(buffer.asTypedList(8192).every((value) => value == 0), isTrue);
        expect(api.BASS_ChannelGetPosition(source, BASS_POS_BYTE), position,
            reason: 'A resident silent mixer cannot consume paused audio.');
        expect(mix.setChannelPaused(source, false),
            isNot(BassMixLibrary.errorValue));
      }
      final read =
          getData(mixerOutput ? mixer : source, buffer.cast(), 8192 * 4);
      if (mixerOutput) {
        expect(read, 8192 * 4);
        expect(mix.channelIsActive(source), BASS_ACTIVE_STOPPED);
      } else if (end == fullDuration) {
        expect(read, sampleBytes,
            reason:
                'The physical EOF adjustment exposes exactly one final frame.');
      } else {
        expect(read == 0 || read == 0xffffffff, isTrue);
      }
      expect(api.BASS_ChannelGetPosition(source, BASS_POS_BYTE), endBytes);
      if (end < fullDuration && read != 0xffffffff) {
        expect(
            buffer.asTypedList(read ~/ 4).every((value) => value == 0), isTrue,
            reason: 'The following CUE section cannot leak.');
      }
    } finally {
      if (mixer != 0) api.BASS_StreamFree(mixer);
      api.BASS_StreamFree(source);
    }
  }

  void close() {
    api.BASS_Free();
    calloc.free(filename);
    calloc.free(buffer);
    tempo.close();
    mix.close();
    library.close();
  }
}
