import 'dart:async';
import 'dart:io';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late OnlineLyricCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-lyric-handoff-');
    cache = OnlineLyricCache(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));

  Lyric line(String text) => Lrc.fromLrcText('[00:01.00]$text', LrcSource.web)!;
  String text(Lyric? lyric) => (lyric!.lines.single as UnsyncLyricLine).content;

  for (final refresh in [false, true]) {
    test('a new request bypasses a superseded lookup (refresh: $refresh)',
        () async {
      var active = true;
      final started = Completer<void>();
      final pending = Completer<Lyric?>();
      final stale = cache.resolve('track', () {
        started.complete();
        return pending.future;
      }, shouldStore: () => active);
      await started.future;
      active = false;
      var calls = 0;
      final current = cache.resolve('track', () async {
        calls++;
        return line('current');
      }, refresh: refresh);
      // Keep the old provider stalled: a current choice must finish without it.
      try {
        expect(
            text(await current.timeout(const Duration(seconds: 2))), 'current');
        expect(calls, 1);
      } finally {
        pending.complete(line('stale'));
        await stale;
        await current;
      }
      expect(await stale, isNull);
      expect(text(await cache.read('track')), 'current');
    });
  }

  test('a shared lookup invalidated while waiting retries for its live reader',
      () async {
    var active = true;
    final started = Completer<void>();
    final pending = Completer<Lyric?>();
    final first = cache.resolve('track', () {
      started.complete();
      return pending.future;
    }, shouldStore: () => active);
    await started.future;
    var calls = 0;
    final second = cache.resolve('track', () async {
      calls++;
      return line('second');
    });
    active = false;
    pending.complete(line('first'));
    expect(await first, isNull);
    expect(text(await second), 'second');
    expect(calls, 1);
    expect(text(await cache.read('track')), 'second');
  });

  test('an invalidated shared reader does not restart provider work', () async {
    var firstActive = true;
    var secondActive = true;
    final started = Completer<void>();
    final pending = Completer<Lyric?>();
    final first = cache.resolve('track', () {
      started.complete();
      return pending.future;
    }, shouldStore: () => firstActive);
    await started.future;
    var calls = 0;
    final second = cache.resolve('track', () async {
      calls++;
      return line('second');
    }, shouldStore: () => secondActive);
    firstActive = false;
    secondActive = false;
    pending.complete(line('first'));
    expect(await first, isNull);
    expect(await second, isNull);
    expect(calls, 0);
    expect(await cache.read('track'), isNull);
  });

  test('a superseded provider failure cannot poison a live shared reader',
      () async {
    var active = true;
    final started = Completer<void>();
    final pending = Completer<Lyric?>();
    final first = cache.resolve('track', () {
      started.complete();
      return pending.future;
    }, shouldStore: () => active);
    final oldFailure = expectLater(first, throwsStateError);
    await started.future;
    final second = cache.resolve('track', () async => line('second'));
    active = false;
    pending.completeError(StateError('superseded provider failed'));
    await oldFailure;
    expect(text(await second), 'second');
    expect(text(await cache.read('track')), 'second');
  });
}
