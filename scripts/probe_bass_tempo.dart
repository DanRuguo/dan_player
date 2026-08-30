// A no-output native smoke test. Uses BASS device 0 and generated in-memory
// PCM; does not open audio devices, user files, network streams or settings.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'package:dan_player/play_service/playback_rate.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';

void main(List<String> args) {
  if (args.length < 2 || args.length > 3) {
    throw ArgumentError(
        'probe_bass_tempo.dart <bass.dll> <bass_fx.dll> [channels]');
  }
  final channels = args.length == 3 ? int.parse(args[2]) : 2;
  if (![1, 2, 6, 8].contains(channels)) {
    throw ArgumentError('Invalid test channels');
  }
  final bass = DynamicLibrary.open(args[0]);
  final init = bass.lookupFunction<
      Int32 Function(Int32, Uint32, Uint32, Pointer<Void>, Pointer<Void>),
      int Function(int, int, int, Pointer<Void>, Pointer<Void>)>('BASS_Init');
  final free =
      bass.lookupFunction<Int32 Function(), int Function()>('BASS_Free');
  final error = bass
      .lookupFunction<Int32 Function(), int Function()>('BASS_ErrorGetCode');
  final create = bass.lookupFunction<
      Uint32 Function(Int32, Pointer<Void>, Uint64, Uint64, Uint32),
      int Function(int, Pointer<Void>, int, int, int)>('BASS_StreamCreateFile');
  final streamFree =
      bass.lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'BASS_StreamFree');
  final setAttribute = bass.lookupFunction<
      Int32 Function(Uint32, Uint32, Float),
      int Function(int, int, double)>('BASS_ChannelSetAttribute');
  final getLength = bass.lookupFunction<Uint64 Function(Uint32, Uint32),
      int Function(int, int)>('BASS_ChannelGetLength');
  final getPosition = bass.lookupFunction<Uint64 Function(Uint32, Uint32),
      int Function(int, int)>('BASS_ChannelGetPosition');
  final bytesToSeconds = bass.lookupFunction<Double Function(Uint32, Uint64),
      double Function(int, int)>('BASS_ChannelBytes2Seconds');
  final secondsToBytes = bass.lookupFunction<Uint64 Function(Uint32, Double),
      int Function(int, double)>('BASS_ChannelSeconds2Bytes');
  final setPosition = bass.lookupFunction<
      Int32 Function(Uint32, Uint64, Uint32),
      int Function(int, int, int)>('BASS_ChannelSetPosition');
  final getData = bass.lookupFunction<
      Uint32 Function(Uint32, Pointer<Void>, Uint32),
      int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');

  void check(bool condition, String message) {
    if (!condition) throw StateError('$message; BASS error=${error()}');
  }

  const sampleRate = 48000;
  const seconds = 12;
  final wav = Uint8List(44 + sampleRate * seconds * channels * 2);
  final header = ByteData.sublistView(wav);
  void fourcc(int offset, String value) =>
      wav.setRange(offset, offset + 4, ascii.encode(value));
  fourcc(0, 'RIFF');
  header.setUint32(4, wav.length - 8, Endian.little);
  fourcc(8, 'WAVE');
  fourcc(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  fourcc(36, 'data');
  header.setUint32(40, wav.length - 44, Endian.little);
  for (var frame = 0; frame < sampleRate * seconds; frame++) {
    final sample =
        (math.sin(frame * 2 * math.pi * 440 / sampleRate) * 8000).round();
    for (var channel = 0; channel < channels; channel++) {
      header.setInt16(
          44 + (frame * channels + channel) * 2, sample, Endian.little);
    }
  }
  final input = calloc<Uint8>(wav.length);
  input.asTypedList(wav.length).setAll(0, wav);
  final outputBytes = sampleRate * channels * 4; // one output second, float PCM
  final output = calloc<Uint8>(outputBytes);
  BassTempoLibrary? tempo;
  final results = <Map<String, Object>>[];
  try {
    check(
        init(0, sampleRate, 0, nullptr, nullptr) != 0, 'no-output device init');
    tempo = BassTempoLibrary.open(args[1]);
    for (final rate in PlaybackRate.presets) {
      var stream = create(1, input.cast(), 0, wav.length, 0x200000 | 0x100);
      check(stream != 0, 'create generated decoder');
      try {
        final wrapped = tempo.createStream(stream, decodingOutput: true);
        check(wrapped != 0, 'create tempo wrapper');
        stream = wrapped;
        check(
            setAttribute(stream, BassTempoLibrary.tempoAttribute,
                    PlaybackRate.tempoPercent(rate)) !=
                0,
            'set tempo');
        final length = bytesToSeconds(stream, getLength(stream, 0));
        check((length - seconds).abs() < .001, 'media length changed');
        check(setPosition(stream, secondsToBytes(stream, 3), 0) != 0,
            'source-time seek');
        final start = bytesToSeconds(stream, getPosition(stream, 0));
        check((start - 3).abs() < .01, 'seek is not on source timeline');
        final count = getData(stream, output.cast(), outputBytes);
        check(count == outputBytes, 'decode one second of float output');
        final end = bytesToSeconds(stream, getPosition(stream, 0));
        check(((end - start) - rate).abs() < .16, 'tempo/source-time mapping');
        // Estimate fundamental from the second half, excluding startup/window
        // transients. A sample-rate speedup would change 440Hz to 220..880Hz.
        final samples = output.cast<Float>().asTypedList(outputBytes ~/ 4);
        var crossings = 0;
        for (var i = sampleRate ~/ 2 + 1; i < sampleRate; i++) {
          if (samples[(i - 1) * channels] <= 0 && samples[i * channels] > 0) {
            crossings++;
          }
        }
        final frequency = crossings * 2.0;
        check((frequency - 440).abs() < 12, 'pitch changed with tempo');
        results.add({
          'rate': rate,
          'length': length,
          'seek': start,
          'afterOneOutputSecond': end,
          'frequencyHz': frequency
        });
        final nextRate = rate == 2 ? .5 : 2.0;
        check(
            setAttribute(stream, BassTempoLibrary.tempoAttribute,
                    PlaybackRate.tempoPercent(nextRate)) !=
                0,
            'mid-stream rate');
        final beforeChange = bytesToSeconds(stream, getPosition(stream, 0));
        check(
            (beforeChange - end).abs() < .01, 'rate change moved the playhead');
        check(getData(stream, output.cast(), outputBytes) == outputBytes,
            'decode after rate change');
        final changed = bytesToSeconds(stream, getPosition(stream, 0));
        // BASS_FX drains a short overlap/tempo processing window when changing
        // speed. The first block is transitional, not exactly the new ratio;
        // subsequent blocks must converge without a discontinuous seek.
        check(
            changed > beforeChange &&
                ((changed - beforeChange) - nextRate).abs() < .5,
            'unexpected discontinuity while changing tempo');
        check(getData(stream, output.cast(), outputBytes) == outputBytes,
            'decode settled rate');
        final settled = bytesToSeconds(stream, getPosition(stream, 0));
        check(((settled - changed) - nextRate).abs() < .03,
            'settled rate did not use source time');
        results.last.addAll({
          'transitionTo': nextRate,
          'transitionMediaAdvance': changed - beforeChange,
          'settledMediaAdvance': settled - changed
        });
        check(setPosition(stream, secondsToBytes(stream, 1.25), 0) != 0,
            'backwards seek at changed rate');
        check(
            (bytesToSeconds(stream, getPosition(stream, 0)) - 1.25).abs() < .01,
            'backwards seek changed timestamp scale');
      } finally {
        check(streamFree(stream) != 0, 'free wrapper and owned decoder');
      }
    }
    print(jsonEncode({
      'passed': true,
      'device': 0,
      'audibleOutput': false,
      'channels': channels,
      'bassFxVersion': tempo.version.toRadixString(16),
      'cases': results
    }));
  } finally {
    free();
    tempo?.close();
    bass.close();
    calloc.free(output);
    calloc.free(input);
  }
}
