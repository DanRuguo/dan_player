import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory fixture;
  late Directory parent;

  setUp(() async {
    parent = await Directory(
            path.join(Directory.current.parent.path, 'tool', 'qa-artwork'))
        .create(recursive: true);
    fixture = await parent.createTemp('cover-cache-');
  });
  tearDown(() async {
    if (!path.isWithin(parent.absolute.path, fixture.absolute.path)) {
      throw StateError('Refusing cleanup outside the owned image fixture.');
    }
    await fixture.delete(recursive: true);
  });

  test('coalesces requests and reuses a file provider without retaining bytes',
      () async {
    final cache = CoverCache.forTesting(directory: fixture);
    final started = Completer<void>();
    final bytes = Completer<Uint8List?>();
    var reads = 0;
    Future<ImageProvider?> request() => cache.imageFor(
          audioPath: 'song-a',
          modified: 1,
          width: 96,
          height: 96,
          produce: () {
            reads++;
            started.complete();
            return bytes.future;
          },
        );
    final first = request();
    final second = request();
    expect(identical(first, second), isTrue);
    await started.future;
    bytes.complete(Uint8List.fromList([1, 2, 3]));
    expect(await first, isA<FileImage>());
    expect(identical(request(), first), isTrue);
    expect(reads, 1);
    expect(cache.cachedProviderCount, 1);
  });

  test('list and large-art metadata entries share a bounded LRU', () async {
    final cache = CoverCache.forTesting(directory: fixture, maxEntries: 3);
    Future<ImageProvider?> request(int index, int size) => cache.imageFor(
          audioPath: 'song-$index',
          modified: 1,
          width: size,
          height: size,
          produce: () async => Uint8List.fromList([index, 2, 3]),
        );
    final first = request(0, 48);
    await first;
    for (var index = 1; index < 10; index++) {
      await request(index, index.isEven ? 96 : 1024);
      expect(cache.cachedProviderCount, lessThanOrEqualTo(3));
    }
    final afterEviction = request(0, 48);
    expect(identical(first, afterEviction), isFalse);
    expect(await afterEviction, isA<FileImage>());
    expect(cache.cachedProviderCount, 3);
  });

  test('the same source at another DPR receives a distinct cached thumbnail',
      () async {
    final cache = CoverCache.forTesting(directory: fixture);
    var reads = 0;
    Future<ImageProvider?> request(int size) => cache.imageFor(
          audioPath: 'song',
          modified: 1,
          width: size,
          height: size,
          produce: () async {
            reads++;
            return Uint8List.fromList([1, 2, 3]);
          },
        );
    final low = await request(48) as FileImage;
    final high = await request(96) as FileImage;
    expect(low.file.path, isNot(high.file.path));
    await request(96);
    expect(reads, 2);
  });

  test('native thumbnail production has at most two active decoders', () async {
    final cache =
        CoverCache.forTesting(directory: fixture, maxConcurrentReads: 2);
    final releases = List.generate(5, (_) => Completer<Uint8List?>());
    final started = List.generate(5, (_) => Completer<void>());
    var active = 0;
    var peak = 0;
    final futures = [
      for (var index = 0; index < 5; index++)
        cache.imageFor(
          audioPath: 'song-$index',
          modified: 1,
          width: 48,
          height: 48,
          produce: () async {
            active++;
            if (active > peak) peak = active;
            started[index].complete();
            try {
              return await releases[index].future;
            } finally {
              active--;
            }
          },
        )
    ];
    // File-system checks may complete out of order; release whichever requests
    // obtained the first slots, then allow every queued request to finish.
    await Future.any(started.map((event) => event.future));
    expect(cache.activeReadCount, inInclusiveRange(1, 2));
    for (final release in releases) {
      release.complete(Uint8List.fromList([1, 2, 3]));
    }
    await Future.wait(futures);
    expect(peak, lessThanOrEqualTo(2));
    expect(cache.activeReadCount, 0);
    expect(started.every((event) => event.isCompleted), isTrue);
  });

  test('invalidating a pending thumbnail cannot put it back into the cache',
      () async {
    final cache = CoverCache.forTesting(directory: fixture);
    final oldStarted = Completer<void>();
    final oldBytes = Completer<Uint8List?>();
    final old = cache.imageFor(
        audioPath: 'changed',
        modified: 1,
        width: 48,
        height: 48,
        produce: () {
          oldStarted.complete();
          return oldBytes.future;
        });
    await oldStarted.future;
    await cache.invalidate('changed');
    final current = cache.imageFor(
        audioPath: 'changed',
        modified: 1,
        width: 48,
        height: 48,
        produce: () async => Uint8List.fromList([4, 5, 6]));
    expect(await current, isA<FileImage>());
    oldBytes.complete(Uint8List.fromList([1, 2, 3]));
    expect(await old, isA<MemoryImage>());
    expect(cache.cachedProviderCount, 1);
    expect((await fixture.list().toList()).length, 1);
  });

  test('v2 soft thumbnails are not reused by the new cover-aware schema',
      () async {
    final old = File(path.join(
        fixture.path, 'v2_${CoverCache.stableHash('song')}_1_e0g0_48x48.png'));
    await old.writeAsBytes([0]);
    final cache = CoverCache.forTesting(directory: fixture);
    var reads = 0;
    final image = await cache.imageFor(
        audioPath: 'song',
        modified: 1,
        width: 48,
        height: 48,
        produce: () async {
          reads++;
          return Uint8List.fromList([1, 2, 3]);
        }) as FileImage;
    expect(reads, 1);
    expect(path.basename(image.file.path), startsWith('v3_'));
    expect(await old.readAsBytes(), [0]);
  });

  test('a missing image has a short negative cache and retries after expiry',
      () async {
    var now = DateTime(2026, 1, 1);
    final cache = CoverCache.forTesting(
      directory: fixture,
      failureRetryDelay: const Duration(seconds: 30),
      clock: () => now,
    );
    var reads = 0;
    Future<ImageProvider?> request() => cache.imageFor(
        audioPath: 'missing',
        modified: 1,
        width: 48,
        height: 48,
        produce: () async {
          reads++;
          return null;
        });
    expect(await request(), isNull);
    expect(await request(), isNull);
    expect(reads, 1,
        reason: 'bad/missing embedded artwork must not decode every rebuild');
    now = now.add(const Duration(seconds: 31));
    expect(await request(), isNull);
    expect(reads, 2);
    expect(cache.cachedProviderCount, 0);
  });

  test('prune enforces disk file and byte caps using oldest files first',
      () async {
    final cache = CoverCache.forTesting(
      directory: fixture,
      maxDiskFiles: 2,
      maxDiskBytes: 7,
    );
    final entries = <CoverCacheEntry>[];
    for (var index = 0; index < 4; index++) {
      final audioPath = 'song-$index';
      entries.add(CoverCacheEntry(audioPath, 1));
      final image = await cache.imageFor(
        audioPath: audioPath,
        modified: 1,
        width: 48,
        height: 48,
        produce: () async => Uint8List.fromList([index, 2, 3, 4]),
      ) as FileImage;
      await image.file
          .setLastModified(DateTime(2026, 1, 1).add(Duration(minutes: index)));
    }
    await cache.prune(entries);
    final files = (await fixture.list().where((item) => item is File).toList())
        .cast<File>();
    expect(files, hasLength(1),
        reason: 'two 4-byte files would exceed the configured 7-byte cap');
    expect(path.basename(files.single.path),
        contains(CoverCache.stableHash('song-3')),
        reason: 'newest valid thumbnail is retained');
  });
}
