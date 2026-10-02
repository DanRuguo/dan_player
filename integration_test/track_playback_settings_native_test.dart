import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/track_playback_settings.dart';
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

/// Real PlaybackService, Rust SMTC and BASS shared output; only lyric lookup
/// and helper IPC are replaced. Generated silence proves state/parameters,
/// never listening quality, latency, or exclusive output reconfiguration.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real service owns saved track parameters across source races',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Track settings QA'))));
    await tester.runAsync(() async {
      const root = String.fromEnvironment('DAN_TRACK_SETTINGS_FIXTURE_DIR');
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
            'Both fixture and DAN_PLAYER_DATA_DIR must be isolated below workspace QA.');
      }
      final dataDirectory = await Directory(data).create(recursive: true);
      await TrackIdentityRegistry.instance.initialize(directory: dataDirectory);
      await RustLib.init();
      final settings = AppSettings.instance;
      settings.dynamicTheme = false;
      settings.restoreLastSession = false;
      settings.automaticOnlineLyrics.value = false;
      settings.experience.value = settings.experience.value.copyWith(
          playbackRate: 1.1, playbackPitch: -1, exclusiveOutput: false);
      final waveA = await _silence(File(p.join(root, 'native-a.wav')));
      final waveB = await _silence(File(p.join(root, 'native-b.wav')));
      final a = CategoryTestAudio('native-a', path: waveA.path, duration: 30);
      final b = CategoryTestAudio('native-b', path: waveB.path, duration: 30);
      final personalFile = File(p.join(data, 'personal_library.json'));
      // An optional personal document read failure cannot block ordinary audio.
      await personalFile.writeAsString('{"version":2,"tracks":{}}');
      final readiness = PlaybackReadiness();
      final facade = PlayService.forTesting(
          readiness: readiness,
          createPlayback: PlaybackService.new,
          createDesktopLyric: (_) => _OfflineHelper(),
          createLyric: (_) => _OfflineLyric());
      final service = facade.playbackService;
      final evidence = <String, Object?>{};
      try {
        expect(service.supportsPlaybackRate, isTrue);
        expect(service.supportsPlaybackPitch, isTrue);
        await _open(service, a);
        _effective(service, 1.1, -1);
        evidence['readFailureStillPlays'] = service.playbackDiagnostics();

        await personalFile.writeAsString(jsonEncode({
          'version': 1,
          'tracks': {
            a.stableTrackId: {
              'rating': 5,
              'tags': ['QA'],
              'playback': {'rate': .75, 'pitch': 3}
            }
          }
        }));
        final library = await PersonalLibrary.instance;
        await _open(service, a);
        _effective(service, .75, 3);
        expect(service.defaultTrackPlaybackSettings.toMap(),
            {'rate': 1.1, 'pitch': -1});
        evidence['savedTrack'] = service.playbackDiagnostics();
        await _open(service, b);
        _effective(service, 1.1, -1);
        evidence['nextTrackDefaults'] = service.playbackDiagnostics();

        // Hold an actual queued store commit; source loading awaits readEntry.
        // This exercises the service's captured revision rather than a mirror.
        final gate = Completer<void>();
        final holding = ProtectedJsonStore.withSnapshot(() => gate.future);
        final writing = library.store.update((_) {});
        try {
          service.play(0, [a]);
          await _until(() => service.resolvingAudioPath.value == a.path);
          expect(service.setPlaybackRate(1.2), isTrue);
        } finally {
          gate.complete();
        }
        await holding;
        await writing;
        await _loaded(service, a);
        _effective(service, 1.2, 3);
        expect(service.defaultTrackPlaybackSettings.toMap(),
            {'rate': 1.2, 'pitch': -1});
        evidence['manualDuringOpen'] = service.playbackDiagnostics();

        final captured = service.captureTrackPlaybackSettings();
        const late = TrackPlaybackSettings(rate: 1.4, pitch: -2);
        final saving = library.setPlayback(a, late);
        await _open(service, b);
        await saving;
        expect(
            service.applySavedTrackPlaybackSettings(
                a.stableTrackId, late, captured),
            isFalse);
        _effective(service, 1.2, -1);
        await _open(service, a);
        _effective(service, 1.4, -2);
        expect(
            service.applySavedTrackPlaybackSettings(
                a.stableTrackId, late, captured),
            isFalse,
            reason: 'A to B to A is still a different source session.');
        final beforeManual = service.captureTrackPlaybackSettings();
        expect(service.setPlaybackPitch(0), isTrue);
        expect(
            service.applySavedTrackPlaybackSettings(
                a.stableTrackId, late, beforeManual),
            isFalse);
        _effective(service, 1.4, 0);
        evidence['lateSaveRejected'] = service.playbackDiagnostics();

        final live = service.captureTrackPlaybackSettings();
        expect(
            service.applySavedTrackPlaybackSettings(
                a.stableTrackId, late, live),
            isTrue);
        _effective(service, 1.4, -2);
        expect(service.defaultTrackPlaybackSettings.toMap(),
            {'rate': 1.2, 'pitch': 0});
        expect(
            service.applySavedTrackPlaybackSettings(
                a.stableTrackId, null, service.captureTrackPlaybackSettings()),
            isTrue);
        _effective(service, 1.2, 0);

        // A parameter observer selecting a new source must cancel the old
        // open before it starts/announces that source as the settled selection.
        var redirected = false;
        void redirect() {
          if (redirected || service.playbackRate.value != 1.4) return;
          redirected = true;
          service.play(0, [b]);
        }

        service.playbackRate.addListener(redirect);
        try {
          service.play(0, [a]);
          await _until(() => redirected);
          await _loaded(service, b);
          _effective(service, 1.2, 0);
        } finally {
          service.playbackRate.removeListener(redirect);
        }
        evidence['observerSourceGuard'] = service.playbackDiagnostics();
        service.pause();
        expect(service.playerState, PlayerState.paused);
        service.start();
        expect(service.playerState, PlayerState.playing);
        _effective(service, 1.2, 0);
        evidence['sharedPauseResume'] = service.playbackDiagnostics();
        await File(p.join(root, 'track-settings-native-evidence.json'))
            .writeAsString(
                const JsonEncoder.withIndent('  ').convert(evidence));
        debugPrint(
            'Track settings native: 7 real service boundaries executed; shared output only.');
      } finally {
        await facade.close();
        readiness.dispose();
        await TrackIdentityRegistry.instance.flush();
      }
    });
  });
}

void _effective(PlaybackService service, double rate, double pitch) {
  expect(service.playbackRate.value, closeTo(rate, 1e-6));
  expect(service.playbackPitch.value, closeTo(pitch, 1e-6));
  expect(service.wasapiExclusive.value, isFalse);
}

Future<void> _open(PlaybackService service, CategoryTestAudio audio) async {
  service.play(0, [audio]);
  await _loaded(service, audio);
}

Future<void> _loaded(PlaybackService service, CategoryTestAudio audio) =>
    _until(() =>
        service.resolvingAudioPath.value == null &&
        service.nowPlaying?.stableTrackId == audio.stableTrackId &&
        service.playerState == PlayerState.playing);

Future<void> _until(bool Function() done) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw StateError(
          'Real service did not settle within the fixture deadline.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<File> _silence(File file) async {
  await file.parent.create(recursive: true);
  const frames = 48000 * 30;
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
