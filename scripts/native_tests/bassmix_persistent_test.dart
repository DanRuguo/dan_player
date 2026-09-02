// Explicit Windows native probe for the resident BASSmix decoder pipeline.
// It uses BASS's no-sound device and generated PCM only; no user/output device
// is opened and no user audio, volume, or settings are touched.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass.dart' as bass_api;
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Uint8List _wave({
  required int sampleRate,
  required int channels,
  int milliseconds = 1200,
}) {
  final frames = sampleRate * milliseconds ~/ 1000;
  final bytes = Uint8List(44 + frames * channels * 2);
  final data = ByteData.sublistView(bytes);
  void fourcc(int offset, String text) =>
      bytes.setRange(offset, offset + 4, ascii.encode(text));
  fourcc(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  fourcc(8, 'WAVE');
  fourcc(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  fourcc(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    final sample =
        (math.sin(frame * math.pi * 2 * 440 / sampleRate) * 4000).round();
    for (var channel = 0; channel < channels; channel++) {
      data.setInt16(
          44 + (frame * channels + channel) * 2, sample, Endian.little);
    }
  }
  return bytes;
}

void main() {
  test('one mixer survives paused source replacement, seek and downmix',
      () async {
    if (!Platform.isWindows) return;
    const workspace = r'D:\code\codex\player';
    final configured = Platform.environment['DAN_PLAYER_BASS_RUNTIME'];
    final runtime = path.normalize(configured ??
        path.join(workspace, 'tool', 'bass', 'runtime-x64-9pkg', 'BASS'));
    if (!path.isWithin(path.join(workspace, 'tool'), path.absolute(runtime))) {
      throw StateError(
          'Native runtime must stay under the workspace tool dir.');
    }

    final bassLibrary = ffi.DynamicLibrary.open(path.join(runtime, 'bass.dll'));
    final bass = bass_api.Bass(bassLibrary);
    final mix = BassMixLibrary.open(path.join(runtime, 'bassmix.dll'));
    final getData = bassLibrary.lookupFunction<
        ffi.Uint32 Function(ffi.Uint32, ffi.Pointer<ffi.Void>, ffi.Uint32),
        int Function(int, ffi.Pointer<ffi.Void>, int)>('BASS_ChannelGetData');
    final run = await Directory(path.join(workspace, 'tool'))
        .createTemp('bassmix-persistent-');
    final buffer = calloc<ffi.Uint8>(8192);
    var mixer = 0;
    try {
      expect(
          bass.BASS_Init(0, 48000, 0, ffi.nullptr, ffi.nullptr), bass_api.TRUE);
      mixer = mix.createStream(
        48000,
        2,
        bass_api.BASS_SAMPLE_FLOAT |
            bass_api.BASS_STREAM_DECODE |
            BassMixLibrary.resume |
            BassMixLibrary.nonstop,
      );
      expect(mixer, isNonZero);
      final persistentIdentity = mixer;

      for (final format in [
        (rate: 44100, channels: 2),
        (rate: 48000, channels: 2),
        (rate: 48000, channels: 6),
      ]) {
        final file = File(path.join(
            run.path, 'source-${format.rate}-${format.channels}.wav'));
        await file.writeAsBytes(
          _wave(sampleRate: format.rate, channels: format.channels),
          flush: true,
        );
        final nativePath = file.path.toNativeUtf16().cast<ffi.Void>();
        var source = 0;
        try {
          source = bass.BASS_StreamCreateFile(
            bass_api.FALSE,
            nativePath,
            0,
            0,
            bass_api.BASS_UNICODE |
                bass_api.BASS_SAMPLE_FLOAT |
                bass_api.BASS_STREAM_DECODE,
          );
        } finally {
          malloc.free(nativePath);
        }
        expect(source, isNonZero,
            reason: 'BASS error ${bass.BASS_ErrorGetCode()}');
        expect(mix.addChannel(mixer, source, paused: true), isTrue,
            reason: 'BASS error ${bass.BASS_ErrorGetCode()}');
        expect(mix.channelIsActive(source), bass_api.BASS_ACTIVE_PAUSED);

        final seekBytes = bass.BASS_ChannelSeconds2Bytes(source, .25);
        expect(
          mix.setChannelPosition(
            source,
            seekBytes,
            bass_api.BASS_POS_BYTE | BassMixLibrary.positionMixerReset,
          ),
          isTrue,
        );
        expect(mix.setChannelPaused(source, false),
            isNot(BassMixLibrary.errorValue));
        expect(mix.channelIsActive(source), bass_api.BASS_ACTIVE_PLAYING);
        expect(getData(mixer, buffer.cast(), 8192), 8192);
        expect(mix.getChannelPosition(source, bass_api.BASS_POS_BYTE),
            greaterThan(seekBytes));
        expect(mixer, persistentIdentity);

        expect(mix.removeChannel(source), isTrue);
        expect(bass.BASS_StreamFree(source), bass_api.TRUE);
      }
      print(jsonEncode({
        'passed': true,
        'mixerRecreated': false,
        'formats': ['44100/2', '48000/2', '48000/6-downmix'],
      }));
    } finally {
      calloc.free(buffer);
      if (mixer != 0) bass.BASS_StreamFree(mixer);
      bass.BASS_Free();
      mix.close();
      bassLibrary.close();
    }
  });
}
