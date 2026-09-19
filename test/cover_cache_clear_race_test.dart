import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dan_player/library/cover_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

class _HeldListingDirectory implements Directory {
  _HeldListingDirectory(this.directory);
  final Directory directory;
  final listing = Completer<void>();
  final release = Completer<void>();
  @override
  String get path => directory.path;
  @override
  Stream<FileSystemEntity> list(
      {bool recursive = false, bool followLinks = true}) async* {
    listing.complete();
    await release.future;
    yield* directory.list(recursive: recursive, followLinks: followLinks);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a thumbnail started during async clear keeps its valid cache file',
      () async {
    final parent = Directory(path.join(
        Directory.current.path, 'build', 'test-data', 'cover-clear-race'));
    await parent.create(recursive: true);
    final folder = await parent.createTemp();
    addTearDown(() async {
      if (!path.isWithin(parent.absolute.path, folder.absolute.path)) {
        throw StateError('Unsafe fixture');
      }
      await folder.delete(recursive: true);
    });
    final delayed = _HeldListingDirectory(folder);
    final cache = CoverCache.forTesting(directory: delayed);
    final clearing = cache.clear();
    await delayed.listing.future;
    Future<ImageProvider?> request() => cache.imageFor(
          audioPath: 'visible-song',
          modified: 1,
          width: 96,
          height: 96,
          produce: () async => Uint8List.fromList([1, 2, 3]),
        );
    final fresh = await request() as FileImage;
    expect(await fresh.file.exists(), isTrue);
    delayed.release.complete();
    await clearing;
    final reused = await request() as FileImage;
    expect(await reused.file.exists(), isTrue,
        reason: 'Concurrent current-generation artwork must not be deleted '
            'while its ready provider remains cached');
  });
}
