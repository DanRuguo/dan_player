import 'dart:async';
import 'dart:convert';

import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final rate in [.5, .75, 1.0, 1.25, 1.5, 1.75, 2.0]) {
    test('$rate x extrapolates media time, not lyric timestamps', () {
      var now = 1000;
      final clock =
          PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
      addTearDown(clock.dispose);
      clock.sync(PlaybackTimelineMessage(1, 20000, true, playbackRate: rate));
      now += 1000;
      expect(clock.positionMilliseconds, 20000 + (rate * 1000).round());
      expect(clock.playbackRate, rate);
    });
  }

  test('old playback JSON defaults to 1x and retains existing keys', () {
    final message = PlaybackTimelineMessage.fromJson({
      'sequence': 7,
      'positionMilliseconds': 12345,
      'playing': true,
    });
    expect(message.playbackRate, 1);
    final jsonMap = json.decode(message.buildMessageJson())['message'];
    expect(jsonMap['sequence'], 7);
    expect(jsonMap['positionMilliseconds'], 12345);
    expect(jsonMap['playing'], true);
    expect(jsonMap['playbackRate'], 1);
  });

  test('old init JSON stays horizontal; new init carries rate and orientation',
      () {
    const initial = InitArgsMessage(false, 'title', 'artist', 'album', true,
        0xff112233, 0xff223344, 0xffeeeeee);
    final oldMap = initial.toJson()
      ..remove('vertical')
      ..remove('playbackRate');
    final old = InitArgsMessage.fromJson(oldMap);
    expect(old.vertical, false);
    expect(old.playbackRate, 1);
    const newArgs = InitArgsMessage(true, 'new title', 'new artist',
        'new album', false, 0xff112233, 0xff223344, 0xffeeeeee,
        vertical: true, playbackRate: 1.75);
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
    );
    addTearDown(controller.dispose);
    controller.applyInitialState(InitArgsMessage.fromJson(newArgs.toJson()));
    expect(controller.vertical.value, true);
    expect(controller.playbackClock.playbackRate, 1.75);
    expect(controller.playbackClock.playing, true);
    expect(controller.nowPlaying.value.title, 'new title');
  });

  test('rate switch reanchors at actual position with no multiplier on anchor',
      () {
    var now = 0;
    final clock =
        PlaybackClock(nowMilliseconds: () => now, automaticTicks: false);
    addTearDown(clock.dispose);
    clock.sync(const PlaybackTimelineMessage(1, 30000, true));
    now = 1000;
    expect(clock.positionMilliseconds, 31000);
    clock.sync(const PlaybackTimelineMessage(1, 31000, true, playbackRate: 2));
    expect(clock.positionMilliseconds, 31000);
    now = 1500;
    expect(clock.positionMilliseconds, 32000);
    clock.sync(const PlaybackTimelineMessage(1, 32000, true, playbackRate: .5));
    now = 2500;
    expect(clock.positionMilliseconds, 32500);
  });

  test(
      'pause freezes and successful paused seek immediately notifies real time',
      () {
    var now = 0;
    var notifications = 0;
    final clock =
        PlaybackClock(nowMilliseconds: () => now, automaticTicks: false)
          ..addListener(() => notifications++);
    addTearDown(clock.dispose);
    clock.sync(const PlaybackTimelineMessage(1, 4000, true, playbackRate: 2));
    now = 1000;
    clock.setPlaying(false);
    expect(clock.positionMilliseconds, 6000);
    now = 9000;
    expect(clock.positionMilliseconds, 6000);
    final before = notifications;
    clock.sync(const PlaybackTimelineMessage(1, 1250, false, playbackRate: 2));
    expect(notifications, before + 1);
    expect(clock.positionMilliseconds, 1250);
    expect(clock.playing, false);
    now = 20000;
    expect(clock.positionMilliseconds, 1250);
    clock.setPlaying(true);
    now = 21000;
    expect(clock.positionMilliseconds, 3250);
  });

  test('invalid rate fields are bounded or reset without invalid clocks', () {
    expect(safeDesktopPlaybackRate(double.nan), 1);
    expect(safeDesktopPlaybackRate(double.infinity), 1);
    expect(safeDesktopPlaybackRate('2.0'), 1);
    expect(safeDesktopPlaybackRate(-2), .5);
    expect(safeDesktopPlaybackRate(99), 2);
    final clock =
        PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false);
    addTearDown(clock.dispose);
    clock.sync(const PlaybackTimelineMessage(1, -1000, true,
        playbackRate: double.nan));
    expect(clock.positionMilliseconds, 0);
    expect(clock.playbackRate, 1);
  });

  test('older song sequence cannot replace clock, rate or lyric', () {
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
    );
    addTearDown(controller.dispose);
    void send(Message message) =>
        controller.handleMessage(message.buildMessageJson());
    send(const PlaybackTimelineMessage(7, 9000, false, playbackRate: 1.75));
    send(const LyricLineTimelineMessage(
        sequence: 7,
        lineIndex: 2,
        startMilliseconds: 8000,
        lengthMilliseconds: 3000,
        content: '新歌',
        translation: null,
        words: []));
    send(const PlaybackTimelineMessage(6, 50000, true, playbackRate: .5));
    send(const LyricLineTimelineMessage(
        sequence: 6,
        lineIndex: 12,
        startMilliseconds: 48000,
        lengthMilliseconds: 3000,
        content: '旧歌',
        translation: null,
        words: []));
    expect(controller.activeSequence, 7);
    expect(controller.playbackClock.positionMilliseconds, 9000);
    expect(controller.playbackClock.playing, false);
    expect(controller.playbackClock.playbackRate, 1.75);
    expect(controller.detailedLyricLine.value!.content, '新歌');
  });

  test('orientation messages do not reset rate, position or paused state', () {
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
    );
    addTearDown(controller.dispose);
    controller.handleMessage(
        const PlaybackTimelineMessage(4, 13500, false, playbackRate: 1.5)
            .buildMessageJson());
    for (final vertical in [true, false, true]) {
      controller.handleMessage(
          DesktopLyricDisplayMessage(vertical: vertical).buildMessageJson());
      expect(controller.vertical.value, vertical);
      expect(controller.playbackClock.positionMilliseconds, 13500);
      expect(controller.playbackClock.playbackRate, 1.5);
      expect(controller.playbackClock.playing, false);
    }
    final encoded = const DesktopLyricDisplayChangedMessage(vertical: true)
        .buildMessageJson();
    expect(
        DesktopLyricDisplayChangedMessage.fromJson(
                Map<String, dynamic>.from(json.decode(encoded)['message']))
            .vertical,
        true);
  });

  test(
      'lock/unlock targets injected own window and late completion is harmless',
      () async {
    final requested = <bool>[];
    final pending = <Completer<void>>[];
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
      setIgnoreMouseEvents: (value) {
        requested.add(value);
        final result = Completer<void>();
        pending.add(result);
        return result.future;
      },
    );
    final lock = controller.setLocked(true);
    final unlock = controller.setLocked(false);
    pending[1].complete();
    await unlock;
    pending[0].complete();
    await lock;
    expect(requested, [true, false]);
    expect(controller.locked.value, false);
    final lateLock = controller.setLocked(true);
    controller.dispose();
    pending[2].complete();
    await expectLater(lateLock, completes);
  });

  test('lock failure does not claim the window is locked', () async {
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
      setIgnoreMouseEvents: (_) async => throw StateError('fixture failure'),
    );
    addTearDown(controller.dispose);
    await expectLater(controller.setLocked(true), throwsStateError);
    expect(controller.locked.value, false);
  });

  test('stdin EOF closes the own window once and freezes the media clock',
      () async {
    final input = StreamController<List<int>>();
    final pendingClose = Completer<void>();
    var closes = 0;
    var now = 0;
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => now, automaticTicks: false),
      input: input.stream,
      closeWindow: () {
        closes++;
        return pendingClose.future;
      },
    );
    input.add(utf8.encode(
        const PlaybackTimelineMessage(1, 2000, true, playbackRate: 1.5)
            .buildMessageJson()));
    await Future<void>.delayed(Duration.zero);
    expect(controller.playbackClock.playing, true);
    now = 200;
    await input.close();
    expect(closes, 1);
    expect(controller.inputClosed, true);
    expect(controller.playbackClock.playing, false);
    expect(controller.playbackClock.positionMilliseconds, 2300);
    now = 9000;
    controller.handleMessage(
        const PlayerStateChangedMessage(true).buildMessageJson());
    expect(controller.playbackClock.positionMilliseconds, 2300);
    controller.dispose();
    controller.dispose();
    pendingClose.complete();
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
  });

  test('pause and direction messages do not close an attached helper',
      () async {
    final input = StreamController<List<int>>();
    var closes = 0;
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
      input: input.stream,
      closeWindow: () async => closes++,
    );
    addTearDown(controller.dispose);
    input.add(utf8.encode([
      const PlayerStateChangedMessage(false).buildMessageJson(),
      const DesktopLyricDisplayMessage(vertical: true).buildMessageJson(),
    ].join()));
    await Future<void>.delayed(Duration.zero);
    expect(controller.vertical.value, true);
    expect(controller.inputClosed, false);
    expect(closes, 0);
    await input.close();
    expect(closes, 1);
  });

  test('disposing cancels stdin without dispatching an EOF close', () async {
    final input = StreamController<List<int>>();
    var closes = 0;
    final controller = DesktopLyricController.detached(
      clock: PlaybackClock(nowMilliseconds: () => 0, automaticTicks: false),
      input: input.stream,
      closeWindow: () async => closes++,
    );
    controller.dispose();
    await input.close();
    expect(closes, 0);
  });
}
