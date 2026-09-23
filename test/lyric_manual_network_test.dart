import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _Playback extends Fake implements PlaybackService {
  _Playback(this.audio);
  final Audio audio;
  final positions = StreamController<double>.broadcast();
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Audio get nowPlaying => audio;
  @override
  Future<void> close() async {}
}

class _Desktop extends Fake implements DesktopLyricService {
  @override
  void sendNoLyricMessage() {}
  @override
  void dispose() {}
  @override
  Future<void> flushAppearance() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    'qq',
    'netease',
    'configured',
    'corrupt',
    'enabled'
  ]) {
    test('automatic $scenario lyric miss follows network permission', () async {
      AppSettings.instance.automaticOnlineLyrics.value = scenario == 'enabled';
      // Real LyricService resolution and cache reads, with only playback and
      // desktop output replaced. Every HTTP client creation is denied and counted.
      final audio = Audio.online(
        provider: scenario == 'qq' ? 'qq' : 'netease',
        id: '${9100000 + [
              'qq',
              'netease',
              'configured',
              'corrupt',
              'enabled'
            ].indexOf(scenario)}',
        numericId: 9100000,
        title: 'Isolated policy probe',
        artist: 'No network',
        album: '',
        duration: 180,
        created: 0,
      );
      final source = scenario == 'configured'
          ? LyricSource(LyricSourceType.netease, neteaseSongId: '9100099')
          : null;
      if (source != null) LYRIC_SOURCES[audio.path] = source;
      File? corrupt;
      if (scenario == 'corrupt') {
        final key =
            sha256.convert(utf8.encode(onlineLyricCacheIdentity(audio)));
        corrupt = File(path.join((await getAppDataDir()).path, 'cache',
            'online_lyrics', '$key.json'));
        await corrupt.parent.create(recursive: true);
        await corrupt.writeAsString('{broken');
      }
      final playback = _Playback(audio);
      final readiness = PlaybackReadiness();
      final facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (_) => playback,
        createDesktopLyric: (_) => _Desktop(),
        createLyric: LyricService.new,
      );
      addTearDown(() async {
        LYRIC_SOURCES.remove(audio.path);
        await facade.close();
        AppSettings.instance.automaticOnlineLyrics.value = false;
        await playback.positions.close();
        readiness.dispose();
        final fixture = corrupt;
        if (fixture != null && await fixture.exists()) await fixture.delete();
      });
      var clients = 0;
      await HttpOverrides.runZoned(() async {
        final lyrics = facade.lyricService;
        lyrics.updateLyric();
        if (scenario == 'enabled') {
          await expectLater(
              lyrics.currLyricFuture, throwsA(isA<NoMatchingOnlineLyric>()));
        } else {
          expect(await lyrics.currLyricFuture, isNull);
        }
        // Window/document refresh paths may resolve repeatedly; misses must
        // remain passive each time, rather than performing a retry search.
        lyrics.updateLyric();
        if (scenario == 'enabled') {
          await expectLater(
              lyrics.currLyricFuture, throwsA(isA<NoMatchingOnlineLyric>()));
        } else {
          expect(await lyrics.currLyricFuture, isNull);
        }
      }, createHttpClient: (_) {
        clients++;
        throw StateError('Unexpected automatic lyric network access');
      });
      expect(clients, scenario == 'enabled' ? greaterThan(0) : 0);
    });
  }
}
