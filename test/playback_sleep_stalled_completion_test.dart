import 'dart:async';
import 'dart:io';

import 'package:dan_player/app_preference.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_diagnostics.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/src/rust/api/smtc_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/music_category_fixtures.dart';

/// Keep the real sleep timer, source/transport ownership and EOF handling.
/// The endpoint models BASS's documented runtime stall/refill state; these
/// tests do not open user audio, a real output device or a provider connection.
class _Endpoint extends Fake implements BassPlayer {
  final events = StreamController<BassPlaybackEvent>.broadcast();
  final positions = StreamController<double>.broadcast();
  final opened = <String>[];
  Completer<bool>? output;
  int generation = 0;
  int pauses = 0;
  int starts = 0;
  bool sourceAttached = false;
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
  @override
  double length = 120;
  @override
  bool get hasSource => sourceAttached;
  @override
  Stream<BassPlaybackEvent> get playbackEvents => events.stream;
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  bool get eqEnabled => false;
  @override
  bool get supportsPlaybackRate => true;
  @override
  bool get supportsPlaybackPitch => true;
  @override
  void cancelPendingSource() => generation++;

  @override
  Future<bool> setSource(String path,
      {bool isUrl = false, dynamic segment}) async {
    cancelPendingSource();
    opened.add(path);
    sourceAttached = true;
    position = 0;
    playerState = PlayerState.stopped;
    return true;
  }

  @override
  Future<bool> useExclusiveMode(bool exclusive) async {
    final current = generation;
    final applied = await output!.future;
    if (current != generation) return false;
    if (applied) wasapiExclusive = exclusive;
    return applied;
  }

  @override
  void start() {
    starts++;
    playerState = PlayerState.playing;
  }

  @override
  void pause() {
    pauses++;
    playerState = PlayerState.paused;
  }

  @override
  void seek(double target) {
    position = target;
    positions.add(target);
  }

  void stall() {
    position = 42;
    playerState = PlayerState.stalled;
    events.add(
        BassPlaybackEvent(PlaybackStamp(generation, 0), PlayerState.stalled));
  }

  void refill() {
    // Data arriving cannot resume an explicitly paused channel.
    if (playerState != PlayerState.stalled) return;
    playerState = PlayerState.playing;
    events.add(
        BassPlaybackEvent(PlaybackStamp(generation, 0), PlayerState.playing));
  }

  void complete() {
    position = length;
    playerState = PlayerState.stopped;
    events.add(BassPlaybackEvent(
        PlaybackStamp(generation, 0), PlayerState.completed,
        reason: PlaybackEndReason.naturalEnd));
  }

  @override
  void setVolumeDsp(double volume) {}
  @override
  double get volumeDsp => 1;
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
  Future<void> free() async {
    await events.close();
    await positions.close();
  }
}

class _SystemMedia extends Fake implements SmtcFlutter {
  final states = <SMTCState>[];
  @override
  Stream<SMTCControlEvent> subscribeToControlEvents() => const Stream.empty();
  @override
  Future<void> updateState({required SMTCState state}) async =>
      states.add(state);
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
  _Fixture(Directory directory) {
    a = CategoryTestAudio('sleep-stall-a',
        path: p.join(directory.path, 'synthetic-a.wav'));
    b = CategoryTestAudio('sleep-stall-b',
        path: p.join(directory.path, 'synthetic-b.wav'));
    c = CategoryTestAudio('sleep-stall-c',
        path: p.join(directory.path, 'synthetic-c.wav'));
    facade = PlayService.forTesting(
        readiness: readiness,
        createPlayback: (owner) => PlaybackService.forTesting(owner,
            player: endpoint, smtc: system, applyAudioTheme: (_) {}),
        createDesktopLyric: (_) => _OfflineHelper(),
        createLyric: (_) => _OfflineLyrics());
    service = facade.playbackService;
  }
  final endpoint = _Endpoint();
  final system = _SystemMedia();
  final readiness = PlaybackReadiness();
  late final CategoryTestAudio a, b, c;
  late final PlayService facade;
  late final PlaybackService service;

  Future<void> open() async {
    service.play(0, [a, b, c]);
    await _until(() =>
        service.nowPlaying == a && service.resolvingAudioPath.value == null);
    expect(service.playerState, PlayerState.playing);
  }

  Future<void> expire(
      {bool finishCurrent = true, void Function()? beforeExpiry}) async {
    service.setSleepTimerFinishCurrent(finishCurrent);
    // Use the real wall clock and periodic timer. FakeAsync alone would not
    // advance this production controller's DateTime.now deadline.
    service.startSleepTimer(const Duration(milliseconds: 1));
    expect(service.sleepTimerRemaining.value, isNotNull);
    beforeExpiry?.call();
    await _until(() => service.sleepTimerRemaining.value == null,
        attempts: 1500);
  }

