import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // CI supplies the repository-owned synthetic 30s VBR fixture: 20s silence,
  // then 10s tone, encoded without Xing. No user music or sound device is used.
  final dll = Platform.environment['DAN_PLAYER_WAVEFORM_BASS_DLL'];
  final mp3 = Platform.environment['DAN_PLAYER_WAVEFORM_VBR_FIXTURE'];
  final skip = !Platform.isWindows || dll == null
      ? 'Set the explicit packaged BASS DLL.'
      : false;

  test('VBR MP3 without Xing preserves exact length and fractional CUE time',
      () async {
    final source = File(mp3!);
    final original = await source.readAsBytes();
    final library = DynamicLibrary.open(dll!);
    final api = Bass(library);
    api.BASS_Init(0, 44100, 0, nullptr, nullptr);
    final name = source.path.toNativeUtf16();
    var estimated = 0;
    var precise = 0;
    try {
      estimated = api.BASS_StreamCreateFile(0, name.cast(), 0, 0,
          BASS_UNICODE | BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT);
      expect(estimated, isNot(0));
      final estimatedSeconds = api.BASS_ChannelBytes2Seconds(
          estimated, api.BASS_ChannelGetLength(estimated, BASS_POS_BYTE));
      precise = api.BASS_StreamCreateFile(0, name.cast(), 0, 0,
          BASS_UNICODE | BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT | 0x20000);
      expect(precise, isNot(0));
      final exactSeconds = api.BASS_ChannelBytes2Seconds(
          precise, api.BASS_ChannelGetLength(precise, BASS_POS_BYTE));
      expect(exactSeconds, closeTo(30, .1));
      // The fixture contains 20s silence then 10s tones, with no VBR index.
      // An estimate cannot be trusted as the denominator for time buckets.
      expect((estimatedSeconds - exactSeconds).abs(), greaterThan(1));
      final data = (await decodeBassWaveform(
          WaveformDecodeRequest(dll, source.path), WaveformCancellation()))!;
      expect(data.duration, closeTo(exactSeconds, 1 / 44100));
      expect(data.peaks.take(330).every((value) => value == 0), isTrue);
      expect(data.peaks[355], greaterThan(.1));
      final cue = (await decodeBassWaveform(
          WaveformDecodeRequest(dll, source.path, start: 21.37, end: 23.37),
          WaveformCancellation()))!;
      expect(cue.duration, closeTo(2, 1 / 44100));
      expect(cue.peaks.every((value) => value > .2), isTrue);
      expect(await source.readAsBytes(), original);
    } finally {
      if (estimated != 0) api.BASS_StreamFree(estimated);
      if (precise != 0) api.BASS_StreamFree(precise);
      api.BASS_Free();
      malloc.free(name);
      library.close();
    }
  },
      skip: skip != false || mp3 == null
          ? 'Set packaged BASS and explicit synthetic VBR MP3 fixture.'
          : false);

  test(
      'six-channel source buckets preserve sixth-channel energy and release the file',
      () async {
    final folder =
        await Directory.systemTemp.createTemp('waveform-six-channel-');
    try {
      const rate = 44100, channels = 6, seconds = 3;
      final bytes = ByteData(44 + rate * seconds * channels * 2);
      void text(int offset, String value) =>
          bytes.buffer.asUint8List().setAll(offset, value.codeUnits);
      text(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      text(8, 'WAVEfmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, channels, Endian.little);
      bytes.setUint32(24, rate, Endian.little);
      bytes.setUint32(28, rate * channels * 2, Endian.little);
      bytes.setUint16(32, channels * 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      text(36, 'data');
      bytes.setUint32(40, bytes.lengthInBytes - 44, Endian.little);
      for (var frame = rate; frame < rate * seconds; frame++) {
        final amplitude = frame < rate * 2 ? 3000 : 15000;
        // Only channel six has data; alternating polarity exercises RMS.
        bytes.setInt16(44 + frame * channels * 2 + 10,
            frame.isEven ? amplitude : -amplitude, Endian.little);
      }
      final source = await File('${folder.path}/six.wav')
          .writeAsBytes(bytes.buffer.asUint8List());
      final data = (await decodeBassWaveform(
          WaveformDecodeRequest(dll!, source.path), WaveformCancellation()))!;
      expect(data.duration, closeTo(3, 1 / rate));
      expect(data.peaks.take(160).every((value) => value == 0), isTrue);
      expect(data.peaks[240], greaterThan(0));
      expect(data.peaks.last, greaterThan(data.peaks[240]));
      await source.rename('${folder.path}/released.wav');
    } finally {
      await folder.delete(recursive: true);
    }
  }, skip: skip);
}
