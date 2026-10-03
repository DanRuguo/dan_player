import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric_display_coordinator.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:dan_player/player_experience_preferences.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/taskbar_lyric_service.dart';
import 'package:dan_player/taskbar_lyrics_publisher.dart';
import 'package:desktop_lyric/message.dart' as msg;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Features extends Fake implements AccessibilityFeatures {
  _Features({this.reduced = false, this.disabled = false});
  final bool reduced;
  final bool disabled;
  @override
  bool get reduceMotion => reduced;
  @override
  bool get disableAnimations => disabled;
}

class _Source extends TaskbarLyricSource {
  bool disposed = false;
  @override
  final lyric = Future<Lyric?>.value(PlainLyric('currently visible'));
  @override
  int get generation => 1;
  @override
  int get session => 1;
  @override
  bool get hasTrack => true;
  @override
  double get position => 0;
  @override
  bool get playing => true;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Process extends Fake implements Process {
  _Process({this.autoExit = true}) {
    _input.stream.listen(bytes.addAll);
    input = IOSink(_input.sink, encoding: utf8);
  }
  final bool autoExit;
  final _input = StreamController<List<int>>();
  final _output = StreamController<List<int>>();
  final _errors = StreamController<List<int>>();
  final _exit = Completer<int>();
  final bytes = <int>[];
  late final IOSink input;
  int kills = 0;
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
    kills++;
    if (autoExit) finishExit();
    return true;
  }

  void finishExit() {
    if (!_exit.isCompleted) _exit.complete(0);
  }

  Future<void> emit(msg.Message message) async {
    _output.add(utf8.encode(message.buildMessageJson()));
    await _flush();
  }

  Future<void> dispose() async {
    finishExit();
    await input.close();
    unawaited(_output.close());
    unawaited(_errors.close());
  }
}

class _Playback extends Fake implements PlaybackService {
  final positions = StreamController<double>.broadcast();
  final states = StreamController<PlayerState>.broadcast();
  @override
  final playbackRate = ValueNotifier(1.0);
  @override
  Stream<double> get positionStream => positions.stream;
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  PlayerState get playerState => PlayerState.paused;
  @override
  Audio? get nowPlaying => null;
  @override
  double get position => 0;
  bool _closed = false;
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await positions.close();
    await states.close();
    playbackRate.dispose();
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _Rig {
  _Rig({bool ready = false, Future<Process> Function()? spawn}) {
    readiness.value = ready;
    facade = PlayService.forTesting(
      readiness: facadeReady,
      createPlayback: (_) => playback,
      createDesktopLyric: (_) => desktop,
      createLyric: (owner) => lyric = LyricService.forTesting(owner,
          resolveDefaultLyric: (_) async => null),
    );
    desktop = DesktopLyricService(
      facade,
      playbackReady: readiness,
      displayCoordinator: coordinator,
      executableExists: (_) => true,
      saveAppearance: () async {},
      startProcess: (_, __) async {
        starts++;
        if (spawn != null) return await spawn();
        final process = _Process();
        processes.add(process);
        return process;
      },
    );
    taskbar = TaskbarLyricService(
      preferences: preferences,
      playbackReady: readiness,
      createSource: () {
        factoryCalls++;
        final source = _Source();
        sources.add(source);
        return source;
      },
      coordinator: coordinator,
      savePreferences: () async {
        saves++;
        await save?.call();
      },
      rendering: rendering,
      animationsAllowed: () => animations,
    );
    taskbar.attach(
      send: (payload) async {
        writes.add(payload);
        await send?.call(payload);
      },
      appearance: () {
        appearanceReads++;
        return const TaskbarLyricAppearance(
            accent: 42, fontFamily: 'fixture', fontPath: 'fixture.ttf');
      },
      onError: (error, _) => errors.add(error),
    );
  }
  final preferences = ValueNotifier(const PlayerExperiencePreferences());
  final readiness = ValueNotifier(false);
  final rendering = ValueNotifier<Object?>(0);
  final coordinator = LyricDisplayCoordinator();
  final facadeReady = PlaybackReadiness();
  final playback = _Playback();
  final writes = <Map<String, Object>>[];
  final sources = <_Source>[];
  final errors = <Object>[];
  final processes = <_Process>[];
  late final PlayService facade;
  late final DesktopLyricService desktop;
  late final TaskbarLyricService taskbar;
  LyricService? lyric;
  Future<void> Function(Map<String, Object>)? send;
  Future<void> Function()? save;
  int starts = 0;
  int factoryCalls = 0;
  int saves = 0;
  int appearanceReads = 0;
  bool animations = true;

  Future<void> dispose() async {
    await taskbar.dispose();
    desktop.dispose();
    await facade.close();
    await playback.close();
    await coordinator.dispose();
    for (final process in processes) {
      await process.dispose();
    }
    preferences.dispose();
    readiness.dispose();
    rendering.dispose();
    facadeReady.dispose();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('off attaches no source factory native work or readiness listener',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    rig.readiness.value = true;
    rig.rendering.value = 1;
    rig.taskbar.refreshAppearance();
    await _flush();
    expect(rig.factoryCalls, 0);
    expect(rig.writes, isEmpty);
    expect(rig.appearanceReads, 0);
    expect(rig.starts, 0);
  });

  test('enabled before readiness waits then disposes subscriptions on off',
      () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    expect(await rig.taskbar.setEnabled(true), true);
    expect(rig.factoryCalls, 0);
    expect(rig.writes, isEmpty);
    rig.readiness.value = true;
    await _flush();
    await _flush();
    expect(rig.factoryCalls, 1);
    expect(rig.writes.last['text'], 'currently visible');
    await rig.taskbar.setEnabled(false);
    expect(rig.sources.single.disposed, true);
    final count = rig.writes.length;
    rig.readiness.value = false;
    rig.readiness.value = true;
    await _flush();
    expect(rig.writes.length, count);
    expect(rig.writes.last['enabled'], false);
  });

