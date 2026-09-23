import 'dart:async';

import 'package:dan_player/play_service/guarded_playback_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pause during a slow open keeps the requested track positioned silently',
      () async {
    final opened = Completer<bool>();
    var playWhenReady = true;
    final calls = <String>[];
    final loading = guardedPlaybackSeek(
      isCurrent: () => true,
      open: () => opened.future,
      seek: () => calls.add('seek'),
      start: () => calls.add('start'),
      shouldStart: () => playWhenReady,
    );
    playWhenReady = false;
    opened.complete(true);
    expect(await loading, isFalse);
    expect(calls, ['seek']);
  });

  test('pause wins even when it arrives during the seek callback', () async {
    var playWhenReady = true;
    var starts = 0;
    expect(
      await guardedPlaybackSeek(
        isCurrent: () => true,
        open: () async => true,
        seek: () => playWhenReady = false,
        start: () => starts++,
        shouldStart: () => playWhenReady,
      ),
      isFalse,
    );
    expect(starts, 0);
  });

  test('a newer play before open completes resumes exactly once', () async {
    final opened = Completer<bool>();
    var playWhenReady = true;
    var starts = 0;
    final loading = guardedPlaybackSeek(
      isCurrent: () => true,
      open: () => opened.future,
      seek: () {},
      start: () => starts++,
      shouldStart: () => playWhenReady,
    );
    playWhenReady = false;
    playWhenReady = true;
    opened.complete(true);
    expect(await loading, isTrue);
    expect(starts, 1);
  });

  test('a newer play intention cannot revive an obsolete source request',
      () async {
    final opened = Completer<bool>();
    var current = true;
    var playWhenReady = true;
    final loading = guardedPlaybackSeek(
      isCurrent: () => current,
      open: () => opened.future,
      seek: () => fail('obsolete source must not seek'),
      start: () => fail('obsolete source must not start'),
      shouldStart: () => playWhenReady,
    );
    playWhenReady = false;
    current = false;
    playWhenReady = true;
    opened.complete(true);
    expect(await loading, isFalse);
  });
}