  Future<void> close() async {
    if (endpoint.output?.isCompleted == false) {
      endpoint.output!.complete(false);
      await _until(() => !service.isChangingOutput.value);
    }
    await facade.close();
    service.dispose();
    readiness.dispose();
  }
}

Future<void> _until(bool Function() condition, {int attempts = 200}) async {
  for (var turn = 0; turn < attempts && !condition(); turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue, reason: 'Transport fixture failed to settle');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  setUpAll(() async {
    final temporary = p.normalize(Directory.systemTemp.absolute.path);
    if (!temporary
        .replaceAll('\\', '/')
        .toLowerCase()
        .contains('/tool/qa-local/')) {
      throw StateError('TEMP must be a workspace QA directory.');
    }
    directory = await Directory(temporary).createTemp('sleep-stalled-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    AppSettings.instance.dynamicTheme = false;
    AppPreference.instance.playbackPref
      ..playMode = PlayMode.forward
      ..shuffle = false;
  });
  setUp(() {
    AppSettings.instance.experience.value =
        AppSettings.instance.experience.value.copyWith(exclusiveOutput: false);
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));

  Future<_Fixture> openedFixture() async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    return fixture;
  }

  test('finish-current sleep preserves a stalled source through refill and EOF',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    await fixture.expire();
    expect(fixture.service.playerState, PlayerState.stalled);
    expect(fixture.endpoint.pauses, 0);
    expect(fixture.service.queueStopBoundary.target,
        fixture.service.queueOccurrenceId(0));
    fixture.endpoint.refill();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.service.playerState, PlayerState.playing);
    expect(fixture.endpoint.starts, 1,
        reason:
            'Refill must preserve native intent without a new play command.');
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
    expect(fixture.system.states.last, SMTCState.paused);
  });

  test('finish-current stalled expiry replaces a later queue stop target',
      () async {
    final fixture = await openedFixture();
    expect(fixture.service.stopAfterQueueItem(2), isTrue);
    fixture.endpoint.stall();
    await fixture.expire();
    expect(fixture.service.queueStopBoundary.target,
        fixture.service.queueOccurrenceId(0));
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isTrue);
    expect(fixture.endpoint.pauses, 0);
  });

  test('ordinary sleep expiry still pauses a stalled source immediately',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    await fixture.expire(finishCurrent: false);
    expect(fixture.service.playerState, PlayerState.paused);
    expect(fixture.endpoint.pauses, 1);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
    fixture.endpoint.refill();
    expect(fixture.service.playerState, PlayerState.paused);
  });

  test('manual pause before finish-current expiry cannot acquire a stop target',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    await fixture.expire(beforeExpiry: fixture.service.pause);
    expect(fixture.service.playerState, PlayerState.paused);
    expect(fixture.endpoint.pauses, 1);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
    fixture.endpoint.refill();
    expect(fixture.service.playerState, PlayerState.paused);
  });

  test('manual next after stalled finish-current expiry revokes the old target',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    await fixture.expire();
    expect(fixture.service.queueStopBoundary.target,
        fixture.service.queueOccurrenceId(0));
    fixture.service.nextAudio();
    await _until(() =>
        fixture.service.nowPlaying == fixture.b &&
        fixture.service.resolvingAudioPath.value == null);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.playerState, PlayerState.playing);
    fixture.endpoint.complete();
    await _until(() =>
        fixture.service.nowPlaying == fixture.c &&
        fixture.service.resolvingAudioPath.value == null);
    expect(fixture.endpoint.opened,
        [fixture.a.path, fixture.b.path, fixture.c.path]);
  });

  test('finish-current expiry during stalled output rebuilding stays immediate',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    fixture.endpoint.output = Completer<bool>();
    fixture.service.useExclusiveMode(true);
    expect(fixture.service.isChangingOutput.value, isTrue);
    await fixture.expire();
    expect(fixture.service.playerState, PlayerState.paused);
    expect(fixture.endpoint.pauses, 1);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    fixture.endpoint.output!.complete(false);
    await _until(() => !fixture.service.isChangingOutput.value);
    expect(fixture.service.playerState, PlayerState.paused);
    expect(fixture.endpoint.starts, 1);
  });

  test('stalled source already at its end does not defer sleep expiry',
      () async {
    final fixture = await openedFixture();
    fixture.endpoint.stall();
    fixture.endpoint.position = fixture.endpoint.length;
    await fixture.expire();
    expect(fixture.service.playerState, PlayerState.paused);
    expect(fixture.endpoint.pauses, 1);
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
  });
}
