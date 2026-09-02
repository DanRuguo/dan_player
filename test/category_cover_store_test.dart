import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

Future<Uint8List> _png(int width, int height, int color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(color), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory parent;
  late Directory fixture;
  late Directory data;

  setUp(() async {
    parent = await Directory(path.join(
            Directory.current.parent.path, 'tool', 'qa-category-covers'))
        .create(recursive: true);
    fixture = await parent.createTemp('category-cover-');
    data = await Directory(path.join(fixture.path, 'app-data')).create();
  });

  tearDown(() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final resolved = await fixture.resolveSymbolicLinks();
    if (!path.isWithin(await parent.resolveSymbolicLinks(), resolved) ||
        !path.basename(resolved).startsWith('category-cover-')) {
      throw StateError('Refusing to remove an unverified category fixture.');
    }
    await Directory(resolved).delete(recursive: true);
  });

  CategoryCoverStore store() =>
      CategoryCoverStore(dataDirectory: () async => data);

  MusicCategoryGroup group(String name,
          {MusicCategoryKind kind = MusicCategoryKind.artist}) =>
      MusicCategories(<CategoryTestAudio>[
        CategoryTestAudio(name,
            artist: kind == MusicCategoryKind.artist ? name : 'Artist',
            album: kind == MusicCategoryKind.album ? name : 'Album')
      ]).groups(kind).single;

  Future<File> source(String name, int color) async =>
      File(path.join(fixture.path, name))
          .writeAsBytes(await _png(80, 60, color), flush: true);

  test('stable group identity excludes translated labels and song order', () {
    final first = CategoryTestAudio('first', artist: '同一艺人');
    final second = CategoryTestAudio('second', artist: '同一艺人');
    final normal = MusicCategories([first, second])
        .groups(MusicCategoryKind.artist)
        .single;
    final reversed = MusicCategories([second, first])
        .groups(MusicCategoryKind.artist)
        .single;

    expect(reversed.persistenceKey, normal.persistenceKey);
    expect(jsonDecode(normal.persistenceKey),
        [1, MusicCategoryKind.artist.name, normal.id]);
  });

  test('managed copy persists and survives deleting the selected original',
      () async {
    final selected = await source('外部封面.png', 0xff228877);
    final originalBytes = await selected.readAsBytes();
    final category = group('Artist A');
    final first = store();

    await first.setCover(category, selected.path);
    final id = first.coverIdFor(category);
    expect(id, isNotNull);
    expect(await selected.readAsBytes(), originalBytes);
    final managed = File(path.join(data.path, 'category-covers', id));
    expect(await managed.exists(), isTrue);
    expect(path.isWithin(data.path, managed.path), isTrue);

    await selected.delete();
    final reloaded = store();
    await reloaded.load();
    expect(reloaded.coverIdFor(category), id);
    expect(await reloaded.imageFor(category), isA<FileImage>());
    final saved = jsonDecode(
        await File(path.join(data.path, 'category_covers.json'))
            .readAsString());
    expect(jsonEncode(saved), isNot(contains(fixture.path)));
  });

  test('corrupt primary recovers the complete backup without overwriting it',
      () async {
    final category = group('Recovered');
    final first = store();
    await first.setCover(category, (await source('safe.png', 0xff336699)).path);
    final primary = File(path.join(data.path, 'category_covers.json'));
    final backup = File('${primary.path}.bak');
    await primary.copy(backup.path);
    final goodBackup = await backup.readAsString();
    await primary.writeAsString('{broken');

    final recovered = store();
    await recovered.load();
    expect(recovered.hasCover(category), isTrue);
    expect(recovered.readError, isNull);
    await recovered.setCover(
        category, (await source('new.png', 0xff993366)).path);
    expect(await backup.readAsString(), goodBackup);
    expect(jsonDecode(await primary.readAsString()), isA<Map>());
  });

  test('failed metadata write rolls back the record and imported copy',
      () async {
    final category = group('Rollback');
    final first = store();
    await first.setCover(category, (await source('old.png', 0xff113355)).path);
    final oldId = first.coverIdFor(category);
    final blocked = Directory(path.join(data.path, 'category_covers.json.tmp'));
    await blocked.create();
    try {
      await expectLater(
          first.setCover(category, (await source('new.png', 0xffaa7733)).path),
          throwsA(anything));
      expect(first.coverIdFor(category), oldId);
      final managed = Directory(path.join(data.path, 'category-covers'));
      expect(
          (await managed
                  .list(followLinks: false)
                  .where((entity) => entity is File)
                  .toList())
              .map((entity) => path.basename(entity.path)),
          [oldId]);
    } finally {
      await blocked.delete();
    }

    await first.setCover(
        category, (await source('retry.png', 0xff224466)).path);
    expect(first.coverIdFor(category), isNot(oldId));
  });

  test('vanished groups remove record, recovery reference and managed image',
      () async {
    final vanished = group('Vanished');
    final retained = group('Retained');
    final first = store();
    await first.setCover(
        vanished, (await source('vanished.png', 0xffcc3344)).path);
    await first.setCover(
        retained, (await source('retained.png', 0xff33aa77)).path);
    final vanishedId = first.coverIdFor(vanished)!;
    final retainedId = first.coverIdFor(retained)!;

    await first.reconcileKind(MusicCategoryKind.artist, [retained]);
    expect(first.hasCover(vanished), isFalse);
    expect(first.coverIdFor(retained), retainedId);
    expect(
        await File(path.join(data.path, 'category-covers', vanishedId))
            .exists(),
        isFalse);
    expect(
        await File(path.join(data.path, 'category-covers', retainedId))
            .exists(),
        isTrue);

    for (final name in [
      'category_covers.json',
      'category_covers.json.bak',
    ]) {
      final contents =
          jsonDecode(await File(path.join(data.path, name)).readAsString())
              as Map;
      final covers = contents['covers'] as Map;
      expect(covers, isNot(contains(vanished.persistenceKey)));
      expect(covers, contains(retained.persistenceKey));
    }
    final reloaded = store();
    await reloaded.load();
    expect(reloaded.hasCover(vanished), isFalse);
    expect(reloaded.coverIdFor(retained), retainedId);
  });

  test('reconciling one lazy kind never deletes another kind', () async {
    final artist = group('Artist cover');
    final album = group('Album cover', kind: MusicCategoryKind.album);
    final first = store();
    await first.setCover(artist, (await source('artist.png', 0xff667799)).path);
    await first.setCover(album, (await source('album.png', 0xff997766)).path);

    await first.reconcileKind(MusicCategoryKind.artist, const []);

    expect(first.hasCover(artist), isFalse);
    expect(first.hasCover(album), isTrue);
  });

  test('one missing managed image never locks the remaining covers', () async {
    final missing = group('Missing image');
    final healthy = group('Healthy image');
    final first = store();
    await first.setCover(
        missing, (await source('missing.png', 0xff884422)).path);
    await first.setCover(
        healthy, (await source('healthy.png', 0xff228844)).path);
    final missingId = first.coverIdFor(missing)!;
    await File(path.join(data.path, 'category-covers', missingId)).delete();

    final recovered = store();
    await recovered.load();
    expect(recovered.readError, isNull);
    expect(recovered.hasCover(missing), isFalse);
    expect(recovered.hasCover(healthy), isTrue);
    for (final name in [
      'category_covers.json',
      'category_covers.json.bak',
    ]) {
      final saved =
          jsonDecode(await File(path.join(data.path, name)).readAsString())
              as Map;
      expect(saved['covers'], isNot(contains(missing.persistenceKey)));
    }

    await recovered.removeCover(healthy);
    await recovered.setCover(
        missing, (await source('replacement.png', 0xff335599)).path);
    expect(recovered.hasCover(healthy), isFalse);
    expect(recovered.hasCover(missing), isTrue);

    final reloaded = store();
    await reloaded.load();
    expect(reloaded.readError, isNull);
    expect(reloaded.hasCover(healthy), isFalse);
    expect(reloaded.hasCover(missing), isTrue);
  });

  test('reimporting identical bytes clears a cached missing provider',
      () async {
    final category = group('Same content recovery');
    final selected = await source('same-content.png', 0xff446688);
    final first = store();
    await first.setCover(category, selected.path);
    final id = first.coverIdFor(category)!;
    await File(path.join(data.path, 'category-covers', id)).delete();
    expect(await first.imageFor(category), isNull);

    await first.setCover(category, selected.path);

    expect(first.coverIdFor(category), id);
    expect(await first.imageFor(category), isA<FileImage>());
  });

  test('the twenty-fifth distinct category cover is not rejected', () async {
    final first = store();
    final groups = <MusicCategoryGroup>[];
    for (var index = 0; index < 25; index++) {
      final category = group('Artist $index');
      groups.add(category);
      await first.setCover(
          category,
          (await source('cover-$index.png', 0xff000000 | (index * 0x010307)))
              .path);
    }

    expect(groups.every(first.hasCover), isTrue);
    final files = await Directory(path.join(data.path, 'category-covers'))
        .list(followLinks: false)
        .where((entry) => entry is File)
        .toList();
    expect(files, hasLength(25));
  });

  test('image-provider futures are reused across rebuild-sized access bursts',
      () async {
    final first = store();
    final groups = <MusicCategoryGroup>[];
    for (var index = 0; index < 8; index++) {
      final category = group('Cached $index');
      groups.add(category);
      await first.setCover(
          category,
          (await source('cached-$index.png', 0xff001100 | (index * 0x020509)))
              .path);
    }
    final original = first.imageFor(groups.first);
    for (final category in groups.skip(1)) {
      first.imageFor(category);
    }

    expect(identical(first.imageFor(groups.first), original), isTrue);
  });
}
