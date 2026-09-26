import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

Future<File> syntheticWav(Directory folder) async {
  const rate = 44100;
  final bytes = ByteData(44 + rate * 3 * 2 * 2);
  void text(int offset, String value) =>
      bytes.buffer.asUint8List().setAll(offset, value.codeUnits);
  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 2, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 4, Endian.little);
  bytes.setUint16(32, 4, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, bytes.lengthInBytes - 44, Endian.little);
  for (var i = 0; i < rate * 3; i++) {
    final sample = i < rate
        ? 0
        : i < rate * 2
            ? 3000
            : 15000;
    bytes.setInt16(44 + i * 4, sample, Endian.little);
    bytes.setInt16(46 + i * 4, -sample, Endian.little);
  }
  return File('${folder.path}/antiphase.wav')
      .writeAsBytes(bytes.buffer.asUint8List());
}

void main() {
  final dll = Platform.environment['DAN_PLAYER_WAVEFORM_BASS_DLL'];
  test(
      'native read-only waveform and CUE range leave other decoder position untouched',
      () async {
    final folder = await Directory.systemTemp.createTemp('waveform-native-');
    final wav = await syntheticWav(folder);
    final original = await wav.readAsBytes();
    final library = DynamicLibrary.open(dll!);
    final api = Bass(library);
    expect(api.BASS_Init(0, 44100, 0, nullptr, nullptr), isNot(0));
    final name = wav.path.toNativeUtf16();
    final handle = api.BASS_StreamCreateFile(0, name.cast(), 0, 0,
        BASS_UNICODE | BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT);
    try {
      expect(handle, isNot(0));
      final position = api.BASS_ChannelSeconds2Bytes(handle, .6);
      expect(api.BASS_ChannelSetPosition(handle, position, BASS_POS_BYTE),
          isNot(0));
      final full = await decodeBassWaveform(
          WaveformDecodeRequest(dll, wav.path), WaveformCancellation());
      expect(full!.duration, closeTo(3, 1 / 44100));
      expect(full.peaks, hasLength(512));
      expect(full.peaks.take(160).every((value) => value == 0), isTrue);
      expect(full.peaks[240], greaterThan(0));
      expect(full.peaks.last, greaterThan(full.peaks[240]));
      final segment = await decodeBassWaveform(
          WaveformDecodeRequest(dll, wav.path, start: 1, end: 2),
          WaveformCancellation());
      expect(segment!.duration, 1);
      expect(
          segment.peaks.every((value) => (value - 1).abs() < .00001), isTrue);
      final getPosition = library.lookupFunction<
          Uint64 Function(Uint32, Uint32),
          int Function(int, int)>('BASS_ChannelGetPosition');
      expect(getPosition(handle, BASS_POS_BYTE), position);
      expect(await wav.readAsBytes(), original);
    } finally {
      api.BASS_StreamFree(handle);
      api.BASS_Free();
      malloc.free(name);
      library.close();
      await folder.delete(recursive: true);
    }
  },
      skip: !Platform.isWindows || dll == null
          ? 'Set explicit packaged BASS path.'
          : false);

  test('native cancellation and invalid file resolve and allow retry',
      () async {
    final folder =
        await Directory.systemTemp.createTemp('waveform-native-cancel-');
    try {
      final wav = await syntheticWav(folder);
      final token = WaveformCancellation();
      final pending =
          decodeBassWaveform(WaveformDecodeRequest(dll!, wav.path), token);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      token.cancel();
      expect(await pending, isNull);
      await expectLater(
          decodeBassWaveform(
              WaveformDecodeRequest(dll, '${folder.path}/missing.wav'),
              WaveformCancellation()),
          throwsA(isA<WaveformUnavailable>()));
      expect(
          await decodeBassWaveform(
              WaveformDecodeRequest(dll, wav.path), WaveformCancellation()),
          isNotNull);
    } finally {
      await folder.delete(recursive: true);
    }
  },
      skip: !Platform.isWindows || dll == null
          ? 'Set explicit packaged BASS path.'
          : false);
}