  test('taskbar opening waits for actual desktop exit not just kill', () async {
    final process = _Process(autoExit: false);
    final rig = _Rig(ready: true, spawn: () async => process);
    rig.processes.add(process);
    addTearDown(rig.dispose);
    await rig.desktop.startDesktopLyric();
    final enabling = rig.taskbar.setEnabled(true);
    await _flush();
    expect(process.kills, greaterThan(0));
    expect(rig.writes, isEmpty);
    process.finishExit();
    expect(await enabling, true);
    await _flush();
    expect(rig.writes.last['enabled'], true);
    expect(rig.desktop.isRunning, false);
  });

  test('desktop opening awaits taskbar in-flight update then disable ack',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    await rig.taskbar.setEnabled(true);
    await _flush();
    final gate = Completer<void>();
    rig.send = (payload) async {
      if (payload['text'] == 'currently visible') await gate.future;
    };
    rig.animations = false;
    rig.rendering.value = 1;
    await _flush();
    final opening = rig.desktop.startDesktopLyric();
    await _flush();
    expect(rig.preferences.value.taskbarLyrics, false);
    expect(rig.starts, 0);
    gate.complete();
    await opening;
    expect(rig.writes.last['enabled'], false);
    expect(rig.desktop.isRunning, true);
    expect(rig.starts, 1);
  });

  test('pending desktop taskbar desktop triple honors latest requested actor',
      () async {
    final pending = Completer<Process>();
    final old = _Process();
    final current = _Process();
    var index = 0;
    final rig = _Rig(
        ready: true,
        spawn: () => index++ == 0 ? pending.future : Future.value(current));
    rig.processes.addAll([old, current]);
    addTearDown(rig.dispose);
    final first = rig.desktop.startDesktopLyric();
    await _flush();
    expect(rig.desktop.isStarting, true);
    final second = rig.taskbar.setEnabled(true);
    final third = rig.desktop.startDesktopLyric();
    pending.complete(old);
    await Future.wait([first, third]);
    expect(await second, false);
    expect(old.kills, greaterThan(0));
    expect(old.bytes, isEmpty);
    expect(rig.desktop.isRunning, true);
    expect(rig.preferences.value.taskbarLyrics, false);
    expect(rig.writes.where((write) => write['enabled'] == true), isEmpty);
  });

  test('real desktop initial sync does not wait for pending lyric provider',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    final gate = Completer<Lyric?>();
    rig.facade.lyricService.currLyricFuture = gate.future;
    await rig.desktop.startDesktopLyric().timeout(const Duration(seconds: 1));
    expect(rig.desktop.isRunning, true);
    expect(await rig.taskbar.setEnabled(true), true);
    final old = rig.processes.single;
    await _flush(); // Drain IOSink writes already queued before the close.
    final oldBytes = old.bytes.length;
    gate.complete(PlainLyric('late initial lyric'));
    await _flush();
    expect(old.bytes.length, oldBytes);
    expect(rig.desktop.isRunning, false);
    expect(rig.writes.last['enabled'], true);
  });

  test('settings notifier opening taskbar closes desktop without extra UI call',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    await rig.desktop.startDesktopLyric();
    rig.preferences.value = rig.preferences.value.copyWith(taskbarLyrics: true);
    await _flush();
    await _flush();
    expect(rig.processes.single.kills, greaterThan(0));
    expect(rig.desktop.isRunning, false);
    expect(rig.writes.last['enabled'], true);
  });

  test('pending lyric initial callback cannot cross a reopened helper',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    final gate = Completer<Lyric?>();
    rig.facade.lyricService.currLyricFuture = gate.future;
    await rig.desktop.startDesktopLyric();
    rig.desktop.killDesktopLyric();
    await rig.desktop.startDesktopLyric();
    gate.complete(PlainLyric('current lyric'));
    await _flush();
    final current = rig.processes.last;
    await current.input.flush();
    await _flush();
    final messages = const LineSplitter()
        .convert(utf8.decode(current.bytes))
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
    expect(
        messages
            .where((message) => message['type'] == 'LyricLineTimelineMessage'),
        hasLength(1));
    expect(rig.processes.first.kills, greaterThan(0));
  });

  test('real first-frame failure clears native and rolls back once', () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    rig.send = (payload) async {
      if (payload['enabled'] == true && payload['text'] != '') {
        throw StateError('fixture surface creation failure');
      }
    };
    await rig.taskbar.setEnabled(true);
    await _flush();
    await _flush();
    expect(rig.preferences.value.taskbarLyrics, false);
    expect(rig.sources.single.disposed, true);
    expect(rig.writes.last['enabled'], false);
    expect(rig.errors, hasLength(1));
    final count = rig.writes.length;
    rig.rendering.value = 1;
    rig.readiness.value = false;
    rig.readiness.value = true;
    await _flush();
    expect(rig.writes.length, count);
  });

  test('native capability failure rolls back preference without lyric factory',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    rig.send = (_) async => throw StateError('fixture native failure');
    expect(await rig.taskbar.setEnabled(true), false);
    expect(rig.preferences.value.taskbarLyrics, false);
    expect(rig.factoryCalls, 0);
    expect(rig.errors, hasLength(1));
    rig.send = null;
    expect(await rig.taskbar.setEnabled(true), true);
    await _flush();
    expect(rig.factoryCalls, 1);
  });

  test('native clear error prevents desktop spawn and does not poison retry',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    await rig.taskbar.setEnabled(true);
    await _flush();
    rig.send = (payload) async {
      if (payload['enabled'] == false) {
        throw StateError('fixture clear failure');
      }
    };
    await expectLater(rig.desktop.startDesktopLyric(), throwsStateError);
    expect(rig.starts, 0);
    rig.send = null;
    await rig.desktop.startDesktopLyric();
    expect(rig.writes.last['enabled'], false);
    expect(rig.desktop.isRunning, true);
  });

  test(
      'live reduceMotion disableAnimations and category updates are event driven',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await rig.taskbar.setEnabled(true);
    await _flush();
    expect(rig.writes.last['animate'], true);
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        _Features(reduced: true);
    await _flush();
    expect(rig.writes.last['animate'], false);
    binding.platformDispatcher.accessibilityFeaturesTestValue = _Features();
    await _flush();
    expect(rig.writes.last['animate'], true);
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        _Features(disabled: true);
    await _flush();
    expect(rig.writes.last['animate'], false);
    binding.platformDispatcher.accessibilityFeaturesTestValue = _Features();
    rig.animations = false;
    rig.rendering.value = 1;
    await _flush();
    expect(rig.writes.last['animate'], false);
    expect(binding.transientCallbackCount, 0);
  });

  test(
      'desktop palette control6 routes through same preference and exit barrier',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    await rig.desktop.startDesktopLyric();
    await rig.processes.single
        .emit(const msg.ControlEventMessage(msg.ControlEvent.taskbarLyrics));
    await _flush();
    expect(rig.preferences.value.taskbarLyrics, true);
    expect(rig.desktop.isRunning, false);
    expect(rig.writes.last['enabled'], true);
    expect(rig.saves, greaterThan(0));
  });

  test('disable while capability ack pending never attaches source or reopens',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    final gate = Completer<void>();
    rig.send = (payload) async {
      if (payload['enabled'] == true) await gate.future;
    };
    final opening = rig.taskbar.setEnabled(true);
    await _flush();
    final closing = rig.taskbar.setEnabled(false);
    gate.complete();
    expect(await opening, false);
    expect(await closing, true);
    expect(rig.factoryCalls, 0);
    expect(rig.writes.last['enabled'], false);
    expect(rig.preferences.value.taskbarLyrics, false);
  });

  test('dispose during capability ack drains native close without late source',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    final gate = Completer<void>();
    rig.send = (payload) async {
      if (payload['enabled'] == true) await gate.future;
    };
    final opening = rig.taskbar.setEnabled(true);
    await _flush();
    final closing = rig.taskbar.dispose();
    gate.complete();
    await closing;
    expect(await opening, false);
    expect(rig.factoryCalls, 0);
    expect(rig.writes.last['enabled'], false);
    final count = rig.writes.length;
    rig.preferences.value =
        rig.preferences.value.copyWith(taskbarLyrics: false);
    rig.readiness.value = false;
    rig.readiness.value = true;
    await _flush();
    expect(rig.writes.length, count);
  });

  test('desktop requested taskbar save failure reports once without zone error',
      () async {
    final rig = _Rig(ready: true);
    addTearDown(rig.dispose);
    rig.save = () async => throw const FileSystemException('fixture save');
    await rig.desktop.startDesktopLyric();
    await rig.processes.single
        .emit(const msg.ControlEventMessage(msg.ControlEvent.taskbarLyrics));
    await _flush();
    expect(rig.preferences.value.taskbarLyrics, true);
    expect(rig.writes.last['enabled'], true);
    expect(rig.errors.single, isA<TaskbarLyricPreferenceSaveError>());
    expect(rig.desktop.isRunning, false);
  });
}
