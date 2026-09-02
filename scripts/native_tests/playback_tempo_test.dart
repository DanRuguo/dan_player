// Explicit Windows integration probe, outside the default unit test directory.
// Uses only generated all-zero PCM and a loopback HTTP server. BASS's per-process
// stream mix is also muted; Windows/system volume and user files are untouched.
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Uint8List _silentWave({
  int seconds = 12,
  int rate = 48000,
  int channels = 2,
}) {
  final bytes = Uint8List(44 + rate * channels * 2 * seconds);
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
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * channels * 2, Endian.little);
  data.setUint16(32, channels * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  fourcc(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

void main() {
  test('actual player tempo, paused seek, URL ownership and completion',
      () async {
    const workspace = r'D:\code\codex\player';
    final executable = path.normalize(Platform.resolvedExecutable);
    if (!Platform.isWindows ||
        path.basename(executable).toLowerCase() != 'flutter_tester.exe' ||
        !path.isWithin(path.join(workspace, 'tool'), executable)) {
      throw StateError('Run only in the workspace Flutter test process.');
    }
    final requestedOutput = Platform.environment['DAN_PLAYER_TEMPO_QA'];
    final output = Directory(
        requestedOutput ?? path.join(workspace, 'tool', 'qa-tempo-player'));
    if (!path.isWithin(
        path.join(workspace, 'tool'), path.absolute(output.path))) {
      throw StateError(
          'Probe output must stay under the workspace tool folder.');
    }
    await output.create(recursive: true);
    final run = await output.createTemp('native-player-');
    final waveBytes = _silentWave();
    final wave = File(path.join(run.path, 'silent-12s.wav'));
    await wave.writeAsBytes(waveBytes, flush: true);
    final finalRapidWave = File(path.join(run.path, 'rapid-final-7s.wav'));
    await finalRapidWave.writeAsBytes(_silentWave(seconds: 7), flush: true);
    final exclusive441 = File(path.join(run.path, 'exclusive-44100.wav'));
    await exclusive441.writeAsBytes(_silentWave(rate: 44100), flush: true);
    final exclusiveSurround =
        File(path.join(run.path, 'exclusive-48000-6ch.wav'));
    await exclusiveSurround.writeAsBytes(_silentWave(channels: 6), flush: true);
    final report = <Map<String, Object?>>[];
    void record(String event, Map<String, Object?> values) {
      final row = {'event': event, ...values};
      report.add(row);
      print(jsonEncode(row));
    }

    final library = ffi.DynamicLibrary.open(
        path.join(path.dirname(executable), 'BASS', 'bass.dll'));
    final getConfig = library.lookupFunction<ffi.Uint32 Function(ffi.Uint32),
        int Function(int)>('BASS_GetConfig');
    final setConfig = library.lookupFunction<
        ffi.Int32 Function(ffi.Uint32, ffi.Uint32),
        int Function(int, int)>('BASS_SetConfig');
    const streamMixGain = 5;
    final originalGain = getConfig(streamMixGain);
    BassPlayer? player;
    HttpServer? server;
    StreamSubscription<double>? subscription;
    StreamSubscription<PlayerState>? stateSubscription;
    var passed = false;
    try {
      player = BassPlayer();
      expect(originalGain, inInclusiveRange(0, 10000));
      expect(setConfig(streamMixGain, 0), 1);
      expect(getConfig(streamMixGain), 0);
      expect(player.supportsPlaybackRate, isTrue);
      expect(player.tempoUnavailableReason, isNull);
      expect(player.playbackRate, 1);
      final actualPositions = <double>[];
      final states = <PlayerState>[];
      subscription = player.positionStream.listen(actualPositions.add);
      stateSubscription = player.playerStateStream.listen(states.add);

      for (final rate in [.5, 1.0, 2.0]) {
        expect(player.setPlaybackRate(rate), isTrue);
        expect(await player.setSource(wave.path), isTrue);
        expect(player.length, closeTo(12, .001));
        player.setVolumeDsp(0);
        expect(player.volumeDsp, closeTo(0, .000001));
        expect(getConfig(streamMixGain), 0);
        player.seek(1);
        final stopwatch = Stopwatch()..start();
        player.start();
        await Future<void>.delayed(const Duration(milliseconds: 650));
        player.pause();
        stopwatch.stop();
        final position = player.position;
        final elapsed = stopwatch.elapsedMicroseconds / 1000000;
        expect(position - 1, closeTo(elapsed * rate, .18));
        expect(player.playerState, PlayerState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final beforeSeekCount = actualPositions.length;
        player.seek(8.25);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(actualPositions.length, beforeSeekCount + 1);
        expect(actualPositions.last, closeTo(8.25, .001));
        expect(player.playerState, PlayerState.paused);
        expect(player.setPlaybackRate(rate == 2 ? .5 : 2), isTrue);
        expect(player.position, closeTo(8.25, .001));
        expect(player.playerState, PlayerState.paused);
        player.seek(1.25);
        expect(player.position, closeTo(1.25, .001));
        record('rate-and-paused-seek', {
          'rate': rate,
          'realElapsed': elapsed,
          'mediaAdvanced': position - 1,
          'duration': player.length,
          'changedWhilePaused': player.playbackRate,
          'pausedPosition': player.position,
        });
      }

      player.setPlaybackRate(1);
      final rapidResults = await Future.wait([
        for (var i = 0; i < 12; i++)
          player.setSource(i == 11 ? finalRapidWave.path : wave.path),
      ]).timeout(const Duration(seconds: 10));
      expect(rapidResults.where((applied) => applied), [true]);
      expect(rapidResults.last, isTrue);
      expect(player.length, closeTo(7, .001));
      record('rapid-local-latest-wins', {
        'requests': rapidResults.length,
        'applied': rapidResults.where((applied) => applied).length,
        'duration': player.length,
      });

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.uri.path != '/silent.wav') {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response.contentLength = waveBytes.length;
          request.response.add(waveBytes);
        }
        await request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      expect(player.setPlaybackRate(1.5), isTrue);
      expect(await player.setSource('$base/silent.wav', isUrl: true), isTrue);
      player.setVolumeDsp(0);
      player.start();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final oldPosition = player.position;
      await expectLater(player.setSource('$base/missing.wav', isUrl: true),
          throwsFormatException);
      expect(player.length, closeTo(12, .001));
      expect(player.playbackRate, 1.5);
      expect(player.playerState, PlayerState.playing);
      expect(player.position, greaterThanOrEqualTo(oldPosition));
      record('failed-url-retains-tempo-stream', {
        'rate': player.playbackRate,
        'state': player.playerState.name,
        'duration': player.length
      });

      expect(await player.setSource(wave.path), isTrue);
      player.setVolumeDsp(0);
      player.setPlaybackRate(2);
      player.seek(11.6);
      states.clear();
      player.start();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(states, contains(PlayerState.completed));
      expect(player.playerState, PlayerState.stopped);
      record('completed-at-double-rate', {
        'state': player.playerState.name,
        'events': states.map((state) => state.name).toList()
      });

      // Real WASAPI integration is intentionally kept in this explicit native
      // probe rather than ordinary CI: it acquires the current output endpoint
      // in exclusive mode. Audio is generated silence and VOLDSP remains zero.
      player.freeFStream();
      final prewarmStopwatch = Stopwatch()..start();
      player.wasapiExclusive = true;
      prewarmStopwatch.stop();
      final prewarmMilliseconds = prewarmStopwatch.elapsedMilliseconds;
      final switchTimes = <int>[];
      for (final source in [wave, exclusive441, exclusiveSurround, wave]) {
        final stopwatch = Stopwatch()..start();
        expect(await player.setSource(source.path), isTrue);
        player.setVolumeDsp(0);
        player.start();
        stopwatch.stop();
        switchTimes.add(stopwatch.elapsedMilliseconds);
        expect(player.playerState, PlayerState.playing);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
      // A source open may recall a cloud file, but these generated local files
      // are already resident. Recreating an exclusive endpoint (~385 ms on the
      // reported regression machine) must therefore be caught here.
      record('persistent-exclusive-switch-timing', {
        'prewarmMilliseconds': prewarmMilliseconds,
        'switchMilliseconds': switchTimes,
        'includes': 'setSource+setVolumeDsp+start',
      });
      expect(switchTimes.skip(1), everyElement(lessThan(150)));
      player.pause();
      expect(player.playerState, PlayerState.paused);
      final pausedAt = player.position;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(player.position, closeTo(pausedAt, .01));
      final pausedSeekStopwatch = Stopwatch()..start();
      player.seek(2.25);
      pausedSeekStopwatch.stop();
      expect(pausedSeekStopwatch.elapsedMilliseconds, lessThan(150));
      expect(player.playerState, PlayerState.paused);
      expect(player.position, closeTo(2.25, .01));
      player.setPlaybackRate(1.5);
      final pausedResumeStopwatch = Stopwatch()..start();
      player.start();
      pausedResumeStopwatch.stop();
      expect(pausedResumeStopwatch.elapsedMilliseconds, lessThan(150));
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(player.playerState, PlayerState.playing);
      expect(player.position, greaterThan(2.35));
      record('persistent-exclusive-source-switch', {
        'switchMilliseconds': switchTimes,
        'prewarmMilliseconds': prewarmMilliseconds,
        'formats': ['48000/2', '44100/2', '48000/6-downmix', '48000/2'],
        'pausedSeek': 2.25,
        'pausedSeekMilliseconds': pausedSeekStopwatch.elapsedMilliseconds,
        'pausedResumeMilliseconds': pausedResumeStopwatch.elapsedMilliseconds,
        'rate': player.playbackRate,
        'state': player.playerState.name,
      });

      final exclusiveCompleted = player.playerStateStream
          .firstWhere((state) => state == PlayerState.completed);
      final playingSeekStopwatch = Stopwatch()..start();
      player.seek(player.length - .15);
      playingSeekStopwatch.stop();
      expect(playingSeekStopwatch.elapsedMilliseconds, lessThan(150));
      await exclusiveCompleted.timeout(const Duration(seconds: 2));
      expect(player.playerState, PlayerState.stopped);
      record('persistent-exclusive-completion', {
        'state': player.playerState.name,
        'playingSeekMilliseconds': playingSeekStopwatch.elapsedMilliseconds,
      });

      await player.free();
      expect(player.setPlaybackRate(1), isFalse);
      await player.free();
      expect(getConfig(streamMixGain), 0);
      passed = true;
    } finally {
      await subscription?.cancel();
      await stateSubscription?.cancel();
      await player?.free();
      await server?.close(force: true);
      final restored = setConfig(streamMixGain, originalGain) != 0 &&
          getConfig(streamMixGain) == originalGain;
      library.close();
      await File(path.join(run.path, 'report.json')).writeAsString(
          jsonEncode({
            'passed': passed,
            'processGainRestored': restored,
            'userAudio': false,
            'windowsVolumeChanged': false,
            'events': report,
          }),
          flush: true);
      expect(restored, isTrue);
    }
  });
}
