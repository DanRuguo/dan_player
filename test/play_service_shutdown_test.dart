import 'dart:async';
import 'dart:io';

import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Playback extends Fake implements PlaybackService {
  _Playback(this.events);
  final List<String> events;
  int closes = 0;
  Completer<void>? holdClose;

  @override
  Future<void> close() async {
    closes++;
    events.add('player-close');
    await holdClose?.future;
    events.add('player-closed');
  }
}

class _DesktopLyric extends Fake implements DesktopLyricService {
  _DesktopLyric(this.events);
  final List<String> events;
  int disposals = 0;
  int kills = 0;
  bool throwOnDispose = false;
  Completer<void>? holdAppearanceSave;

  @override
  Future<void> flushAppearance() async => await holdAppearanceSave?.future;

  @override
  void dispose() {
    disposals++;
    events.add('helper-dispose');
    if (throwOnDispose) throw StateError('fake helper cleanup failed');
  }

  @override
  void killDesktopLyric() => kills++;
}

class _Lyric extends Fake implements LyricService {
  _Lyric(this.events);
  final List<String> events;
  int disposals = 0;
  bool throwOnDispose = false;

  @override
  void dispose() {
    disposals++;
    events.add('lyric-dispose');
    if (throwOnDispose) throw StateError('fake lyric cleanup failed');
  }
}

class _PendingProcess extends Fake implements Process {
  int kills = 0;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills++;
    return true;
  }
}

class _Harness {
  _Harness() {
    playback = _Playback(events);
    helper = _DesktopLyric(events);
    lyric = _Lyric(events);
    facade = PlayService.forTesting(
      readiness: ready,
      createPlayback: (owner) {
        expect(owner, same(facade));
        playbackCreations++;
        return playback;
      },
      createDesktopLyric: (owner) {
        expect(owner, same(facade));
        helperCreations++;
        return helper;
      },
      createLyric: (owner) {
        expect(owner, same(facade));
        lyricCreations++;
        return lyric;
      },
    );
  }

  final ready = PlaybackReadiness();
  final events = <String>[];
  late final _Playback playback;
  late final _DesktopLyric helper;
  late final _Lyric lyric;
  late final PlayService facade;
  int playbackCreations = 0;
  int helperCreations = 0;
  int lyricCreations = 0;

  (int, int, int) get creations =>
      (playbackCreations, helperCreations, lyricCreations);

