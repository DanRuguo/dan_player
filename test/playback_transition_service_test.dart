import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/play_service/playback_transition_preferences.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

class _Decoder extends Fake implements BassPlayer {
  final events = StreamController<BassPlaybackEvent>.broadcast();
  final positions = StreamController<double>.broadcast();
  final opens = <String>[];
  String? currentPath;
  int generation = 0;
  Completer<void>? openBarrier;
  bool sourceAccepted = true;
  bool preparationAccepted = true;
  Completer<void>? preparationBarrier;
  Object? prepared;
  String? preparedPath;
  final preparations = <Object>[];
  double adoptionPosition = .03;
  @override
  bool get supportsTransitions => true;
  @override
  Object? get preparedSourceIdentity => prepared;
  @override
  void configureTransitions(PlaybackTransitionPreferences value) {}
  @override
  void cancelPreparedSource() {
    prepared = null;
    preparedPath = null;
  }

  @override
  Future<bool> prepareNextSource(String path,
      {required Object identity,
      required double rate,
      required double pitch,
      required bool Function() stillCurrent}) async {
    preparations.add(identity);
    await preparationBarrier?.future;
    if (!stillCurrent() || !preparationAccepted) return false;
    prepared = identity;
    preparedPath = path;
    return true;
  }

  @override
  bool takePreparedSource(Object identity) {
    if (prepared != identity) return false;
    currentPath = preparedPath;
    position = adoptionPosition;
    playerState = PlayerState.playing;
    cancelPreparedSource();
    return true;
  }

  void sample(double progress) {
    position = progress;
    positions.add(progress);
  }

  void completed() => events.add(const BassPlaybackEvent(
      PlaybackStamp(1, 1), PlayerState.completed,
      reason: PlaybackEndReason.naturalEnd));
  @override
  bool wasapiExclusive = false;
  @override
  double playbackRate = 1;
  @override
  double playbackPitch = 0;
  @override
  double position = 0;
  @override
  double get length => 120;
  @override
  bool get hasSource => currentPath != null;
  @override
  PlayerState playerState = PlayerState.stopped;
  @override
  bool get eqEnabled => false;
  @override
  bool get supportsPlaybackRate => true;
  @override
  bool get supportsPlaybackPitch => true;
  @override
  Stream<BassPlaybackEvent> get playbackEvents => events.stream;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  void cancelPendingSource() {
    generation++;
    cancelPreparedSource();
  }

  @override
  Future<bool> setSource(String path,
      {bool isUrl = false, dynamic segment}) async {
    cancelPendingSource();
    final opening = generation;
    opens.add(path);
    await openBarrier?.future;
    if (opening != generation || !sourceAccepted) return false;
    currentPath = path;
    position = 0;
    playerState = PlayerState.stopped;
    return true;
  }

  @override
  bool freeSourceIfPath(String path) {
    if (currentPath != path) return false;
    currentPath = null;
    playerState = PlayerState.stopped;
    return true;
  }

  @override
  Future<void> waitForPendingFileOpen(String path) async {}
  @override
  void start() => playerState = PlayerState.playing;
  @override
  void pause() {
    cancelPreparedSource();
    playerState = PlayerState.paused;
  }

  @override
  void seek(double target) {
    cancelPreparedSource();
    position = target;
  }

  @override
  void setVolumeDsp(double volume) {}
  @override
  bool setPlaybackRate(double rate) {
    playbackRate = rate;
    return true;
  }

  @override
  bool setPlaybackPitch(double pitch) {
    playbackPitch = pitch;
    return true;
  }

  @override
  Future<void> free() async {
    await events.close();
    await positions.close();
  }
}

