import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../test/support/music_category_fixtures.dart';

class _OfflineLyric extends Fake implements LyricService {
  @override
  void updateLyric() {}
  @override
  void findCurrLyricLine() {}
  @override
  void dispose() {}
}

class _OfflineHelper extends Fake implements DesktopLyricService {
  @override
  Future<bool> get canSendMessage async => false;
  @override
  void sendPlaybackTimelineMessage() {}
  @override
  void dispose() {}
  @override
  Future<void> flushAppearance() async {}
}

/// Real PlaybackService and shared BASS output. Generated silence verifies
/// queue/state ownership; it does not verify listening or device latency.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real queue next and append preserve playback across edits',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Queue insertion QA'))));
    await tester.runAsync(() async {
      const root = String.fromEnvironment('DAN_QUEUE_INSERT_FIXTURE_DIR');
      final data = Platform.environment['DAN_PLAYER_DATA_DIR'];
      if (!p.isAbsolute(root) ||
          !p
              .normalize(root)
              .replaceAll('\\', '/')
              .toLowerCase()
              .contains('/tool/qa-local/') ||
          data == null ||
          !p.isWithin(root, p.normalize(data))) {
        throw StateError(
            'Fixture and application data must stay in workspace QA.');
      }
      final directory = await Directory(data).create(recursive: true);
      await TrackIdentityRegistry.instance.initialize(directory: directory);
      await RustLib.init();
      final settings = AppSettings.instance;
      settings.dynamicTheme = false;
      settings.restoreLastSession = false;
      settings.automaticOnlineLyrics.value = false;
      settings.experience.value = settings.experience.value
          .copyWith(playbackRate: 1, playbackPitch: 0, exclusiveOutput: false);
      final audios = <CategoryTestAudio>[];
      for (final name in ['a', 'b', 'c', 'd', 'e']) {
        final file = await _silence(File(p.join(root, '$name.wav')));
        audios.add(CategoryTestAudio(name, path: file.path, duration: 30));
      }
      final [a, b, c, d, e] = audios;
      final readiness = PlaybackReadiness();
      final facade = PlayService.forTesting(
          readiness: readiness,
          createPlayback: PlaybackService.new,
          createDesktopLyric: (_) => _OfflineHelper(),
          createLyric: (_) => _OfflineLyric());
      final service = facade.playbackService;
      service.useShuffle(false);
      final evidence = <String, Object?>{};
      try {
        service.play(0, [a, b]);
        await _loaded(service, a);
        service.pause();
        final source = service.playbackSessionToken;
        final position = service.position;
        final intent = service.playbackIntent.value;
        final active = service.queueOccurrenceId(0);
        expect(service.enqueueAudios([c, c], next: true), isTrue);
        expect(service.enqueueAudios([d], next: true), isTrue);
        expect(service.enqueueAudios([e]), isTrue);
        expect(_names(service), ['a', 'd', 'c', 'c', 'b', 'e']);
        final repeated = [
          service.queueOccurrenceId(2),
          service.queueOccurrenceId(3)
        ];
        expect(repeated.toSet(), hasLength(2));
        expect(service.queueOccurrenceId(0), active);
        expect(service.playbackSessionToken, source);
        expect(service.playbackIntent.value, intent);
        expect(service.playerState, PlayerState.paused);
        expect(service.position, closeTo(position, .02));
        evidence['nextAppendKeepsDecoder'] = service.playbackDiagnostics();

        expect(service.undoQueueEdit(), isTrue);
        expect(_names(service), ['a', 'd', 'c', 'c', 'b']);
        expect(service.redoQueueEdit(), isTrue);
        expect(_names(service), ['a', 'd', 'c', 'c', 'b', 'e']);
        expect(service.undoQueueEdit(), isTrue);
        expect(service.enqueueAudios([e], next: true), isTrue);
        expect(_names(service), ['a', 'e', 'd', 'c', 'c', 'b']);
        expect(service.canRedoQueueEdit, isFalse);
        expect(service.queueOccurrenceId(3), repeated[0]);
        expect(service.queueOccurrenceId(4), repeated[1]);
        evidence['historyAndImmediatePriority'] = _names(service);

        final beforeShuffle = _names(service);
        final beforeShuffleIds = [
          for (var i = 0; i < service.playlist.value.length; i++)
            service.queueOccurrenceId(i)
        ];
        service.useShuffle(true);
        expect(service.enqueueAudios([c], next: true), isTrue);
        expect(service.playlist.value[service.playlistIndex + 1], same(c));
        final insertedId = service.queueOccurrenceId(service.playlistIndex + 1);
        expect(beforeShuffleIds, isNot(contains(insertedId)));
        expect(service.undoQueueEdit(), isTrue);
        expect(service.redoQueueEdit(), isTrue);
        expect(
            service.queueOccurrenceId(service.playlistIndex + 1), insertedId);
        service.useShuffle(false);
        expect(_names(service), [...beforeShuffle, c.title]);
        expect([
          for (var i = 0; i < service.playlist.value.length; i++)
            service.queueOccurrenceId(i)
        ], [
          ...beforeShuffleIds,
          insertedId
        ]);
        expect(service.queueOccurrenceId(0), active);
        expect(service.playerState, PlayerState.paused);
        expect(service.playbackSessionToken, source);
        evidence['shuffleBackup'] = _names(service);

        var reentered = false;
        void reopenFromQueueNotification() {
          if (reentered) return;
          reentered = true;
          service.playIndexOfPlaylist(0);
        }

        service.playlist.addListener(reopenFromQueueNotification);
        try {
          expect(service.enqueueAudios([b], next: true), isTrue);
        } finally {
          service.playlist.removeListener(reopenFromQueueNotification);
        }
        expect(reentered, isTrue);
        await _loaded(service, a);
        expect(service.canUndoQueueEdit, isFalse);
        expect(service.enqueueAudios([d], next: true), isTrue);
        expect(_names(service).take(3), ['a', 'd', 'b']);
        expect(service.canUndoQueueEdit, isTrue);
        expect(service.undoQueueEdit(), isTrue);
        expect(_names(service).take(2), ['a', 'b']);
        evidence['synchronousSourceReentry'] = _names(service);

        // Exercise the actual natural-end service path with a separate short
        // source; the earlier state checks use long files to avoid EOF races.
        final shortFile =
            await _silence(File(p.join(root, 'short.wav')), frames: 28800);
        final short =
            CategoryTestAudio('short', path: shortFile.path, duration: 1);
        service.play(0, [short, b]);
        await _loaded(service, short);
        service.pause();
        expect(service.enqueueAudios([c, d], next: true), isTrue);
        service.start();
        await _loaded(service, c);
        expect(service.playlistIndex, 1);
        expect(service.enqueueAudios([e], next: true), isTrue);
        expect(_names(service), ['short', 'c', 'e', 'd', 'b']);
        evidence['naturalEofThenImmediateNext'] = _names(service);
        expect(service.wasapiExclusive.value, isFalse);
        await File(p.join(root, 'queue-insert-native-evidence.json'))
            .writeAsString(
                const JsonEncoder.withIndent('  ').convert(evidence));
        debugPrint(
            'Queue insertion native: 5 real-service boundaries executed; shared output only.');
      } finally {
        await facade.close();
        readiness.dispose();
        await TrackIdentityRegistry.instance.flush();
      }
    });
  });
}

List<String> _names(PlaybackService service) =>
    service.playlist.value.map((item) => item.title).toList();

Future<void> _loaded(PlaybackService service, CategoryTestAudio audio) async {
  final elapsed = Stopwatch()..start();
  while (service.resolvingAudioPath.value != null ||
      service.nowPlaying?.stableTrackId != audio.stableTrackId ||
      service.playerState != PlayerState.playing) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError(
          'Real service did not settle within the fixture deadline.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<File> _silence(File file, {int frames = 48000 * 30}) async {
  await file.parent.create(recursive: true);
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
  return file.writeAsBytes(bytes.buffer.asUint8List());
}
