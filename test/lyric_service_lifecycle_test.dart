import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/play_service/desktop_lyric_service.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _Audio extends Fake implements Audio {
  @override
  String get path => 'synthetic-lyric-lifecycle-not-opened.wav';
  @override
  bool get isOnline => false;
}

class _Lyric extends Lyric {
  _Lyric(super.lines);
}

Lyric _sampleLyric() => _Lyric([
      LrcLine(Duration.zero, 'Synthetic first line', isBlank: false),
      LrcLine(const Duration(seconds: 2), 'Synthetic second line',
          isBlank: false),
    ]);

class _Playback extends Fake implements PlaybackService {
  final positions = StreamController<double>.broadcast(sync: true);
  final audio = _Audio();
  double currentPosition = 0;
  int positionReads = 0;
  int audioReads = 0;
  int closes = 0;

  @override
  Stream<double> get positionStream => positions.stream;
  @override
  double get position {
    positionReads++;
    return currentPosition;
  }

  @override
  Audio? get nowPlaying {
    audioReads++;
    return audio;
  }

  @override
  Future<void> close() async => closes++;
}

class _Desktop extends Fake implements DesktopLyricService {
  Completer<bool>? readiness;
  int disposals = 0;
  int checks = 0;
  int timelines = 0;
  int missing = 0;
  final lines = <int>[];

  @override
  Future<bool> get canSendMessage {
    checks++;
    return readiness?.future ?? Future.value(true);
  }

  @override
  void sendPlaybackTimelineMessage() => timelines++;
  @override
  void sendNoLyricMessage() => missing++;
  @override
  void sendLyricLineMessage(LyricLine line, {required int lineIndex}) =>
      lines.add(lineIndex);
  @override
  void dispose() => disposals++;
  @override
  Future<void> flushAppearance() async {}
}

class _Harness {
  _Harness() {
    facade = PlayService.forTesting(
      readiness: ready,
      createPlayback: (_) {
        playerCreations++;
        return playback;
      },
      createDesktopLyric: (_) {
        helperCreations++;
        return desktop;
      },
      createLyric: (owner) =>
          LyricService.forTesting(owner, resolveDefaultLyric: (localFirst) {
        requests++;
        return resolve(localFirst);
      }),
    );
    service = facade.lyricService;
  }

  final ready = PlaybackReadiness();
  final playback = _Playback();
  final desktop = _Desktop();
  Future<Lyric?> Function(bool) resolve = (_) async => null;
  late final PlayService facade;
  late final LyricService service;
  int playerCreations = 0;
  int helperCreations = 0;
  int requests = 0;

