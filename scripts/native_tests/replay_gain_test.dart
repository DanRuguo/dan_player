// Explicit Windows integration probe. All files must be generated fixtures in
// workspace/tool; decoders are read without playback, and player streams remain
// stopped/paused. No system volume or user media/settings are changed.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:dan_player/play_service/replay_gain.dart';
import 'package:dan_player/src/bass/bass.dart';
import 'package:dan_player/src/bass/bass_mix.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/bass/bass_replay_gain.dart';
import 'package:dan_player/src/bass/bass_tempo.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'ReplayGain native formats, tempo, mixer and transactional player lifecycle',
      () async {
    final fixtures = Platform.environment['DAN_PLAYER_REPLAYGAIN_FIXTURES'];
    final workspace = Directory.current.parent.path;
    if (!Platform.isWindows ||
        fixtures == null ||
        !path.isWithin(path.join(workspace, 'tool'), path.absolute(fixtures))) {
      throw StateError(
          'Set DAN_PLAYER_REPLAYGAIN_FIXTURES to generated workspace/tool fixtures.');
    }
    final runtime =
        path.join(path.dirname(Platform.resolvedExecutable), 'BASS');
    final library = DynamicLibrary.open(path.join(runtime, 'bass.dll'));
    final api = Bass(library);
    final tempo = BassTempoLibrary.open(path.join(runtime, 'bass_fx.dll'));
    final mix = BassMixLibrary.open(path.join(runtime, 'bassmix.dll'));
    final getData = library.lookupFunction<
        Uint32 Function(Uint32, Pointer<Void>, Uint32),
        int Function(int, Pointer<Void>, int)>('BASS_ChannelGetData');
    final buffer = calloc<Float>(4096);
    final player = BassPlayer();
    const track = ReplayGainPreferences(mode: ReplayGainMode.track);
    const album = ReplayGainPreferences(mode: ReplayGainMode.album);
    final report = <Map<String, Object>>[];
    try {
      for (final filename in [
        'tone.flac',
        'tone.ogg',
        'tone-v3.mp3',
        'tone-v4.mp3'
      ]) {
        for (final pipeline in ['decoder', 'tempo', 'exclusive-mixer']) {
          double decodeRms(bool normalize) {
            final nativeName = path.join(fixtures, filename).toNativeUtf16();
            var raw = 0;
            var stream = 0;
            var mixer = 0;
            try {
              raw = api.BASS_StreamCreateFile(0, nativeName.cast(), 0, 0,
                  BASS_UNICODE | BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
              expect(raw, isNot(0),
                  reason: '$filename: ${api.BASS_ErrorGetCode()}');
              final tags = readBassReplayGain(library, raw);
              expect(tags.trackGainDb, closeTo(-6.020599913, 1e-8));
              expect(tags.trackPeak, .25);
              expect(tags.albumGainDb, closeTo(6.020599913, 1e-8));
              expect(tags.albumPeak, .8);
              stream = raw;
              if (pipeline != 'decoder') {
                stream = tempo.createStream(raw, decodingOutput: true);
                expect(stream, isNot(0));
                api.BASS_ChannelSetAttribute(
                    stream, BassTempoLibrary.tempoAttribute, 50);
              }
              final volume = tags.volume(
                  .75, normalize ? track : const ReplayGainPreferences());
              expect(
                  api.BASS_ChannelSetAttribute(
                      stream, BASS_ATTRIB_VOLDSP, volume),
                  1);
              var output = stream;
              if (pipeline == 'exclusive-mixer') {
                mixer = mix.createStream(
                    48000, 1, BASS_SAMPLE_FLOAT | BASS_STREAM_DECODE);
                expect(mixer, isNot(0));
                expect(mix.addChannel(mixer, stream, paused: false), isTrue);
                output = mixer;
              }
              var sum = 0.0;
              var count = 0;
              for (var iteration = 0; iteration < 200; iteration++) {
                final bytes = getData(output, buffer.cast(), 4096 * 4);
                if (bytes == 0xffffffff || bytes == 0) break;
                for (final sample in buffer.asTypedList(bytes ~/ 4)) {
                  sum += sample * sample;
                  count++;
                }
              }
              expect(count, greaterThan(48000));
              return math.sqrt(sum / count);
            } finally {
              if (mixer != 0) {
                mix.removeChannel(stream);
                api.BASS_StreamFree(mixer);
              }
              if (stream != 0) {
                api.BASS_StreamFree(stream);
              } else if (raw != 0) {
                api.BASS_StreamFree(raw);
              }
              calloc.free(nativeName);
            }
          }

          final original = decodeRms(false);
          final adjusted = decodeRms(true);
          expect(original, greaterThan(.02));
          expect(adjusted / original, closeTo(.5, .0001),
              reason: '$filename $pipeline must apply gain exactly once.');
          report.add({
            'file': filename,
            'pipeline': pipeline,
            'originalRms': original,
            'normalizedRms': adjusted,
            'ratio': adjusted / original
          });
        }
      }

      print(jsonEncode({'nativeDecodeCases': report}));
      player.setVolumeDsp(.75);
      expect(player.configureReplayGain(track), isTrue);
      expect(await player.setSource(path.join(fixtures, 'tone.flac')), isTrue);
      expect(player.volumeDsp, .75);
      expect(player.effectiveVolumeDsp, closeTo(.375, .000001));
      expect(player.configureReplayGain(album), isTrue);
      expect(player.volumeDsp, .75);
      expect(player.effectiveVolumeDsp, closeTo(1.25, .000001));
      expect(player.setPlaybackRate(1.5), isTrue);
      expect(player.effectiveVolumeDsp, closeTo(1.25, .000001));
      player.setVolumeDsp(0);
      expect(player.configureReplayGain(track), isTrue);
      expect(player.effectiveVolumeDsp, 0);
      final exclusiveAvailable = await player.useExclusiveMode(true);
      if (!exclusiveAvailable) {
        expect(player.wasapiExclusive, isFalse,
            reason: 'Unavailable hardware must roll back to shared output.');
      }
      expect(player.volumeDsp, 0);
      expect(player.effectiveVolumeDsp, 0);
      player.setVolumeDsp(.75);
      expect(player.effectiveVolumeDsp, closeTo(.375, .000001));
      expect(await player.useExclusiveMode(false), isTrue);
      expect(player.volumeDsp, .75);
      expect(player.effectiveVolumeDsp, closeTo(.375, .000001));

      final pending = player.setSource(path.join(fixtures, 'tone-v3.mp3'));
      expect(player.configureReplayGain(album), isTrue);
      player.setVolumeDsp(.25);
      expect(await pending, isTrue);
      expect(player.effectiveVolumeDsp, closeTo(.5, .000001));
      final stale = player.setSource(path.join(fixtures, 'tone.ogg'));
      final latest = player.setSource(path.join(fixtures, 'untagged.wav'));
      expect(await stale, isFalse);
      expect(await latest, isTrue);
      expect(player.replayGainTags.hasGain, isFalse);
      expect(player.effectiveVolumeDsp, closeTo(.25, .000001));
      expect(
          await player.setSource(path.join(fixtures, 'tone-v4.mp3')), isTrue);
      expect(player.effectiveVolumeDsp, closeTo(.5, .000001));
      expect(player.configureReplayGain(const ReplayGainPreferences()), isTrue);
      expect(player.effectiveVolumeDsp, closeTo(.25, .000001));
      expect(player.volumeDsp, .25);
      player.freeFStream();
      expect(player.replayGainTags.hasGain, isFalse);
      expect(player.configureReplayGain(album), isTrue);
      expect(await player.setSource(path.join(fixtures, 'tone.flac')), isTrue);
      expect(player.effectiveVolumeDsp, closeTo(.5, .000001));
      print(jsonEncode({
        'hardwareExclusiveAvailable': exclusiveAvailable,
        'player': [
          'pre-load preferences',
          'native album peak clamp',
          'tempo',
          'mute',
          exclusiveAvailable ? 'exclusive reopen' : 'exclusive failure rollback',
          'shared reopen',
          'settings during open',
          'stale open rejection',
          'untagged reset',
          'off reset',
          'stream reload'
        ]
      }));
    } finally {
      await player.free();
      calloc.free(buffer);
      mix.close();
      tempo.close();
      library.close();
    }
    expect(player.configureReplayGain(track), isFalse);
  });
}
