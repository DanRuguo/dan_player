import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

/// Drive the real interval and source controller. Only native audio/SMTC and
/// lyric output are replaced; no endpoint or user music is opened.
class _Endpoint extends Fake implements BassPlayer {
  final positions = StreamController<double>.broadcast(sync: true);
  @override
  bool wasapiExclusive = false;
  @override
  double playbackRate = 1;
  @override
  double playbackPitch = 0;
  @override
  PlayerState playerState = PlayerState.stopped;
  @override
  double position = 0;
  int starts = 0;
  final seeks = <double>[];
  @override
  double get length => 120;
  @override
  bool get hasSource => true;
  @override
  Stream<BassPlaybackEvent> get playbackEvents => const Stream.empty();
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  bool get eqEnabled => false;
  @override
  void cancelPendingSource() {}
  @override
  Future<bool> setSource(String path,
          {bool isUrl = false, dynamic segment}) async =>
      true;
  @override
  void start() {
    starts++;
    playerState = PlayerState.playing;
  }

  @override
  void pause() => playerState = PlayerState.paused;
  @override
  void seek(double target) {
    seeks.add(target);
    position = target;
  }

  void reportPosition(double value) {
    position = value;
    positions.add(value);
  }

  @override
  void setVolumeDsp(double volume) {}
  @override
  bool setPlaybackPitch(double value) {
    playbackPitch = value;
    return true;
  }

  @override
  bool setPlaybackRate(double value) {
    playbackRate = value;
    return true;
  }

  @override
  Future<void> free() => positions.close();
}

class _SystemMedia extends Fake implements SmtcFlutter {
  @override
  Stream<SMTCControlEvent> subscribeToControlEvents() => const Stream.empty();
  @override
  Future<void> updateState({required SMTCState state}) async {}
  @override
  Future<void> updateDisplay(
      {required String title,
      required String artist,
      required String album,
      required int duration,
      required String path}) async {}
  @override
  Future<void> updateTimeProperties({required int progress}) async {}
  @override
  Future<void> close() async {}
}

class _OfflineLyrics extends Fake implements LyricService {
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

class _Fixture {
  _Fixture(Directory directory, this.time) {
    facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (owner) => PlaybackService.forTesting(owner,
            player: endpoint, smtc: _SystemMedia(), applyAudioTheme: (_) {}),
        createDesktopLyric: (_) => _OfflineHelper(),
        createLyric: (_) => _OfflineLyrics());
    service = facade.playbackService;
    audio = CategoryTestAudio('practice',
        path: p.join(directory.path, 'synthetic-not-opened.wav'));
  }

  final endpoint = _Endpoint();
  final FakeAsync time;
  final readiness = PlaybackReadiness();
  late final PlayService facade;
  late final PlaybackService service;
  late final CategoryTestAudio audio;

