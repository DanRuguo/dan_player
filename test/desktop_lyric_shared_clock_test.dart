import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Process extends Fake implements Process {
  final _input = StreamController<List<int>>();
  final _output = StreamController<List<int>>();
  final _errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final bytes = <int>[];
  late final IOSink input;

  _Process() {
    _input.stream.listen(bytes.addAll);
    input = IOSink(_input.sink, encoding: utf8);
  }

  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => _output.stream;
  @override
  Stream<List<int>> get stderr => _errors.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  Future<List<Map<String, dynamic>>> messages() async {
    await input.flush();
    await Future<void>.delayed(Duration.zero);
    return const LineSplitter()
        .convert(utf8.decode(bytes))
        .map((line) => Map<String, dynamic>.from(json.decode(line)))
        .toList();
  }

  Future<List<Map<String, dynamic>>> timelines() async => (await messages())
      .where((message) => message['type'] == 'PlaybackTimelineMessage')
      .map((message) => Map<String, dynamic>.from(message['message']))
      .toList();

  Future<void> dispose() async {
    await input.close();
    unawaited(_output.close());
    unawaited(_errors.close());
  }
}

class _Playback extends Fake implements PlaybackService {
  final positions = StreamController<double>.broadcast(sync: true);
  final states = StreamController<PlayerState>.broadcast(sync: true);
  @override
  final playbackRate = ValueNotifier(1.0);
  @override
  PlayerState playerState = PlayerState.playing;
  @override
  double position = 1;
  @override
  Audio? nowPlaying = Audio.online(
      provider: 'fixture',
      id: '1',
      title: 'One',
      artist: 'Artist',
      album: 'Album',
      duration: 60000);
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;

  void move(double value) {
    position = value;
    positions.add(value);
  }

  void state(PlayerState value) {
    playerState = value;
    states.add(value);
  }

  Future<void> dispose() async {
    playbackRate.dispose();
    await positions.close();
    await states.close();
  }
}

class _Lyric extends Fake implements LyricService {
  int syncs = 0;
  @override
  Future<void> syncDesktopLyric() async {
    syncs++;
  }
}

class _Fixture {
  final ready = PlaybackReadiness();
  final playback = _Playback();
  final lyric = _Lyric();
  final processes = [_Process(), _Process()];
  Duration elapsed = Duration.zero;
  int starts = 0;
  late final PlayService facade;
  late final DesktopLyricService service;

  _Fixture() {
    facade = PlayService.forTesting(
        readiness: ready,
        createPlayback: (_) => playback,
        createLyric: (_) => lyric,
        createDesktopLyric: (_) => service);
    service = DesktopLyricService(facade,
        playbackReady: ready,
        elapsed: () => elapsed,
        executableExists: (_) => true,
        startProcess: (_, __) async => processes[starts++],
        readTheme: () => const ColorScheme.light());
  }

