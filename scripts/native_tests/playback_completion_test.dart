// Explicit Windows playback probe. Only generated silence is played, with
// per-stream gain zero; user files, settings and system volume are untouched.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/audio_segment.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Uint8List silentWave(int sampleRate, int milliseconds) {
  final frames = sampleRate * milliseconds ~/ 1000;
  final bytes = Uint8List(44 + frames * 4);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setAll(offset, ascii.encode(value));
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 2, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 4, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

void main() {
  test('completed CUE can pause and replay from its segment start', () async {
    final workspace = path.normalize(Directory.current.parent.path);
    final executable = path.normalize(Platform.resolvedExecutable);
    if (!Platform.isWindows ||
        path.basename(executable).toLowerCase() != 'flutter_tester.exe' ||
        !path.isWithin(path.join(workspace, 'tool'), executable)) {
      throw StateError('Use the workspace Windows Flutter tester.');
    }
    final output = Directory(
        path.join(workspace, 'tool', 'validation', 'playback-completion'));
    await output.create(recursive: true);
    final run = await output.createTemp('replay-');
    final wave = File(path.join(run.path, 'cue.wav'));
    await wave.writeAsBytes(silentWave(48000, 1250));
    final player = BassPlayer();
    try {
      expect(
          await player.setSource(wave.path,
              segment: const AudioSegment(.2, .9)),
          isTrue);
      player.setVolumeDsp(0);
      for (var round = 0; round < 3; round++) {
        final end =
            player.playbackEvents.firstWhere((event) => event.completed);
        player.start();
        expect(player.position, lessThan(.2),
            reason: 'Round $round must start at CUE start');
        expect((await end.timeout(const Duration(seconds: 3))).reason?.name,
            'segmentEnd');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        if (round > 0) expect(player.pause, returnsNormally);
      }
    } finally {
      await player.free();
    }
  });
  test('real tempo playback reports natural completion across rates', () async {
    final workspace = path.normalize(Directory.current.parent.path);
    final executable = path.normalize(Platform.resolvedExecutable);
    if (!Platform.isWindows ||
        path.basename(executable).toLowerCase() != 'flutter_tester.exe' ||
        !path.isWithin(path.join(workspace, 'tool'), executable)) {
      throw StateError('Use the workspace Windows Flutter tester.');
    }
    final output = Directory(
        path.join(workspace, 'tool', 'validation', 'playback-completion'));
    await output.create(recursive: true);
    final run = await output.createTemp('silent-');
    final player = BassPlayer();
    final results = <Map<String, Object?>>[];
    Future<void> playToEnd(String source,
        {required String name,
        double rate = 1,
        bool isUrl = false,
        AudioSegment? segment,
        bool pauseAndSeek = false}) async {
      expect(await player.setSource(source, isUrl: isUrl, segment: segment),
          isTrue);
      player.setVolumeDsp(0);
      expect(player.setPlaybackRate(rate), isTrue);
      final events = <BassPlaybackEvent>[];
      final subscription = player.playbackEvents.listen(events.add);
      try {
        var completed = player.playbackEvents
            .firstWhere((event) => event.completed || event.problem != null);
        player.start();
        if (pauseAndSeek) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          player.pause();
          final paused = player.position;
          await Future<void>.delayed(const Duration(milliseconds: 80));
          expect(player.position, closeTo(paused, .005));
          expect(events.where((event) => event.completed), isEmpty);
          player.seek(player.length * .7);
          player.start();
        }
        final event = await completed.timeout(const Duration(seconds: 6));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final row = <String, Object?>{
          'case': name,
          'rate': rate,
          'exclusive': player.wasapiExclusive,
          'position': player.position,
          'duration': player.length,
          'reason': event.reason?.name,
          'problem': event.problem?.kind.name,
          'completionCount': events.where((event) => event.completed).length,
        };
        results.add(row);
        print(jsonEncode(row));
        expect(event.completed, isTrue, reason: name);
        expect(
            event.reason?.name, segment == null ? 'naturalEnd' : 'segmentEnd');
        expect(event.problem, isNull);
        expect(player.position, closeTo(player.length, .001));
        expect(events.where((event) => event.completed), hasLength(1));
      } finally {
        await subscription.cancel();
      }
    }

    try {
      expect(player.supportsPlaybackRate, isTrue);
      for (final sampleRate in [44100, 48000]) {
        final wave = File(path.join(run.path, '$sampleRate.wav'));
        await wave.writeAsBytes(silentWave(sampleRate, 1250));
        for (final rate in [.5, 1.0, 2.0]) {
          await playToEnd(wave.path, name: '$sampleRate.wav', rate: rate);
        }
      }
      final wave = File(path.join(run.path, '48000.wav'));
      final ffmpeg = Platform.environment['DAN_PLAYER_TEST_FFMPEG'];
      if (ffmpeg != null) {
        for (final format in [
          ('cbr.mp3', ['-codec:a', 'libmp3lame', '-b:a', '192k']),
          ('vbr.mp3', ['-codec:a', 'libmp3lame', '-q:a', '3']),
          ('lossless.flac', ['-codec:a', 'flac']),
          ('vorbis.ogg', ['-codec:a', 'libvorbis']),
          ('aac.m4a', ['-codec:a', 'aac']),
          ('opus.opus', ['-codec:a', 'libopus']),
        ]) {
          final outputFile = path.join(run.path, format.$1);
          final encoded = await Process.run(ffmpeg, [
            '-nostdin',
            '-loglevel',
            'error',
            '-i',
            wave.path,
            ...format.$2,
            outputFile,
          ]);
          expect(encoded.exitCode, 0, reason: '${encoded.stderr}');
          await playToEnd(outputFile, name: format.$1);
        }
      }
      await playToEnd(wave.path, name: 'pause-seek-resume', pauseAndSeek: true);
      for (final rate in [1.0, 2.0]) {
        await playToEnd(wave.path,
            name: 'cue-segment',
            rate: rate,
            segment: const AudioSegment(.2, .9));
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final bytes = silentWave(44100, 1250);
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      try {
        await playToEnd('http://127.0.0.1:${server.port}/silence.wav',
            name: 'loopback-http', isUrl: true);
      } finally {
        await server.close(force: true);
      }
      // A completion listener must be able to open the next stream without a
      // stale stop/position from its predecessor completing the new one.
      final queueFinished = Completer<void>();
      var queueIndex = 0;
      final queueEvents = <int>[];
      final queueSubscription = player.playbackEvents.listen((event) async {
        if (!event.completed) return;
        queueEvents.add(queueIndex);
        queueIndex++;
        if (queueIndex == 4) {
          queueFinished.complete();
          return;
        }
        try {
          expect(await player.setSource(wave.path), isTrue);
          player.setVolumeDsp(0);
          player.start();
        } catch (error, trace) {
          queueFinished.completeError(error, trace);
        }
      });
      try {
        expect(await player.setSource(wave.path), isTrue);
        player.setPlaybackRate(2);
        player.setVolumeDsp(0);
        player.start();
        await queueFinished.future.timeout(const Duration(seconds: 8));
        expect(queueEvents, [0, 1, 2, 3]);
        print(jsonEncode({
          'case': 'automatic-consecutive-streams',
          'completed': queueEvents
        }));
      } finally {
        await queueSubscription.cancel();
      }
      // Seeking a completed source starts a fresh run of the same handle.
      player.seek(.5);
      final repeated =
          player.playbackEvents.firstWhere((event) => event.completed);
      player.start();
      expect((await repeated.timeout(const Duration(seconds: 3))).completed,
          isTrue);

      if (Platform.environment['DAN_PLAYER_TEST_EXCLUSIVE'] == 'true') {
        player.freeFStream();
        player.wasapiExclusive = true;
        for (final rate in [1.0, 2.0]) {
          await playToEnd(wave.path, name: 'exclusive-wave', rate: rate);
          await playToEnd(wave.path,
              name: 'exclusive-cue',
              rate: rate,
              segment: const AudioSegment(.2, .9));
        }
        await playToEnd(wave.path,
            name: 'exclusive-pause-seek', pauseAndSeek: true);
      }
      // Explicit stop must not produce an end or advance the caller's queue.
      expect(await player.setSource(wave.path), isTrue);
      final stoppedEvents = <BassPlaybackEvent>[];
      final stoppedSubscription =
          player.playbackEvents.listen(stoppedEvents.add);
      player.setVolumeDsp(0);
      player.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      player.freeFStream();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stoppedEvents.where((event) => event.completed), isEmpty);
      expect(stoppedEvents.where((event) => event.reason?.name == 'userStop'),
          hasLength(1));
      await stoppedSubscription.cancel();
      expect(results.map((row) => row['problem']), everyElement(isNull));
    } finally {
      await player.free();
      await File(path.join(run.path, 'result.json'))
          .writeAsString(jsonEncode(results), flush: true);
    }
  });
}