  Future<void> open() async {
    service.play(0, [audio]);
    for (var turn = 0; turn < 200; turn++) {
      if (service.nowPlaying == audio &&
          service.resolvingAudioPath.value == null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(service.playerState, PlayerState.playing);
    expect(service.canUseSegmentLoop, isTrue);
  }

  void beginInterval() {
    service.segmentLoop.configurePractice(rounds: 3, interval: 10);
    service.segmentLoop.setStart(10, endpoint.length);
    service.segmentLoop.setEnd(20, endpoint.length);
    expect(service.setSegmentLoopEnabled(true), isTrue);
    endpoint.reportPosition(20);
    expect(service.playerState, PlayerState.paused);
    expect(service.segmentLoop.completedRounds, 1);
  }

  Future<void> close() async {
    var done = false;
    final closing = facade.close().whenComplete(() => done = true);
    // Persistence launched by a position callback belongs to its virtual
    // scheduling zone. Let real QA filesystem I/O finish without dropping its
    // queued microtasks or manufacturing a shutdown timeout.
    for (var turn = 0; turn < 200 && !done; turn++) {
      time.flushMicrotasks();
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await closing;
    service.dispose();
    readiness.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUpAll(() async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (!temporary
        .replaceAll('\\', '/')
        .toLowerCase()
        .contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    directory = await Directory(temporary).createTemp('practice-interval-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    AppSettings.instance.dynamicTheme = false;
    AppPreference.instance.playbackPref
      ..playMode = PlayMode.forward
      ..shuffle = false;
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));

  Future<(_Fixture, FakeAsync)> openedFixture() async {
    final time = FakeAsync();
    late _Fixture fixture;
    // Stream callbacks run in the zone where listen() was registered. Both
    // the production subscription and its interval Timer must share this clock.
    time.run((_) => fixture = _Fixture(directory, time));
    addTearDown(fixture.close);
    await fixture.open();
    time.flushMicrotasks();
    return (fixture, time);
  }

  test('repeated play during A-B interval preserves the original deadline',
      () async {
    final (fixture, time) = await openedFixture();
    time.run((time) {
      fixture.beginInterval();
      final starts = fixture.endpoint.starts;
      try {
        time.elapse(const Duration(seconds: 9));
        fixture.service.start(); // A duplicate SMTC/keyboard play command.
        time.elapse(const Duration(seconds: 1));
        expect(fixture.service.playerState, PlayerState.playing);
        expect(fixture.endpoint.starts, starts + 1);
        expect(fixture.endpoint.position, 10);
        expect(fixture.service.segmentLoop.completedRounds, 1);
      } finally {
        fixture.service.segmentLoop.setEnabled(false);
      }
    });
  });

  test('a burst of play commands starts the next practice round once',
      () async {
    final (fixture, time) = await openedFixture();
    time.run((time) {
      fixture.beginInterval();
      final starts = fixture.endpoint.starts;
      try {
        for (var second = 0; second < 9; second++) {
          time.elapse(const Duration(seconds: 1));
          for (var repeat = 0; repeat < 4; repeat++) {
            fixture.service.start();
          }
          expect(fixture.service.playerState, PlayerState.paused);
        }
        time.elapse(const Duration(seconds: 1));
        expect(fixture.endpoint.starts, starts + 1);
        expect(fixture.endpoint.position, 10);
        time.elapse(const Duration(seconds: 20));
        expect(fixture.endpoint.starts, starts + 1);
      } finally {
        fixture.service.segmentLoop.setEnabled(false);
      }
    });
  });

  test('manual pause holds an interval until play resumes its wait', () async {
    final (fixture, time) = await openedFixture();
    time.run((time) {
      fixture.beginInterval();
      final starts = fixture.endpoint.starts;
      try {
        fixture.service.pause(); // Pause at the beginning of the 10s wait.
        time.elapse(const Duration(seconds: 20));
        expect(fixture.endpoint.starts, starts);
        fixture.service.start();
        fixture.service.start();
        time.elapse(const Duration(seconds: 9));
        expect(fixture.endpoint.starts, starts);
        time.elapse(const Duration(seconds: 1));
        expect(fixture.endpoint.starts, starts + 1);
        expect(fixture.endpoint.position, 10);
      } finally {
        fixture.service.segmentLoop.setEnabled(false);
      }
    });
  });

  for (final stop in ['disable', 'seek']) {
    test('$stop during an interval prevents its delayed auto resume', () async {
      final (fixture, time) = await openedFixture();
      time.run((time) {
        fixture.beginInterval();
        final starts = fixture.endpoint.starts;
        try {
          if (stop == 'disable') {
            fixture.service.setSegmentLoopEnabled(false);
          } else {
            fixture.service.seek(45);
          }
          time.elapse(const Duration(seconds: 20));
          expect(fixture.endpoint.starts, starts);
          expect(fixture.service.playerState, PlayerState.paused);
          expect(fixture.service.segmentLoop.enabled, isFalse);
        } finally {
          fixture.service.segmentLoop.setEnabled(false);
        }
      });
    });
  }
}