  Future<void> initialize() async {
    facade.ensurePlaybackInitialized();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> dispose() async {
    service.dispose();
    ready.dispose();
    await playback.dispose();
    for (final process in processes) {
      await process.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('empty desktop lyrics do not invent a repeating playback clock',
      () async {
    final process = _Process();
    final service = DesktopLyricService(PlayService.instance,
        executableExists: (_) => true,
        startProcess: (_, __) async => process,
        readTheme: () => const ColorScheme.light());
    await service.startDesktopLyric();
    final before = (await process.timelines()).length;
    expect(before, greaterThan(0),
        reason: 'Opening still needs a full snapshot');
    try {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      expect((await process.timelines()).length, before,
          reason: 'No playback source means no periodic correction messages');
    } finally {
      service.dispose();
      await process.dispose();
    }
  });

  test('parent forwards blur and hidden policies with the frame policy',
      () async {
    final process = _Process();
    final rendering = AppSettings.instance.rendering;
    final original = rendering.value;
    final service = DesktopLyricService(PlayService.instance,
        executableExists: (_) => true,
        startProcess: (_, __) async => process,
        readTheme: () => const ColorScheme.light());
    addTearDown(() async {
      service.dispose();
      rendering.value = original;
      await process.dispose();
    });
    rendering.value =
        original.copyWith(surfaceBlur: false, pauseWhenHidden: true);
    await service.startDesktopLyric();
    final initial = (await process.messages()).lastWhere(
        (message) => message['type'] == 'FrameRateMessage')['message'];
    expect(initial['panelBlur'], false);
    expect(initial['pauseWhenHidden'], true);
    rendering.value =
        original.copyWith(surfaceBlur: true, pauseWhenHidden: false);
    final updated = (await process.messages()).lastWhere(
        (message) => message['type'] == 'FrameRateMessage')['message'];
    expect(updated['panelBlur'], true);
    expect(updated['pauseWhenHidden'], false);
  });

  test(
      'shared source throttles playback but sends paused seeks and rate immediately',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.initialize();
    await fixture.service.startDesktopLyric();
    final process = fixture.processes.first;
    final initial = await process.timelines();
    expect(initial, hasLength(1));
    expect(initial.single['positionMilliseconds'], 1000);
    expect(fixture.playback.positions.hasListener, true);
    for (var i = 1; i <= 12; i++) {
      fixture.elapsed = Duration(milliseconds: i * 33);
      fixture.playback.move(1 + i * .033);
    }
    expect(await process.timelines(), hasLength(1));
    fixture.elapsed = const Duration(milliseconds: 429);
    fixture.playback.move(1.429);
    expect(await process.timelines(), hasLength(2));

    fixture.playback.state(PlayerState.paused);
    expect((await process.timelines()).last['playing'], false);
    fixture.playback.move(12.5);
    expect((await process.timelines()).last['positionMilliseconds'], 12500);
    final pausedCount = (await process.timelines()).length;
    for (var i = 0; i < 100; i++) {
      fixture.playback.move(12.5);
    }
    expect(await process.timelines(), hasLength(pausedCount));
    fixture.playback.playbackRate.value = 1.5;
    expect((await process.timelines()).last['playbackRate'], 1.5);

    fixture.playback.state(PlayerState.playing);
    fixture.playback.move(30);
    // Native successful seeks publish position and state, even while playing.
    fixture.playback.states.add(PlayerState.playing);
    expect((await process.timelines()).last['positionMilliseconds'], 30000);
    fixture.service.killDesktopLyric();
    expect(fixture.playback.positions.hasListener, false);
    expect(fixture.playback.states.hasListener, false);
  });

  test(
      'late playback readiness and recovered process attach once and replay latest state',
      () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    await fixture.service.startDesktopLyric();
    expect(fixture.ready.value, false);
    expect(fixture.playback.positions.hasListener, false);
    await fixture.initialize();
    expect(fixture.playback.positions.hasListener, true);
    expect((await fixture.processes.first.timelines()).last['playing'], true);
    expect(fixture.lyric.syncs, 1);
    fixture.processes.first.kill();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.service.state, DesktopLyricState.recovering);
    expect(fixture.playback.positions.hasListener, false);
    fixture.playback.position = 42;
    await Future<void>.delayed(const Duration(milliseconds: 550));
    expect(fixture.starts, 2);
    expect(fixture.playback.positions.hasListener, true);
    final recovered = await fixture.processes.last.timelines();
    expect(recovered, hasLength(1));
    expect(recovered.single['positionMilliseconds'], 42000);
    expect(fixture.lyric.syncs, 2);
    fixture.elapsed = const Duration(milliseconds: 450);
    fixture.playback.move(42.45);
    expect(await fixture.processes.last.timelines(), hasLength(2));
    fixture.service.dispose();
    expect(fixture.playback.positions.hasListener, false);
    expect(fixture.playback.states.hasListener, false);
  });
}
