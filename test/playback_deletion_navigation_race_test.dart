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
  void cancelPendingSource() => generation++;
  @override
  Future<bool> setSource(String path,
      {bool isUrl = false, dynamic segment}) async {
    cancelPendingSource();
    final opening = generation;
    opens.add(path);
    await openBarrier?.future;
    if (opening != generation) return false;
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
  void pause() => playerState = PlayerState.paused;
  @override
  void seek(double target) => position = target;
  @override
  void setVolumeDsp(double volume) {}
  @override
  bool setPlaybackRate(double rate) => true;
  @override
  bool setPlaybackPitch(double pitch) => true;
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
    directory = await Directory(temporary).createTemp('deletion-navigation-');
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
    await facade.close();
    playback.dispose();
    readiness.dispose();
  });

  test('next during deletion preparation retains the newer source request',
      () async {
    final preparing = playback.prepareAudioDeletion(a.path);
    playback.nextAudio();
    await preparing;
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(playback.nowPlaying, b);
    expect(decoder.currentPath, b.path);
    expect(playback.playerState, PlayerState.playing);
  });

  test(
      'deleting retained old source cannot cancel an already opening next track',
      () async {
    decoder.openBarrier = Completer<void>();
    playback.nextAudio();
    await _until(() => decoder.opens.last == b.path);
    final request = playback.playbackSessionToken;
    final ticket = await playback.prepareAudioDeletion(a.path);
    expect(playback.playbackSessionToken, request);
    expect(playback.resolvingAudioPath.value, b.path);
    // A filesystem failure cannot restore A over the deliberately selected B.
    playback.cancelAudioDeletion(ticket);
    decoder.openBarrier!.complete();
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(playback.nowPlaying, b);
    expect(decoder.currentPath, b.path);
    expect(decoder.opens, [a.path, b.path]);
  });

  test('pause during deletion failure recovery stays paused', () async {
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.pause();
    playback.cancelAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(decoder.currentPath, a.path);
    expect(playback.playerState, isNot(PlayerState.playing));
  });

  test(
      'explicit play during deletion recovery resumes a previously paused track',
      () async {
    playback.pause();
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.start();
    playback.cancelAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(decoder.currentPath, a.path);
    expect(playback.playerState, PlayerState.playing);
  });

  test(
      'sleep expiry during deletion recovery cannot restart the detached source',
      () async {
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.startSleepTimer(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 3));
    playback.toggleSleepTimerPaused(); // Rechecks the already elapsed deadline.
    expect(playback.sleepTimerRemaining.value, isNull);
    playback.cancelAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(decoder.currentPath, a.path);
    expect(playback.playerState, isNot(PlayerState.playing));
  });

  test('successful deletion keeps a later pause while selecting the next track',
      () async {
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.pause();
    playback.commitAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(playback.nowPlaying, b);
    expect(decoder.currentPath, b.path);
    expect(playback.playerState, isNot(PlayerState.playing));
  });

  test('successful deletion keeps a later play from a previously paused track',
      () async {
    playback.pause();
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.start();
    playback.commitAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(playback.nowPlaying, b);
    expect(decoder.currentPath, b.path);
    expect(playback.playerState, PlayerState.playing);
  });

  test('successful deletion keeps sleep expiry while selecting the next track',
      () async {
    final ticket = await playback.prepareAudioDeletion(a.path);
    playback.startSleepTimer(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 3));
    playback.toggleSleepTimerPaused();
    expect(playback.sleepTimerRemaining.value, isNull);
    playback.commitAudioDeletion(ticket);
    await _until(() => playback.resolvingAudioPath.value == null);
    expect(playback.nowPlaying, b);
    expect(decoder.currentPath, b.path);
    expect(playback.playerState, isNot(PlayerState.playing));
  });
}
