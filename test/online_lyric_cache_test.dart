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
  String contentOf(Lyric lyric) =>
      (lyric.lines.single as UnsyncLyricLine).content;
  Future<int> savedBytes() async {
    var result = 0;
    await for (final file in directory.list(followLinks: false)) {
      if (file is File && file.path.endsWith('.json')) {
        result += await file.length();
      }
    }
    return result;
  }

  Future<int> seedBudget() async {
    await cache.resolve('seed', () async => line('a' * 32));
    return savedBytes();
  }

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
    final noSearch = await cache.read('track/provider');
    expect(noSearch, isA<Qrc>());
    expect(await cache.read('unknown/provider'), isNull);
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

  test('successive lyric writes enforce total bytes without a maintenance wait',
      () async {
    final entryBytes = await seedBudget();
    final cap = entryBytes * 2 + 8;
    cache = OnlineLyricCache(
        directory: () async => directory, totalBytesLimit: cap);
    for (var index = 0; index < 4; index++) {
      final identity = 'sequential-$index';
      final content = String.fromCharCode(98 + index) * 32;
      await cache.resolve(identity, () async => line(content));
      expect(await savedBytes(), lessThanOrEqualTo(cap),
          reason: 'Each completed write must honor the total cache budget');
      expect(contentOf((await cache.read(identity))!), content,
          reason: 'The newest fitting entry must remain usable offline');
    }
  });

  test('refresh accounts for a replaced corrupt file and preserves fresh ink',
      () async {
    final entryBytes = await seedBudget();
    final cap = entryBytes * 3 + 32;
    cache = OnlineLyricCache(
        directory: () async => directory, totalBytesLimit: cap);
    await cache.resolve('replace', () async => line('b' * 32));
    await cache.resolve('other', () async => line('c' * 32));
    final replaced = (await directory.list(followLinks: false).toList())
        .whereType<File>()
        .singleWhere((file) => file.readAsStringSync().contains('b' * 32));
    await replaced.writeAsString('{broken ${'x' * 512}');
    final replacement = 'd' * 128;
    final fetched = await cache
        .resolve('replace', () async => line(replacement), refresh: true);
    expect(contentOf(fetched!), replacement);
    expect(await savedBytes(), lessThanOrEqualTo(cap));
    expect(contentOf((await cache.read('replace'))!), replacement);
    expect(
        directory
            .listSync()
            .whereType<File>()
            .any((file) => file.path.endsWith('.tmp')),
        isFalse);
  });

  test('parallel lyric identities keep atomic snapshots within the total cap',
      () async {
    final entryBytes = await seedBudget();
    final cap = entryBytes * 2 + 8;
    cache = OnlineLyricCache(
        directory: () async => directory, totalBytesLimit: cap);
    final completions = <Lyric?>[];
    for (var pair = 0; pair < 3; pair++) {
      completions.addAll(await Future.wait([
        for (var side = 0; side < 2; side++)
          cache.resolve('parallel-$pair-$side',
              () async => line(String.fromCharCode(98 + pair * 2 + side) * 32))
      ]));
      expect(await savedBytes(), lessThanOrEqualTo(cap),
          reason: 'Concurrent completed renames must share one byte budget');
    }
    expect(completions, hasLength(6));
    expect(completions.every((lyric) => lyric != null), isTrue,
        reason: 'Evicting snapshots must not discard fetched playback lyrics');
    var readable = 0;
    for (var pair = 0; pair < 3; pair++) {
      for (var side = 0; side < 2; side++) {
        final cached = await cache.read('parallel-$pair-$side');
        if (cached != null) {
          readable++;
          expect(contentOf(cached),
              String.fromCharCode(98 + pair * 2 + side) * 32);
        }
      }
    }
    expect(readable, inInclusiveRange(1, 2));
    expect(
        directory
            .listSync()
            .whereType<File>()
            .any((file) => file.path.endsWith('.tmp')),
        isFalse);
  });

  test('clearing cache during a fetch cannot revive its old byte inventory',
      () async {
    final entryBytes = await seedBudget();
    final cap = entryBytes * 2 + 8;
    cache = OnlineLyricCache(
        directory: () async => directory, totalBytesLimit: cap);
    await cache.resolve('before-clear', () async => line('b' * 32));
    final started = Completer<void>();
    final pending = Completer<Lyric?>();
    final afterClear = cache.resolve('after-clear', () {
      started.complete();
      return pending.future;
    });
    await started.future;
    try {
      await directory.delete(recursive: true);
      await directory.create();
      pending.complete(line('c' * 32));
      expect(contentOf((await afterClear)!), 'c' * 32);
      expect(await cache.read('before-clear'), isNull);
      for (var index = 0; index < 3; index++) {
        final identity = 'after-clear-$index';
        final content = String.fromCharCode(100 + index) * 32;
        await cache.resolve(identity, () async => line(content));
        expect(await savedBytes(), lessThanOrEqualTo(cap));
        expect(contentOf((await cache.read(identity))!), content);
      }
    } finally {
      if (!pending.isCompleted) pending.complete(line('c' * 32));
      await afterClear;
    }
  });
}
