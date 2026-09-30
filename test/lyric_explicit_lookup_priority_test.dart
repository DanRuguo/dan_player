import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Playback extends Fake implements PlaybackService {
  final audio = Audio('Song', 'Artist', 'Album', 0, 180, null, null,
      'explicit-priority-not-opened.mp3', 0, 0, null);
  final positions = StreamController<double>.broadcast();
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Audio get nowPlaying => audio;
  @override
  double get position => 0;
  @override
  Future<void> close() async {}
}

class _Desktop extends Fake implements DesktopLyricService {
  @override
  Future<bool> get canSendMessage async => false;
  @override
  void sendNoLyricMessage() {}
  @override
  void dispose() {}
  @override
  Future<void> flushAppearance() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final persisted in [false, true]) {
    test(
        'enabling automatic lookup preserves a pending explicit choice '
        '(persisted: $persisted)', () async {
      final setting = AppSettings.instance.automaticOnlineLyrics;
      final original = setting.value;
      setting.value = false;
      final directory = await Directory.systemTemp.createTemp('dan-priority-');
      final cache = OnlineLyricCache(directory: () async => directory);
      final documents =
          persisted ? LyricDocumentStore(storageDirectory: directory) : null;
      await documents?.load();
      final playback = _Playback();
      final ready = PlaybackReadiness();
      final pending = Completer<Lyric?>();
      final started = Completer<void>();
      var automaticReads = 0;
      final facade = PlayService.forTesting(
        readiness: ready,
        createPlayback: (_) => playback,
        createDesktopLyric: (_) => _Desktop(),
        createLyric: (owner) => LyricService.forTesting(owner,
            documents: documents, onlineCache: cache, onlineLookup: (_, __) {
          if (!started.isCompleted) started.complete();
          return pending.future;
        }, resolveDefaultLyric: (_) async {
          automaticReads++;
          return null;
        }),
      );
      addTearDown(() async {
        await facade.close();
        await playback.positions.close();
        ready.dispose();
        documents?.dispose();
        setting.value = original;
        await directory.delete(recursive: true);
      });

      final service = facade.lyricService;
      service.useOnlineLyric();
      final selected = service.currLyricFuture;
      await started.future;
      final generation = service.resolutionGeneration;
      setting.value = true;
      final generationAfterOptIn = service.resolutionGeneration;
      final retainedChoice = identical(service.currLyricFuture, selected);
      pending.complete(Lrc.fromLrcText('[00:01.00]Explicit', LrcSource.web));
      // Observe the existing request even on the broken implementation, where
      // the newer automatic generation would turn it into an empty result.
      await selected;
      await service.currLyricFuture;
      expect(generationAfterOptIn, generation);
      expect(retainedChoice, isTrue);
      expect(automaticReads, 0);
      expect((service.rawCurrentLyric!.lines.single as UnsyncLyricLine).content,
          'Explicit');
      if (documents != null) {
        expect(documents.forAudio(playback.audio)?.effective, isNotNull);
      }
    });
  }
}
