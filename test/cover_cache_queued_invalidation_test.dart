import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final clear in [false, true]) {
    test('cancel obsolete queued decodes and retain semaphore: clear=$clear',
        () async {
      final parent = Directory(path.join(
          Directory.current.path, 'build', 'test-data', 'cover-queue'));
      await parent.create(recursive: true);
      final folder = await parent.createTemp();
      addTearDown(() async {
        if (!path.isWithin(parent.absolute.path, folder.absolute.path)) {
          throw StateError('Unsafe fixture path');
        }
        await folder.delete(recursive: true);
      });
      final cache =
          CoverCache.forTesting(directory: folder, maxConcurrentReads: 1);
      final gate = Completer<Uint8List?>();
      final started = Completer<void>();
      final first = cache.imageFor(
          audioPath: 'occupied',
          modified: 1,
          width: 48,
          height: 48,
          produce: () {
            started.complete();
            return gate.future;
          });
      await started.future;
      var obsoleteReads = 0;
      final queued = [
        for (var i = 0; i < 20; i++)
          cache.imageFor(
              audioPath: 'changed',
              modified: 1,
              width: 48 + i,
              height: 48 + i,
              produce: () async {
                obsoleteReads++;
                return Uint8List.fromList([1, 2, 3]);
              })
      ];
      if (clear) {
        await cache.clear();
      } else {
        await cache.invalidate('changed');
      }
      var validReads = 0;
      final latest = cache.imageFor(
          audioPath: 'changed',
          modified: 2,
          width: 48,
          height: 48,
          produce: () async {
            validReads++;
            return Uint8List.fromList([1, 2, 3]);
          });
      gate.complete(null);
      await first;
      expect(await Future.wait(queued), everyElement(isNull));
      expect(await latest, isNotNull);
      expect(obsoleteReads, 0,
          reason: 'Invalidated work must not consume native decoder time');
      expect(validReads, 1);
      expect(cache.activeReadCount, 0);
      expect(cache.cachedProviderCount, 1);
    });
  }
}
