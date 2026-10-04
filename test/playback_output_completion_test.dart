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

/// Only the endpoint and SMTC are controlled. Source loading, occurrence IDs,
/// output busy ownership, completion settlement and next/stop are production.
class _Endpoint extends Fake implements BassPlayer {
  final events = StreamController<BassPlaybackEvent>.broadcast();
  final positions = StreamController<double>.broadcast();
  final opened = <String>[];
  Completer<bool>? output;
  int generation = 0;
  bool sourceAttached = false;
  bool resetOutputPosition = false;
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
  BassPlaybackEvent? lastEvent;
  @override
  double get length => 120;
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
    lastEvent = null;
    return true;
  }

  @override
  Future<bool> useExclusiveMode(bool exclusive) async {
    final current = generation;
    final applied = await output!.future;
    if (current != generation) return false;
    if (applied) {
      wasapiExclusive = exclusive;
      if (resetOutputPosition) {
        // A replacement starts paused at zero. BassPlayer keeps that valid
        // stream when restoring the old position fails, and clears lastEvent.
        position = 0;
        playerState = PlayerState.paused;
        lastEvent = null;
      }
    }
    return applied;
  }

  @override
  void start() => playerState = PlayerState.playing;
  @override
  void pause() => playerState = PlayerState.paused;
  @override
  bool freeSourceIfPath(String path) {
    if (!sourceAttached || opened.last != path) return false;
    sourceAttached = false;
    playerState = PlayerState.stopped;
    lastEvent = BassPlaybackEvent(PlaybackStamp(generation, 1), playerState,
        reason: PlaybackEndReason.userStop);
    events.add(lastEvent!);
    return true;
  }

  @override
  Future<void> waitForPendingFileOpen(String path) async {}
  @override
  void seek(double target) {
    position = target;
    lastEvent = BassPlaybackEvent(PlaybackStamp(generation, 1), playerState);
    positions.add(target);
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

  void complete({PlaybackEndReason reason = PlaybackEndReason.naturalEnd}) {
    position = length;
    playerState = PlayerState.stopped;
    lastEvent = BassPlaybackEvent(
        PlaybackStamp(generation, 0), PlayerState.completed,
        reason: reason);
    events.add(lastEvent!);
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
    a = CategoryTestAudio('output-a', path: p.join(directory.path, 'a.wav'));
    b = CategoryTestAudio('output-b', path: p.join(directory.path, 'b.wav'));
    c = CategoryTestAudio('output-c', path: p.join(directory.path, 'c.wav'));
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

  Future<void> beginOutput() async {
    endpoint.output = Completer<bool>();
    service.useExclusiveMode(true);
    expect(service.isChangingOutput.value, isTrue);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> finishOutput({bool applied = true}) async {
    endpoint.output!.complete(applied);
    await _until(() => !service.isChangingOutput.value);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    if (endpoint.output?.isCompleted == false) {
      endpoint.output!.complete(false);
    }
    await facade.close();
    service.dispose();
    readiness.dispose();
  }
}

Future<void> _until(bool Function() condition) async {
  for (var turn = 0; turn < 200 && !condition(); turn++) {
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
    directory = await Directory(temporary).createTemp('output-completion-');
    messenger.setMockMethodCallHandler(provider, (_) async => directory.path);
    expect(p.isWithin(directory.path, (await getAppDataDir()).path), isTrue);
    AppSettings.instance.dynamicTheme = false;
    AppSettings.instance.experience.value =
        AppSettings.instance.experience.value.copyWith(exclusiveOutput: false);
    AppPreference.instance.playbackPref
      ..playMode = PlayMode.forward
      ..shuffle = false;
  });
  tearDownAll(() => messenger.setMockMethodCallHandler(provider, null));

  test('natural EOF while changing output advances current queue exactly once',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.service.nowPlaying, fixture.a);
    await fixture.finishOutput();
    await _until(() => fixture.service.nowPlaying == fixture.b);
    expect(fixture.endpoint.opened, [fixture.a.path, fixture.b.path]);
  });

  test('natural EOF during output completes bound queue target', () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    expect(fixture.service.stopAfterQueueItem(0), isTrue);
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    await fixture.finishOutput();
    expect(fixture.service.queueStopBoundary.active, isFalse);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
    expect(fixture.system.states.last, SMTCState.paused);
  });

  test('manual pause after captured EOF preserves the current target',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    expect(fixture.service.stopAfterQueueItem(0), isTrue);
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    fixture.service.pause();
    await fixture.finishOutput();
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
    expect(fixture.service.queueStopBoundary.active, isTrue);
    expect(fixture.service.playerState, PlayerState.paused);
  });

  test('manual next after captured EOF cannot end the newer track', () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    fixture.service.nextAudio();
    await _until(() => fixture.service.nowPlaying == fixture.b);
    await fixture.finishOutput();
    expect(fixture.service.nowPlaying, fixture.b);
    expect(fixture.service.playerState, PlayerState.playing);
    expect(fixture.endpoint.opened, [fixture.a.path, fixture.b.path]);
  });

  test('failed output change still settles proven EOF on retained source',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    await fixture.finishOutput(applied: false);
    await _until(() => fixture.service.nowPlaying == fixture.b);
    expect(fixture.endpoint.opened, [fixture.a.path, fixture.b.path]);
  });

  test('unproven native stop during output never auto advances', () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete(reason: PlaybackEndReason.unexpectedStop);
    await Future<void>.delayed(Duration.zero);
    await fixture.finishOutput();
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
  });

  test('page close before output acknowledgement rejects retained completion',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(() {
      fixture.service.dispose();
      fixture.readiness.dispose();
    });
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    await fixture.facade.close();
    fixture.endpoint.output!.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(fixture.endpoint.opened, [fixture.a.path]);
  });

  test('output busy notification can supersede a deferred completion',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    var changed = false;
    void onSettled() {
      if (!fixture.service.isChangingOutput.value && !changed) {
        changed = true;
        fixture.service.nextAudio();
      }
    }

    fixture.service.isChangingOutput.addListener(onSettled);
    await fixture.finishOutput();
    await _until(() => fixture.service.nowPlaying == fixture.b);
    fixture.service.isChangingOutput.removeListener(onSettled);
    expect(fixture.endpoint.opened, [fixture.a.path, fixture.b.path]);
    expect(fixture.service.playerState, PlayerState.playing);
  });

  test('accepted manual seek during restored readiness overrides deferred EOF',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    void onReady() {
      if (fixture.service.resolvingAudioPath.value == null) {
        fixture.service.seek(30);
      }
    }

    fixture.service.resolvingAudioPath.addListener(onReady);
    await fixture.finishOutput();
    fixture.service.resolvingAudioPath.removeListener(onReady);
    expect(fixture.service.position, 30);
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
  });

  test('sleep stop during output cancels a captured natural completion',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    fixture.service.startSleepTimer(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    // Adjust first ticks the real deadline, without waiting for its 1s poll.
    fixture.service.adjustSleepTimer(Duration.zero);
    expect(fixture.service.sleepTimerRemaining.value, isNull);
    await fixture.finishOutput();
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.endpoint.opened, [fixture.a.path]);
    expect(fixture.service.queueStopBoundary.canAdvanceAutomatically, isFalse);
  });

  test('explicit source release during output invalidates captured EOF',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    // The production deletion transaction stops/releases the matching stream;
    // no physical user file is touched by this fixture.
    await fixture.service.prepareAudioDeletion(fixture.a.path);
    await fixture.finishOutput();
    expect(fixture.service.nowPlaying, fixture.a);
    expect(fixture.service.playerState, PlayerState.stopped);
    expect(fixture.endpoint.hasSource, isFalse);
    expect(fixture.endpoint.opened, [fixture.a.path]);
  });

  test('reopened paused source at zero still settles its proven old EOF',
      () async {
    final fixture = _Fixture(directory);
    addTearDown(fixture.close);
    await fixture.open();
    fixture.endpoint.resetOutputPosition = true;
    await fixture.beginOutput();
    fixture.endpoint.complete();
    await Future<void>.delayed(Duration.zero);
    await fixture.finishOutput();
    await _until(() => fixture.service.nowPlaying == fixture.b);
    expect(fixture.endpoint.opened, [fixture.a.path, fixture.b.path]);
  });
}
