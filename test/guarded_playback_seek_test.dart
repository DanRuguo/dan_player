import 'dart:async';
import 'package:dan_player/play_service/guarded_playback_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('awaits opened CUE source, applies relative offset once, then starts',
      () async {
    final opened = Completer<bool>();
    final calls = <String>[];
    final job = guardedPlaybackSeek(
        isCurrent: () => true,
        open: () {
          calls.add('open');
          return opened.future;
        },
        seek: () => calls.add('seek 12.4'),
        start: () => calls.add('start'));
    expect(calls, ['open']);
    opened.complete(true);
    expect(await job, isTrue);
    expect(calls, ['open', 'seek 12.4', 'start']);
  });
  test('old open and synchronous seek callback cannot seek/start a new session',
      () async {
    var current = true;
    final opened = Completer<bool>();
    var seeks = 0, starts = 0;
    final job = guardedPlaybackSeek(
        isCurrent: () => current,
        open: () => opened.future,
        seek: () => seeks++,
        start: () => starts++);
    current = false;
    opened.complete(true);
    expect(await job, isFalse);
    expect([seeks, starts], [0, 0]);
    current = true;
    expect(
        await guardedPlaybackSeek(
            isCurrent: () => current,
            open: () async => true,
            seek: () {
              seeks++;
              current = false;
            },
            start: () => starts++),
        isFalse);
    expect([seeks, starts], [1, 0]);
  });
  test('invalid or failed open does not seek and seek failure never starts',
      () async {
    var opened = 0, started = 0;
    expect(
        await guardedPlaybackSeek(
            isCurrent: () => false,
            open: () async {
              opened++;
              return true;
            },
            seek: () {},
            start: () => started++),
        isFalse);
    expect(opened, 0);
    expect(
        await guardedPlaybackSeek(
            isCurrent: () => true,
            open: () async => false,
            seek: () => fail('must not seek'),
            start: () => started++),
        isFalse);
    await expectLater(
        guardedPlaybackSeek(
            isCurrent: () => true,
            open: () async => true,
            seek: () => throw StateError('seek failed'),
            start: () => started++),
        throwsStateError);
    expect(started, 0);
  });
}
