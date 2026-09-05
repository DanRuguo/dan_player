import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Optional native regression: uses shipped DLLs and synthetic PCM only.
/// Set DAN_PLAYER_CUE_BASS_DLL and DAN_PLAYER_CUE_FX_DLL to run it locally.
void main() {
  final bassPath = Platform.environment['DAN_PLAYER_CUE_BASS_DLL'];
  final fxPath = Platform.environment['DAN_PLAYER_CUE_FX_DLL'];
  test(
      'production segment setup cuts native decoder and tempo at exact frame boundaries',
      () async {
    final directory =
        Directory('${Directory.current.parent.path}/tool/qa-local/cue-native');
    await directory.create(recursive: true);
    final wav = File('${directory.path}/production-segment.wav');
    final data = ByteData(44 + 44100 * 3 * 2);
    void label(int offset, String text) =>
        data.buffer.asUint8List().setAll(offset, text.codeUnits);
    label(0, 'RIFF');
    data.setUint32(4, data.lengthInBytes - 8, Endian.little);
    label(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, 44100, Endian.little);
    data.setUint32(28, 88200, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    label(36, 'data');
    data.setUint32(40, data.lengthInBytes - 44, Endian.little);
    for (var i = 0; i < 44100 * 3; i++) {
      data.setInt16(
          44 + i * 2,
          i < 44100
              ? 1000
              : i < 88200
                  ? 5000
                  : 10000,
          Endian.little);
    }
    await wav.writeAsBytes(data.buffer.asUint8List());
    final library = DynamicLibrary.open(bassPath!);
    final api = Bass(library);
    final tempo = BassTempoLibrary.open(fxPath!);
    expect(api.BASS_Init(0, 44100, 0, nullptr, nullptr), isNot(0));
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    final buffer = calloc<Float>(4096);
    final filename = wav.path.toNativeUtf16();
    try {
      for (final rate in [1.0, 1.5]) {
        final raw = api.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
            BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | 0x20000);
        expect(raw, isNot(0));
        expect(prepareBassSegment(api, raw, const AudioSegment(1, 2)), 1);
        final handle = tempo.createStream(raw, decodingOutput: true);
        expect(handle, isNot(0));
        api.BASS_ChannelSetAttribute(
            handle, BassTempoLibrary.tempoAttribute, (rate - 1) * 100);
        int readRemaining() {
          var count = 0;
          for (var attempt = 0; attempt < 100; attempt++) {
            final read = getData(handle, buffer.cast(), 4096 * 4);
            if (read == 0xffffffff || read == 0) return count;
            count += read ~/ 4;
            expect(
                buffer.asTypedList(read ~/ 4).every((v) => v >= 0 && v < 0.16),
                isTrue,
                reason:
                    'The next source section has amplitude 0.305 and must never leak.');
          }
          fail('Native segment never ended');
        }

        expect(readRemaining() / 44100, closeTo(1 / rate, 1 / 44100));
        expect(
            api.BASS_ChannelSetPosition(
                handle, api.BASS_ChannelSeconds2Bytes(handle, 1.5), 0),
            isNot(0));
        expect(readRemaining() / 44100, closeTo(0.5 / rate, 1 / 44100));
        api.BASS_StreamFree(handle);
      }
    } finally {
      api.BASS_Free();
      calloc.free(filename);
      calloc.free(buffer);
      tempo.close();
      library.close();
    }
  },
      skip: !Platform.isWindows || bassPath == null || fxPath == null
          ? 'Requires explicit local BASS/BASS_FX paths; portable Dart coverage runs separately.'
          : false);
}
