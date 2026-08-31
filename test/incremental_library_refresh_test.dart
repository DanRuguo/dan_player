import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Map<String, Object?> _song(String name,
        {String? nanos = '1700000000000000100',
        int size = 200,
        bool pending = false}) =>
    {
      'path': 'D:/synthetic-library/$name.mp3',
      'title': name,
      'artist': 'Fixture',
      'album': 'Synthetic',
      'modified': 1700000000,
      'file_size': size,
      'modified_ns': nanos,
      'metadata_pending': pending,
      'classification_version': 1,
    };
Map<String, Object?> _index(List<Map> songs, {List<String>? roots}) => {
      'version': 113,
      if (roots != null) 'roots': roots,
      'folders': [
        {
          'path': 'D:/synthetic-library',
          'modified': 1,
          'latest': 0,
          'audios': songs
        }
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixture;
  late Directory data;
  late Directory parent;

  setUp(() async {
    parent = await Directory(path.join(Directory.current.parent.path, 'tool',
            'qa-20260831', 'incremental-tests'))
        .create(recursive: true);
    fixture = await parent.createTemp('library-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fixture.path);
    data = await getAppDataDir();
    expect(path.isWithin(fixture.path, data.path), isTrue);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(path.isWithin(parent.path, fixture.path), isTrue);
    await fixture.delete(recursive: true);
  });

  test(
      'native scan continues after view cancellation and gate spans dependent reload',
      () async {
    final gate = LibraryMutationGate();
    final source = StreamController<IndexActionState>();
    final scanStarted = Completer<void>();
    final reloadStarted = Completer<void>();
    final releaseReload = Completer<void>();
    var reloads = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () {
          scanStarted.complete();
          return source.stream;
        },
        commit: () async {
          reloads++;
          reloadStarted.complete();
          await releaseReload.future;
          return 2;
        });
    final view = task.stream.listen((_) {});
    await scanStarted.future;
    expect(gate.isBusy, isTrue);
    // This is the exact operation performed by BuildIndexStateView.dispose.
    await view.cancel();
    expect(gate.isBusy, isTrue);
    await expectLater(
        gate.run(() async => fail('must not interleave metadata save')),
        throwsA(isA<LibraryMutationBusy>()));
    await source.close();
    await reloadStarted.future;
    expect(reloads, 1);
    expect(gate.isBusy, isTrue);
    releaseReload.complete();
    await task.completed;
    expect(task.error, isNull);
    expect(task.pendingMetadata, 2);
    expect(gate.isBusy, isFalse);
    expect(await gate.run(() async => 'next operation'), 'next operation');
  });

  test(
      'busy metadata save rejects refresh before scan and never queues stale work',
      () async {
    final gate = LibraryMutationGate();
    final release = Completer<void>();
    final saving = gate.run(() => release.future);
    var scans = 0;
    var reloads = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () {
          scans++;
          return const Stream.empty();
        },
        commit: () async {
          reloads++;
          return 0;
        });
    final errors = <Object>[];
    final view = task.stream.listen((_) {}, onError: errors.add);
    await task.completed;
    await view.cancel();
    expect(task.error, isA<LibraryMutationBusy>());
    expect(scans, 0);
    expect(reloads, 0);
    expect(gate.isBusy, isTrue);
    release.complete();
    await saving;
    expect(gate.isBusy, isFalse);
    expect(scans, 0,
        reason: 'busy refresh must not start later with old state');
  });

  test(
      'real metadata entry point rejects shared refresh gate before native access',
      () async {
    final release = Completer<void>();
    final refresh = LibraryMutationGate.shared.run(() => release.future);
    try {
      await expectLater(
          applyAudioMetadataEdit(
              Audio.fromMap(_song('NeverWritten')),
              const AudioMetadataEdit(
                  fileName: 'NeverWritten.mp3',
                  title: 'Edited',
                  artist: 'Fixture',
                  album: 'Synthetic')),
          throwsA(isA<AudioMetadataEditException>()
              .having((error) => error.code, 'code', 'TAG_LIBRARY_BUSY')));
    } finally {
      release.complete();
      await refresh;
    }
    expect(LibraryMutationGate.shared.isBusy, isFalse);
  });

  test(
      'native failure skips cache reload and releases gate even without a view',
      () async {
    final gate = LibraryMutationGate();
    final source = StreamController<IndexActionState>();
    final started = Completer<void>();
    var reloads = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () {
          started.complete();
          return source.stream;
        },
        commit: () async {
          reloads++;
          return 0;
        });
    final view = task.stream.listen((_) {}, onError: (_) {});
    await started.future;
    await view.cancel();
    source.addError(StateError('synthetic incomplete scan'));
    unawaited(source.close());
    await task.completed;
    expect(reloads, 0);
    expect(task.error, isA<StateError>());
    expect(gate.isBusy, isFalse);
  });

  test(
      'post-commit reload failure releases gate and retains distinct task failure',
      () async {
    final gate = LibraryMutationGate();
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () => const Stream.empty(),
        commit: () async => throw StateError('synthetic reload failure'));
    final view = task.stream.listen((_) {}, onError: (_) {});
    await task.completed;
    await view.cancel();
    expect(task.error, isA<StateError>());
    expect(gate.isBusy, isFalse);
    await gate.run(() async {});
  });

  test(
      'unopened refresh task acquires nothing; multiple observers scan only once',
      () async {
    final gate = LibraryMutationGate();
    var scans = 0;
    final task = LibraryRefreshTask(
        gate: gate,
        scan: () {
          scans++;
          return const Stream.empty();
        },
        commit: () async => 0);
    expect(gate.isBusy, isFalse);
    expect(scans, 0);
    final first = task.stream.listen((_) {});
    final second = task.stream.listen((_) {});
    await task.completed;
    await first.cancel();
    await second.cancel();
    expect(scans, 1);
    expect(task.error, isNull);
    expect(gate.isBusy, isFalse);
  });

  test(
      'fingerprint and pending state survive Audio JSON and an edit invalidates stamp',
      () {
    final audio = Audio.fromMap(_song('A', pending: true));
    expect(audio.modifiedNanos, '1700000000000000100');
    expect(audio.metadataReadPending, isTrue);
    expect(audio.toMap()['modified_ns'], '1700000000000000100');
    expect(Audio.fromMap(audio.toMap()).metadataReadPending, isTrue);
    audio.applyEditedMetadata(
        newPath: audio.path,
        newTitle: 'B',
        newArtist: audio.artist,
        newAlbum: audio.album,
        newModified: 1700000000);
    expect(audio.modifiedNanos, isNull);
  });

  test('root selections including empty roots survive real library save/reload',
      () async {
    final file = File(path.join(data.path, 'index.json'));
    const roots = ['D:/synthetic-library', 'D:/synthetic-empty'];
    await file.writeAsString(jsonEncode(_index([_song('A')], roots: roots)));
    await AudioLibrary.initFromIndex();
    expect(AudioLibrary.instance.scanRoots, roots);
    await AudioLibrary.instance.saveIndex();
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(saved['roots'], roots);
    expect((saved['folders'][0]['audios'][0] as Map)['modified_ns'],
        '1700000000000000100');
  });

  test(
      'legacy version 113 without roots or nanoseconds retains folders and missing stamp',
      () async {
    final file = File(path.join(data.path, 'index.json'));
    final song = _song('Old')
      ..remove('modified_ns')
      ..remove('metadata_pending');
    await file.writeAsString(jsonEncode(_index([song])));
    await AudioLibrary.initFromIndex();
    expect(AudioLibrary.instance.scanRoots, ['D:/synthetic-library']);
    expect(AudioLibrary.instance.audioCollection.single.modifiedNanos, isNull);
    await AudioLibrary.instance.saveIndex();
    final saved = jsonDecode(await file.readAsString()) as Map;
    expect(saved['roots'], ['D:/synthetic-library']);
    expect(saved['folders'][0]['audios'][0]['title'], 'Old');
    expect(saved['folders'][0]['audios'][0]['modified_ns'], isNull);
  });

  test('incremental invalidates only added changed deleted and pending paths',
      () async {
    final before = LibraryRefreshSnapshot.fromIndex(_index([
      _song('Same'),
      _song('Changed'),
      _song('Size'),
      _song('Deleted'),
      _song('Pending'),
    ]));
    final after = LibraryRefreshSnapshot.fromIndex(_index([
      _song('Same'),
      _song('Changed', nanos: '1700000000000000200'),
      _song('Size', size: 201),
      _song('New'),
      _song('Pending', pending: true),
    ]));
    final events = <String>[];
    await completeLibraryRefresh(
        incremental: true,
        before: before,
        readCommitted: () async => after,
        invalidateCover: (path) async => events.add(path),
        clearCovers: () async => events.add('CLEAR'),
        reload: () async => events.add('RELOAD'));
    expect(events.toSet(), {
      'D:/synthetic-library/Changed.mp3',
      'D:/synthetic-library/Size.mp3',
      'D:/synthetic-library/Deleted.mp3',
      'D:/synthetic-library/New.mp3',
      'D:/synthetic-library/Pending.mp3',
      'RELOAD',
    });
    expect(events.last, 'RELOAD');
  });

  test(
      'unchanged incremental cache is untouched while full refresh clears once',
      () async {
    final snapshot = LibraryRefreshSnapshot.fromIndex(_index([_song('A')]));
    final events = <String>[];
    for (final incremental in [true, false]) {
      await completeLibraryRefresh(
          incremental: incremental,
          before: snapshot,
          readCommitted: () async => snapshot,
          invalidateCover: (_) async => events.add('INVALIDATE'),
          clearCovers: () async => events.add('CLEAR'),
          reload: () async => events.add('RELOAD'));
    }
    expect(events, ['RELOAD', 'CLEAR', 'RELOAD']);
  });

  test(
      'failed committed-index validation leaves cache and in-memory library untouched',
      () async {
    final events = <String>[];
    for (final incremental in [true, false]) {
      await expectLater(
          completeLibraryRefresh(
              incremental: incremental,
              before: LibraryRefreshSnapshot.fromIndex(_index([_song('A')])),
              readCommitted: () async =>
                  throw const FormatException('synthetic failure'),
              invalidateCover: (_) async => events.add('INVALIDATE'),
              clearCovers: () async => events.add('CLEAR'),
              reload: () async => events.add('RELOAD')),
          throwsFormatException);
    }
    expect(events, isEmpty);
  });

  test('captured snapshot cannot change when an Audio is edited later', () {
    final audio = Audio.fromMap(_song('A'));
    final snapshot = LibraryRefreshSnapshot.capture([audio]);
    audio.modifiedNanos = 'later';
    expect(
        snapshot.changedPaths(
            LibraryRefreshSnapshot.fromIndex(_index([_song('A')]))),
        isEmpty);
  });

  test(
      'native nanosecond/size fingerprint avoids stale artwork even across cold startup',
      () async {
    final directory =
        await Directory(path.join(fixture.path, 'covers')).create();
    final cache = CoverCache.forTesting(directory: directory);
    var reads = 0;
    Future<ImageProvider?> request(String fingerprint) => cache.imageFor(
        audioPath: 'synthetic',
        modified: 1700000000,
        fingerprint: fingerprint,
        width: 16,
        height: 16,
        produce: () async {
          reads++;
          return Uint8List.fromList([1, 2, 3]);
        });
    await request('100_s200');
    await request('100_s200');
    await request('101_s200');
    await request('101_s201');
    expect(reads, 3);
    final cold = CoverCache.forTesting(directory: directory);
    await cold.prune([
      const CoverCacheEntry('synthetic', 1700000000, fingerprint: '101_s201')
    ]);
    expect(await directory.list().length, 1);
    await cold.imageFor(
        audioPath: 'synthetic',
        modified: 1700000000,
        fingerprint: '101_s201',
        width: 16,
        height: 16,
        produce: () async {
          fail('must reuse the matching disk cache');
        });
  });
}
