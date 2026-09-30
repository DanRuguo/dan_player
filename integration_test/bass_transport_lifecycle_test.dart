import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Native transport/state evidence with generated silence. This opens the
/// selected Windows endpoint; it does not measure listening quality or latency.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('paused source remains idle after failed replacement',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.runAsync(() async {
      final folder = await _fixtureDirectory();
      final file = await _silentWave(folder);
      final player = BassPlayer();
      var positions = 0, spectra = 0;
      final positionSubscription =
          player.positionStream.listen((_) => positions++);
      final spectrumSubscription =
          player.frequencySpectrumStream.listen((_) => spectra++);
      try {
        expect(await player.setSource(file.path), isTrue);
        player.start();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(player.playerState, PlayerState.playing);
        expect(positions, greaterThan(0));
        expect(spectra, greaterThan(0));

        // A playing retained source still needs a fresh observation stamp.
        final activePositions = positions;
        player.cancelPendingSource();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(positions, greaterThan(activePositions));

        player.pause();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(player.playerState, PlayerState.paused);
        final pausedPositions = positions, pausedSpectra = spectra;
        player.cancelPendingSource();
        await expectLater(
            player.setSource(p.join(folder.path, 'missing.wav')),
            throwsA(isA<PlaybackProblem>().having((error) => error.kind, 'kind',
                PlaybackProblemKind.sourceUnavailable)));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(positions, pausedPositions,
            reason:
                'A failed new source must not revive the paused 33 ms poll.');
        expect(spectra, pausedSpectra,
            reason: 'A retained paused decoder must not perform FFT work.');
        expect(player.playerState, PlayerState.paused);

        // Paused seek sends its one immediate sample, then stays idle.
        player.seek(2);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(positions, pausedPositions + 1);
        expect(player.position, closeTo(2, .01));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(positions, pausedPositions + 1);
        player.start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(player.playerState, PlayerState.playing);
        expect(positions, greaterThan(pausedPositions + 1));
      } finally {
        await positionSubscription.cancel();
        await spectrumSubscription.cancel();
        await player.free();
        await _removeFixture(folder);
      }
    });
  });

  testWidgets('exclusive ordinary source restarts at EOF without reopening',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.runAsync(() async {
      final folder = await _fixtureDirectory();
      final file = await _silentWave(folder);
      final player = BassPlayer();
      try {
        expect(await player.setSource(file.path), isTrue);
        expect(await player.useExclusiveMode(true), isTrue,
            reason: 'This probe requires a usable exclusive Windows endpoint.');
        final sourceSession = player.sessionId;
        player.seek(player.length - .1);
        player.start();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        expect(player.lastEvent?.completed, isTrue);
        expect(player.playerState, PlayerState.stopped);
        player.start();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(player.sessionId, sourceSession,
            reason: 'Transport resume rewinds the existing decoder.');
        expect(player.playerState, PlayerState.playing);
        expect(player.position, lessThan(1));
      } finally {
        await player.free();
        await _removeFixture(folder);
      }
    });
  }, skip: !const bool.fromEnvironment('DAN_PLAYBACK_EXCLUSIVE_TEST'));
}

Future<Directory> _fixtureDirectory() async {
  const root = String.fromEnvironment('DAN_PLAYBACK_FIXTURE_DIR');
  if (!p.isAbsolute(root) ||
      !p
          .normalize(root)
          .replaceAll('\\', '/')
          .toLowerCase()
          .contains('/tool/qa-local/')) {
    throw StateError(
        'DAN_PLAYBACK_FIXTURE_DIR must be an absolute workspace QA path.');
  }
  final parent = await Directory(root).create(recursive: true);
  return parent.createTemp('bass-transport-');
}

Future<File> _silentWave(Directory folder) async {
  const frames = 48000 * 8;
  final bytes = ByteData(44 + frames * 2);
  void ascii(int offset, String value) =>
      bytes.buffer.asUint8List().setAll(offset, value.codeUnits);
  ascii(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVEfmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 48000, Endian.little);
  bytes.setUint32(28, 96000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, frames * 2, Endian.little);
  return File(p.join(folder.path, 'silence.wav'))
      .writeAsBytes(bytes.buffer.asUint8List());
}

Future<void> _removeFixture(Directory folder) async {
  const root = String.fromEnvironment('DAN_PLAYBACK_FIXTURE_DIR');
  final resolved = await folder.resolveSymbolicLinks();
  final parent = await Directory(root).resolveSymbolicLinks();
  if (!p.isWithin(parent, resolved) ||
      !p.basename(resolved).startsWith('bass-transport-')) {
    throw StateError('Refusing to remove an unverified fixture.');
  }
  await Directory(resolved).delete(recursive: true);
}
