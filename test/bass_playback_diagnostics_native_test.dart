import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_diagnostics.dart';
import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decoder-only probe using synthetic PCM; this does not exercise a physical
/// endpoint, verify audible gaplessness, or stand in for device hotplug tests.
void main() {
  final bassPath = Platform.environment['DAN_PLAYER_CUE_BASS_DLL'];
  test(
      'native format ABI and EOF distinguish real decoder end from invalid handle',
      () async {
    final folder = Directory(
        '${Directory.current.parent.path}/tool/qa-snapshot2-playback');
    await folder.create(recursive: true);
    final file = File('${folder.path}/diagnostics-native.wav');
    const samples = 4410;
    final bytes = ByteData(44 + samples * 2);
    void text(int offset, String value) =>
        bytes.buffer.asUint8List().setAll(offset, value.codeUnits);
    text(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 44100, Endian.little);
    bytes.setUint32(28, 88200, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, samples * 2, Endian.little);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final library = DynamicLibrary.open(bassPath!);
    final bass = Bass(library);
    final filename = file.path.toNativeUtf16();
    final buffer = calloc<Float>(samples + 512);
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    int stream = 0;
    try {
      expect(bass.BASS_Init(0, 44100, 0, nullptr, nullptr), isNot(0));
      stream = bass.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
          BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
      expect(stream, isNot(0));
      final format = readBassChannelFormat(library, stream)!;
      expect(format.sampleRate, 44100);
      expect(format.channels, 1);
      expect(format.originalBits, 16);
      expect(format.sampleFormat, 'float32');
      expect(format.toJson().keys, isNot(contains('filename')));
      final duration = bass.BASS_ChannelBytes2Seconds(
          stream, bass.BASS_ChannelGetLength(stream, BASS_POS_BYTE));
      expect(
          classifyPlaybackStop(
              validHandle: true,
              deviceAvailable: true,
              position: 0,
              duration: duration),
          PlaybackEndReason.unexpectedStop);
      getData(stream, buffer.cast(), (samples + 512) * 4);
      expect(bass.BASS_ChannelIsActive(stream), BASS_ACTIVE_STOPPED);
      expect(bass.BASS_ErrorGetCode(), 0);
      final position = bass.BASS_ChannelBytes2Seconds(
          stream, bass.BASS_ChannelGetPosition(stream, BASS_POS_BYTE));
      expect(
          classifyPlaybackStop(
              validHandle: true,
              deviceAvailable: true,
              position: position,
              duration: duration),
          PlaybackEndReason.naturalEnd);
      expect(bass.BASS_StreamFree(stream), isNot(0));
      expect(bass.BASS_ChannelIsActive(stream), BASS_ACTIVE_STOPPED);
      final invalid = bass.BASS_ErrorGetCode();
      expect(invalid, BASS_ERROR_HANDLE);
      expect(
          classifyPlaybackStop(
              validHandle: invalid != BASS_ERROR_HANDLE,
              deviceAvailable: true,
              position: position,
              duration: duration),
          PlaybackEndReason.invalidHandle);
      stream = bass.BASS_StreamCreateFile(0, filename.cast(), 0, 0,
          BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE | 0x20000);
      const segment = AudioSegment(0.02, 0.08);
      expect(prepareBassSegment(bass, stream, segment), closeTo(0.06, 0.00001));
      getData(stream, buffer.cast(), (samples + 512) * 4);
      expect(bass.BASS_ChannelIsActive(stream), BASS_ACTIVE_STOPPED);
      final absolute = bass.BASS_ChannelBytes2Seconds(
          stream, bass.BASS_ChannelGetPosition(stream, BASS_POS_BYTE));
      expect(
          classifyPlaybackStop(
              validHandle: true,
              deviceAvailable: true,
              position: segment.relativePosition(absolute, 0.06),
              duration: 0.06,
              segment: true),
          PlaybackEndReason.segmentEnd);
      expect(bass.BASS_StreamFree(stream), isNot(0));
      stream = 0;
    } finally {
      if (stream != 0) bass.BASS_StreamFree(stream);
      bass.BASS_Free();
      calloc.free(filename);
      calloc.free(buffer);
      library.close();
    }
  },
      skip: !Platform.isWindows || bassPath == null
          ? 'Requires explicit local BASS DLL; no physical output is opened.'
          : false);
}