  Future<void> cleanUp() async {
    final held = playback.holdClose;
    if (held != null && !held.isCompleted) held.complete();
    try {
      await facade.close();
    } catch (_) {
      // A deliberate disposal failure is asserted by its owning test.
    }
    ready.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('lazy facade shutdown without native audio', () {
    late _Harness rig;
    setUp(() => rig = _Harness());
    tearDown(() => rig.cleanUp());

    test('cold facade close creates no player, helper, lyric or global facade',
        () async {
      expect(PlayService.hasFacade, isFalse);
      expect(PlayService.isInitialized, isFalse);
      expect(rig.creations, (0, 0, 0));
      await rig.facade.close();
      expect(rig.creations, (0, 0, 0));
      expect(rig.events, isEmpty);
      expect(rig.ready.value, isFalse);
      expect(PlayService.hasFacade, isFalse);
    });

    test('helper-only facade disposes the helper without creating BASS',
        () async {
      expect(rig.facade.desktopLyricService, same(rig.helper));
      expect(rig.ready.value, isFalse);
      await rig.facade.close();
      expect(rig.creations, (0, 1, 0));
      expect(rig.helper.disposals, 1);
      expect(rig.playback.closes, 0);
      expect(rig.events, ['helper-dispose']);
      expect(rig.ready.value, isFalse);
    });

    test('owned player closes even before its ready microtask is published',
        () async {
      var notices = 0;
      void listener() => notices++;
      rig.ready.addListener(listener);
      expect(rig.facade.playbackService, same(rig.playback));
      expect(rig.ready.value, isFalse);
      final closing = rig.facade.close();
      expect(rig.playback.closes, 1);
      await closing;
      await Future<void>.value();
      expect(rig.creations, (1, 0, 0));
      expect(rig.ready.value, isFalse);
      expect(notices, 0);
      rig.ready.removeListener(listener);
    });

    test('successful construction still publishes once after getter assignment',
        () async {
      late PlaybackService assigned;
      var notices = 0;
      rig.ready.addListener(() {
        expect(assigned, same(rig.playback));
        expect(rig.facade.playbackService, same(assigned));
        notices++;
      });
      assigned = rig.facade.playbackService;
      expect(notices, 0);
      await Future<void>.value();
      expect(rig.ready.value, isTrue);
      expect(notices, 1);
      expect(rig.facade.playbackService, same(assigned));
      expect(rig.creations, (1, 0, 0));
      await rig.facade.close();
      expect(notices, 1);
      expect(rig.playback.closes, 1);
    });

    test('startup initialization eagerly constructs playback exactly once',
        () async {
      rig.facade.ensurePlaybackInitialized();
      rig.facade.ensurePlaybackInitialized();
      expect(rig.creations, (1, 0, 0));
      expect(rig.ready.value, isFalse);
      await Future<void>.value();
      expect(rig.ready.value, isTrue);
      expect(rig.facade.playbackService, same(rig.playback));
    });

    test('repeated close shares cleanup and disposes helper before player',
        () async {
      rig.facade.desktopLyricService;
      rig.facade.playbackService;
      rig.playback.holdClose = Completer<void>();
      var completed = false;
      final first = rig.facade.close();
      final second = rig.facade.close();
      expect(first, same(second));
      unawaited(first.then<void>((_) {
        completed = true;
      }));
      await Future<void>.value();
      expect(completed, isFalse);
      expect(rig.events, ['helper-dispose', 'player-close']);
      rig.playback.holdClose!.complete();
      await Future.wait([first, second]);
      expect(completed, isTrue);
      expect(rig.helper.disposals, 1);
      expect(rig.playback.closes, 1);
      expect(rig.events, ['helper-dispose', 'player-close', 'player-closed']);
    });

    test('helper disposal failure cannot skip the already owned player cleanup',
        () async {
      rig.facade.desktopLyricService;
      rig.facade.playbackService;
      rig.helper.throwOnDispose = true;
      final closing = rig.facade.close();
      await expectLater(closing, throwsStateError);
      expect(rig.events, ['helper-dispose', 'player-close', 'player-closed']);
      expect(rig.facade.close(), same(closing));
      expect(rig.helper.disposals, 1);
      expect(rig.playback.closes, 1);
    });

    test('owned lyric closes before helper and player exactly once', () async {
      rig.facade.lyricService;
      rig.facade.desktopLyricService;
      rig.facade.playbackService;
      await rig.facade.close();
      await rig.facade.close();
      expect(rig.events,
          ['lyric-dispose', 'helper-dispose', 'player-close', 'player-closed']);
      expect(rig.lyric.disposals, 1);
      expect(rig.helper.disposals, 1);
      expect(rig.playback.closes, 1);
    });

    test('lyric disposal failure still cleans both helper and player',
        () async {
      rig.facade.lyricService;
      rig.facade.desktopLyricService;
      rig.facade.playbackService;
      rig.lyric.throwOnDispose = true;
      await expectLater(rig.facade.close(), throwsStateError);
      expect(rig.events,
          ['lyric-dispose', 'helper-dispose', 'player-close', 'player-closed']);
      expect(rig.lyric.disposals, 1);
      expect(rig.helper.disposals, 1);
      expect(rig.playback.closes, 1);
    });

    test('closed cold facade rejects every new lazy getter', () async {
      await rig.facade.close();
      expect(() => rig.facade.playbackService, throwsStateError);
      expect(() => rig.facade.desktopLyricService, throwsStateError);
      expect(() => rig.facade.lyricService, throwsStateError);
      expect(rig.creations, (0, 0, 0));
      expect(rig.ready.value, isFalse);
    });

    test('closing player blocks new resources throughout asynchronous cleanup',
        () async {
      final existing = rig.facade.playbackService;
      rig.playback.holdClose = Completer<void>();
      final closing = rig.facade.close();
      expect(() => rig.facade.desktopLyricService, throwsStateError);
      expect(() => rig.facade.lyricService, throwsStateError);
      // Existing consumers may detach while cleanup is awaiting the player.
      expect(rig.facade.playbackService, same(existing));
      expect(rig.creations, (1, 0, 0));
      rig.playback.holdClose!.complete();
      await closing;
      expect(rig.ready.value, isFalse);
    });

    test('ordinary helper close does not close the facade or its lazy player',
        () async {
      final helper = rig.facade.desktopLyricService;
      helper.killDesktopLyric();
      expect(rig.helper.kills, 1);
      expect(rig.helper.disposals, 0);
      expect(rig.facade.desktopLyricService, same(helper));
      expect(rig.facade.playbackService, same(rig.playback));
      await Future<void>.value();
      expect(rig.ready.value, isTrue);
      expect(rig.playback.closes, 0);
    });
  });

  test('failed lazy construction is not cached and can retry before close',
      () async {
    final ready = PlaybackReadiness();
    final playback = _Playback([]);
    var attempts = 0;
    final facade = PlayService.forTesting(
      readiness: ready,
      createPlayback: (_) {
        attempts++;
        if (attempts == 1) throw StateError('fake constructor failed');
        return playback;
      },
      createDesktopLyric: (_) => throw StateError('must not construct helper'),
    );
    addTearDown(() async {
      await facade.close();
      ready.dispose();
    });
    expect(() => facade.playbackService, throwsStateError);
    await Future<void>.value();
    expect(ready.value, isFalse);
    expect(facade.playbackService, same(playback));
    expect(ready.value, isFalse);
    await Future<void>.value();
    expect(ready.value, isTrue);
    expect(attempts, 2);
  });

  test('closing a facade cancels its real pending lyric-helper launch',
      () async {
    final ready = PlaybackReadiness();
    final pending = Completer<Process>();
    final process = _PendingProcess();
    var playerCreations = 0;
    final facade = PlayService.forTesting(
      readiness: ready,
      createPlayback: (_) {
        playerCreations++;
        throw StateError('cold lyric exit must not create BASS');
      },
      createDesktopLyric: (owner) => DesktopLyricService(
        owner,
        executableExists: (_) => true,
        startProcess: (_, __) => pending.future,
      ),
    );
    addTearDown(() async {
      await facade.close();
      if (!pending.isCompleted) pending.complete(process);
      ready.dispose();
    });
    final helper = facade.desktopLyricService;
    final launching = helper.startDesktopLyric();
    expect(helper.state, DesktopLyricState.starting);
    await facade.close();
    pending.complete(process);
    await launching;
    expect(helper.state, DesktopLyricState.stopped);
    expect(helper.isRunning, isFalse);
    expect(process.kills, 1);
    expect(playerCreations, 0);
    expect(ready.value, isFalse);
    expect(PlayService.playbackReady.value, isFalse);
  });
}