class _Media extends Fake implements SmtcFlutter {
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

class _Lyrics extends Fake implements LyricService {
  @override
  void updateLyric() {}
  @override
  void findCurrLyricLine() {}
  @override
  void dispose() {}
}

class _Helper extends Fake implements DesktopLyricService {
  @override
  Future<bool> get canSendMessage async => false;
  @override
  void sendPlaybackTimelineMessage() {}
  @override
  Future<void> flushAppearance() async {}
  @override
  void dispose() {}
}

Future<void> _until(bool Function() condition) async {
  for (var turn = 0; turn < 200 && !condition(); turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'Playback request did not settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late _Decoder decoder;
  late PlayService facade;
  late PlaybackReadiness readiness;
  late PlaybackService playback;
  late CategoryTestAudio a, b;

  setUpAll(() async {
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (!temporary
        .replaceAll('\\', '/')
        .toLowerCase()
        .contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    directory = await Directory(temporary).createTemp('transition-service-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    AppSettings.instance.dynamicTheme = false;
    AppPreference.instance.playbackPref
      ..playMode = PlayMode.forward
      ..shuffle = false;
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));
  setUp(() async {
    a = CategoryTestAudio('delete-a', path: p.join(directory.path, 'a.wav'));
    b = CategoryTestAudio('keep-b', path: p.join(directory.path, 'b.wav'));
    AppSettings.instance.playbackTransitions.value =
        const PlaybackTransitionPreferences(
            mode: PlaybackTransitionMode.gapless);
    decoder = _Decoder();
    readiness = PlaybackReadiness();
    facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (owner) => PlaybackService.forTesting(owner,
            player: decoder, smtc: _Media(), applyAudioTheme: (_) {}),
        createDesktopLyric: (_) => _Helper(),
        createLyric: (_) => _Lyrics());
    playback = facade.playbackService;
    playback.play(0, [a, b]);
    await _until(() => playback.nowPlaying == a && playback.canEditQueue);
  });
  tearDown(() async {
    if (decoder.openBarrier?.isCompleted == false) {
      decoder.openBarrier!.complete();
    }
    if (decoder.preparationBarrier?.isCompleted == false) {
      decoder.preparationBarrier!.complete();
    }
    await facade.close();
    AppSettings.instance.playbackTransitions.value =
        const PlaybackTransitionPreferences();
    playback.dispose();
    readiness.dispose();
  });

  Future<void> prepare() async {
    decoder.sample(105);
    await _until(() => decoder.prepared != null);
    // The service installs the completed native plan on the next microtask.
    await Future<void>.delayed(Duration.zero);
  }

  test(
      'automatic transition adopts the prepared occurrence without reopening it',
      () async {
    await prepare();
    final firstOpen = List.of(decoder.opens);
    decoder.completed();
    await _until(() => playback.nowPlaying == b && playback.canEditQueue);
    expect(decoder.opens, firstOpen);
    expect(playback.playlistIndex, 1);
    expect(decoder.currentPath, b.localFilePath);
    expect(playback.position, closeTo(.03, .001));
    expect(playback.playerState, PlayerState.playing);
  });

  test('standard mode and remote stop boundaries do not start preparation',
      () async {
    AppSettings.instance.playbackTransitions.value =
        const PlaybackTransitionPreferences();
    decoder.sample(105);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(decoder.preparations, isEmpty);
    AppSettings.instance.playbackTransitions.value =
        const PlaybackTransitionPreferences(
            mode: PlaybackTransitionMode.gapless);
    playback.setStopAfterCurrent(true);
    decoder.sample(106);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(decoder.preparations, isEmpty);
  });

  test('handoff cannot save the next native clock as the completed predecessor',
      () async {
    final notifier = AppSettings.instance.trackResume;
    final previous = notifier.value;
    addTearDown(() => notifier.value = previous);
    notifier.value =
        const TrackResumePreferences(mode: TrackResumeMode.allLocal);
    await prepare();
    final store = await TrackResumeStore.instance;
    await store.remember(
        track: a.path,
        stableTrackId: a.stableTrackId,
        position: 45,
        duration: 120,
        preferences: notifier.value,
        force: true);
    decoder.adoptionPosition = 15;
    decoder.completed();
    await _until(() => playback.nowPlaying == b && playback.canEditQueue);
    await store.flush();
    expect(
        await store.resumePosition(
            track: a.path,
            stableTrackId: a.stableTrackId,
            duration: 120,
            preferences: notifier.value),
        isNull);
    expect(playback.position, 15);
  });

  test(
      'a queue edit retires a prepared source without changing the current track',
      () async {
    await prepare();
    expect(playback.removeQueueItem(1), isTrue);
    expect(decoder.prepared, isNull);
    expect(playback.nowPlaying, a);
    expect(decoder.opens, hasLength(1));
  });

  test('a late preparation cannot resurrect a removed next occurrence',
      () async {
    decoder.preparationBarrier = Completer<void>();
    decoder.sample(105);
    await _until(() => decoder.preparations.isNotEmpty);
    expect(playback.removeQueueItem(1), isTrue);
    decoder.preparationBarrier!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(decoder.prepared, isNull);
    expect(playback.nowPlaying, a);
  });

  test('pause and seek retire preparation while retaining the playback command',
      () async {
    await prepare();
    playback.pause();
    expect(decoder.prepared, isNull);
    expect(playback.playerState, PlayerState.paused);
    playback.start();
    await prepare();
    playback.seekPrecisely(25, playback.captureTrackPlaybackSettings().session);
    expect(decoder.prepared, isNull);
    expect(playback.position, 25);
    expect(playback.playerState, PlayerState.playing);
  });

  test('A-B playback cannot feed the automatically following source', () async {
    playback.segmentLoop.setStart(10, 120);
    playback.segmentLoop.setEnd(110, 120);
    playback.segmentLoop.setEnabled(true);
    decoder.sample(105);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(decoder.preparations, isEmpty);
  });

  test('failed preparation is bounded and ordinary playback remains available',
      () async {
    decoder.preparationAccepted = false;
    decoder.sample(105);
    await _until(() => decoder.preparations.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    for (var i = 0; i < 50; i++) {
      decoder.sample(105 + i / 100);
    }
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(decoder.preparations, hasLength(1));
    decoder.completed();
    await _until(() => playback.nowPlaying == b && playback.canEditQueue);
    expect(decoder.opens, hasLength(2));
  });

  test(
      'duplicate paths transition to the next occurrence rather than the first',
      () async {
    await playback.playQueue(0, [a, a]);
    await prepare();
    final count = decoder.opens.length;
    decoder.completed();
    await _until(() => playback.playlistIndex == 1 && playback.canEditQueue);
    expect(decoder.opens, hasLength(count));
    expect(playback.nowPlaying, a);
  });
}
