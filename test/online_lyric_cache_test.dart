import 'dart:async';
import 'dart:io';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late OnlineLyricCache cache;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dan-online-lyrics-');
    cache = OnlineLyricCache(directory: () async => directory);
  });
  tearDown(() => directory.delete(recursive: true));
  Lyric line(String text) => Lrc.fromLrcText('[00:01.00]$text', LrcSource.web)!;

  test('restart reads word timing offline and returns independent models',
      () async {
    final original =
        Qrc.fromQrcText('[1000,2000]Hello(1000,700) world(1700,1300)', null);
    await cache.resolve('track/provider', () async => original);
    cache = OnlineLyricCache(directory: () async => directory);
    var calls = 0;
    Future<Lyric?> offline() async {
      calls++;
      throw StateError('offline');
    }

    final first = (await cache.resolve('track/provider', offline))!;
    final second = (await cache.resolve('track/provider', offline))!;
    expect(calls, 0);
    expect(first, isA<Qrc>());
    final words = (first.lines.first as SyncLyricLine).words;
    expect(words.last.start.inMilliseconds, 1700);
    expect(words.last.length.inMilliseconds, 1300);
    expect(identical(first, second), isFalse);
    expect(identical(first.lines, second.lines), isFalse);
  });

  test('concurrent playback shares fetch; forced search replaces saved result',
      () async {
    final pending = Completer<Lyric?>();
    var calls = 0;
    final first = cache.resolve('same', () {
      calls++;
      return pending.future;
    });
    final second = cache.resolve('same', () {
      calls++;
      return pending.future;
    });
    final refresh =
        cache.resolve('same', () async => line('new'), refresh: true);
    pending.complete(line('old'));
    await Future.wait([first, second, refresh]);
    final saved =
        await cache.resolve('same', () async => throw StateError('network'));
    expect(calls, 1);
    expect((saved!.lines.first as UnsyncLyricLine).content, 'new');
  });

  test('failures are retried, changed metadata/source has separate result',
      () async {
    expect(await cache.resolve('a', () async => null), isNull);
    await cache.resolve('a', () async => line('a'));
    final b = await cache.resolve('b', () async => line('b'));
    expect((b!.lines.first as UnsyncLyricLine).content, 'b');
    expect(directory.listSync().whereType<File>().length, 2);
  });

  test('corrupt cache and unavailable storage do not prevent playback',
      () async {
    await cache.resolve('a', () async => line('a'));
    await directory
        .listSync()
        .whereType<File>()
        .single
        .writeAsString('{broken');
    final repaired = await cache.resolve('a', () async => line('repaired'));
    expect((repaired!.lines.first as UnsyncLyricLine).content, 'repaired');
    final unavailable = OnlineLyricCache(
        directory: () async => throw const FileSystemException('denied'));
    expect(
        await unavailable.resolve('a', () async => line('online')), isNotNull);
  });
}