  Future<void> cleanUp() async {
    await facade.close();
    await playback.positions.close();
    ready.dispose();
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Harness rig;
  setUp(() => rig = _Harness());
  tearDown(() => rig.cleanUp());

  for (final failed in [false, true]) {
    test('pending lyric ${failed ? 'failure' : 'success'} after close is inert',
        () async {
      final readyBeforeClose = rig.ready.value;
      var readyNotices = 0;
      void onReady() => readyNotices++;
      rig.ready.addListener(onReady);
      addTearDown(() => rig.ready.removeListener(onReady));
      final pending = Completer<Lyric?>();
      rig.resolve = (_) => pending.future;
      rig.service.updateLyric();
      rig.service.findCurrLyricLine();
      final sync = rig.service.syncDesktopLyric();
      await rig.facade.close();
      final oldReads = rig.playback.positionReads;
      if (failed) {
        pending.completeError(StateError('synthetic late lyric failure'));
      } else {
        pending.complete(_sampleLyric());
      }
      await sync;
      await _flush();
      expect(rig.helperCreations, 0);
      expect(rig.playerCreations, 1);
      expect(rig.playback.closes, 1);
      expect(rig.playback.positionReads, oldReads);
      expect(rig.playback.positions.hasListener, isFalse);
      expect(rig.desktop.lines, isEmpty);
      expect(rig.desktop.missing, 0);
      // setUp may already have published the successfully constructed fake
      // player. Closing must not introduce a new publication or reset history.
      expect(rig.ready.value, readyBeforeClose);
      expect(readyNotices, 0);
    });
  }

  test('dispose is idempotent and late positions have no observers', () async {
    final received = <int>[];
    final subscription = rig.service.lyricLineStream.listen(received.add);
    expect(rig.playback.positions.hasListener, isTrue);
    rig.service.dispose();
    rig.service.dispose();
    rig.playback.positions.add(30);
    await _flush();
    expect(received, isEmpty);
    expect(rig.playback.positions.hasListener, isFalse);
    expect(rig.helperCreations, 0);
    expect(await rig.service.lyricLineStream.toList(), isEmpty);
    await subscription.cancel();
  });

  test('every disposed entry point avoids new getters and lyric requests',
      () async {
    await rig.facade.close();
    final oldAudioReads = rig.playback.audioReads;
    final oldPositionReads = rig.playback.positionReads;
    rig.service.updateLyric();
    rig.service.useLocalLyric();
    rig.service.useOnlineLyric();
    rig.service.useSpecificLyric(_sampleLyric());
    rig.service.findCurrLyricLine();
    await rig.service.syncDesktopLyric();
    await _flush();
    expect(rig.requests, 0);
    expect(rig.helperCreations, 0);
    expect(rig.playback.audioReads, oldAudioReads);
    expect(rig.playback.positionReads, oldPositionReads);
  });

  for (final failed in [false, true]) {
    test('late desktop capability ${failed ? 'failure' : 'success'} is ignored',
        () async {
      final pending = Completer<bool>();
      rig.desktop.readiness = pending;
      rig.service.useSpecificLyric(_sampleLyric());
      await _flush();
      expect(rig.desktop.checks, 1);
      expect(rig.helperCreations, 1);
      await rig.facade.close();
      if (failed) {
        pending.completeError(StateError('synthetic helper failure'));
      } else {
        pending.complete(true);
      }
      await _flush();
      expect(rig.desktop.lines, isEmpty);
      expect(rig.desktop.timelines, 0);
      expect(rig.desktop.disposals, 1);
      expect(rig.helperCreations, 1);
    });
  }

  test('normal position updates and immediate desktop sync stay correct',
      () async {
    final received = <int>[];
    final subscription = rig.service.lyricLineStream.listen(received.add);
    rig.service.useSpecificLyric(_sampleLyric());
    await _flush();
    rig.playback.currentPosition = 2.2;
    rig.playback.positions.add(2.2);
    await _flush();
    rig.playback.positions.add(2.5);
    await _flush();
    expect(received, [0, 1]);
    expect(rig.desktop.lines, [0, 1]);
    await rig.service.syncDesktopLyric();
    expect(rig.desktop.lines, [0, 1, 1]);
    expect(rig.desktop.timelines, 3);
    expect(rig.playerCreations, 1);
    expect(rig.helperCreations, 1);
    await subscription.cancel();
  });

  test('a stale track future cannot overwrite the newer tracked lyric',
      () async {
    final old = Completer<Lyric?>();
    final current = Completer<Lyric?>();
    rig.resolve = (_) => old.future;
    rig.service.updateLyric();
    rig.resolve = (_) => current.future;
    rig.service.updateLyric();
    current.complete(_sampleLyric());
    await _flush();
    expect(rig.desktop.lines, [0]);
    old.complete(null);
    await _flush();
    expect(rig.desktop.lines, [0]);
    expect(rig.desktop.missing, 0);
  });

  test('late canSend does not send a previously passed line of the same lyric',
      () async {
    final pending = Completer<bool>();
    rig.desktop.readiness = pending;
    rig.service.useSpecificLyric(_sampleLyric());
    await _flush();
    rig.playback.currentPosition = 2.2;
    rig.playback.positions.add(2.2);
    pending.complete(true);
    await _flush();
    expect(rig.desktop.lines, [1]);
  });

  test('an empty lyric still sends the normal missing-lyric message', () async {
    rig.service.useSpecificLyric(_Lyric([]));
    await _flush();
    expect(rig.desktop.missing, 1);
    expect(rig.desktop.lines, isEmpty);
    expect(rig.helperCreations, 1);
  });

  test('a candidate captured for another track is never applied', () async {
    var notifications = 0;
    void onChanged() => notifications++;
    rig.service.addListener(onChanged);
    addTearDown(() => rig.service.removeListener(onChanged));

    final applied = rig.service.useSpecificLyricForTrack(
      'different-track.wav',
      _sampleLyric(),
    );
    await _flush();

    expect(applied, isFalse);
    expect(notifications, 0);
    expect(await rig.service.currLyricFuture, isNull);
    expect(rig.desktop.lines, isEmpty);
  });

  test('a candidate is applied when its captured path is still current',
      () async {
    final lyric = _sampleLyric();
    final applied = rig.service.useSpecificLyricForTrack(
      rig.playback.audio.path,
      lyric,
    );
    await _flush();

    expect(applied, isTrue);
    expect(await rig.service.currLyricFuture, same(lyric));
    expect(rig.desktop.lines, [0]);
  });

  test('local-source selection also rejects a stale captured path', () async {
    var notifications = 0;
    void onChanged() => notifications++;
    rig.service.addListener(onChanged);
    addTearDown(() => rig.service.removeListener(onChanged));

    expect(rig.service.useLocalLyricForTrack('different-track.wav'), isFalse);
    await _flush();
    expect(notifications, 0);
    expect(await rig.service.currLyricFuture, isNull);
  });
}
