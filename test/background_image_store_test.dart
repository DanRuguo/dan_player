import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/background_image_store.dart';
import 'package:dan_player/background_preferences.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Future<Uint8List> _png(int width, int height,
    [Color color = const Color(0xff217979)]) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
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

Future<ui.Size> _decodedSize(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  final image = (await codec.getNextFrame()).image;
  try {
    return ui.Size(image.width.toDouble(), image.height.toDouble());
  } finally {
    image.dispose();
    codec.dispose();
  }
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory parent;
  late Directory fixture;
  late Directory copies;
  late BackgroundImageStore store;

  setUp(() async {
    parent = await Directory(path.join(
            Directory.current.parent.path, 'tool', 'qa-settings-background'))
        .create(recursive: true);
    fixture = await parent.createTemp('image-store-');
    copies = Directory(path.join(fixture.path, 'background-images'));
    store = BackgroundImageStore(directory: () async => copies);
  });
  tearDown(() async {
    final resolved = await fixture.resolveSymbolicLinks();
    if (!path.isWithin(await parent.resolveSymbolicLinks(), resolved) ||
        !path.basename(resolved).startsWith('image-store-')) {
      throw StateError('Refusing to remove an unverified background fixture.');
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await Directory(resolved).delete(recursive: true);
  });

  Future<File> source(String name, Uint8List bytes) =>
      File(path.join(fixture.path, name)).writeAsBytes(bytes);

  test('imports a managed copy without mutating or relocating the original',
      () async {
    final bytes = await _png(96, 64);
    final file = await source('旅行.png', bytes);
    final before = await file.stat();
    final asset = await store.importFile(file.path);
    expect(isBackgroundImageId(asset.id), isTrue);
    expect(asset.name, '旅行.png');
    expect(asset.width, 96);
    expect(asset.height, 64);
    expect(await file.readAsBytes(), bytes);
    expect((await file.stat()).modified, before.modified);
    expect(await _decodedSize(File(path.join(copies.path, asset.id))),
        const ui.Size(96, 64));
    expect(await store.imageFor(asset.id), isA<FileImage>());
  });

  test('reimport and simultaneous requests deduplicate immutable assets',
      () async {
    final file = await source('one.png', await _png(60, 40));
    final assets = await Future.wait([
      store.importFile(file.path),
      store.importFile(file.path),
      store.importFile(file.path),
    ]);
    expect(assets.map((value) => value.id).toSet().length, 1);
    expect(await copies.list().length, 1);
    final first = store.imageFor(assets.first.id);
    expect(identical(first, store.imageFor(assets.first.id)), isTrue);
  });

  test('landscape and portrait samples preserve aspect and do not upscale',
      () async {
    for (final size in [(4096, 1024), (1024, 4096), (12, 20)]) {
      final file = await source(
          '${size.$1}-${size.$2}.png', await _png(size.$1, size.$2));
      final asset = await store.importFile(file.path);
      expect(asset.width, lessThanOrEqualTo(2048));
      expect(asset.height, lessThanOrEqualTo(2048));
      expect(asset.width * asset.height, lessThanOrEqualTo(4 * 1024 * 1024));
      expect(asset.width / asset.height, closeTo(size.$1 / size.$2, .001));
      expect(asset.width, lessThanOrEqualTo(size.$1));
      expect(asset.height, lessThanOrEqualTo(size.$2));
      expect(await _decodedSize(File(path.join(copies.path, asset.id))),
          ui.Size(asset.width.toDouble(), asset.height.toDouble()));
    }
  });

  test('missing/empty/text/disguised SVG/GIF inputs never create an asset',
      () async {
    await expectLater(store.importFile(path.join(fixture.path, 'missing.png')),
        throwsA(isA<BackgroundImageException>()));
    for (final bytes in [
      Uint8List(0),
      Uint8List.fromList(List.filled(64, 65)),
      Uint8List.fromList('<svg><path/></svg>'.codeUnits),
      Uint8List.fromList('GIF89aNOT-A-STATIC-IMAGE'.codeUnits)
    ]) {
      final file = await source('disguised.png', bytes);
      await expectLater(store.importFile(file.path),
          throwsA(isA<BackgroundImageException>()));
      expect(await file.readAsBytes(), bytes);
    }
    expect(await copies.exists(), isFalse);
  });

  test('large encoded files fail before reading or decoding', () async {
    final file = File(path.join(fixture.path, 'large.png'));
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(BackgroundImageStore.maxInputBytes + 1);
    await handle.close();
    await expectLater(
        store.importFile(file.path),
        throwsA(isA<BackgroundImageException>()
            .having((error) => error.message, 'message', contains('20 MiB'))));
    expect(await copies.exists(), isFalse);
  });

  test('oversized headers fail before full raster decoding', () async {
    final bytes = Uint8List.fromList(await _png(8, 8));
    final data = ByteData.sublistView(bytes);
    data.setUint32(16, 10000);
    data.setUint32(20, 10000);
    data.setUint32(29, _crc32(bytes.sublist(12, 29)));
    final file = await source('huge-header.png', bytes);
    await expectLater(
        store.importFile(file.path),
        throwsA(isA<BackgroundImageException>()
            .having((error) => error.message, 'message', contains('4000'))));
    expect(await copies.exists(), isFalse);
  });

  test('APNG animation declaration is rejected without starting frames',
      () async {
    final bytes = await _png(8, 8);
    final animation = ByteData(20)
      ..setUint32(0, 8)
      ..setUint32(8, 2)
      ..setUint32(12, 0);
    final chunk = animation.buffer.asUint8List();
    chunk.setRange(4, 8, 'acTL'.codeUnits);
    animation.setUint32(16, _crc32(chunk.sublist(4, 16)));
    final file = await source('animated.png',
        Uint8List.fromList([...bytes.take(33), ...chunk, ...bytes.skip(33)]));
    await expectLater(
        store.importFile(file.path),
        throwsA(isA<BackgroundImageException>()
            .having((error) => error.message, 'message', contains('动图'))));
    expect(await copies.exists(), isFalse);
  });

  test('quota failure preserves existing pictures and leaves no partial files',
      () async {
    store =
        BackgroundImageStore(directory: () async => copies, maxStoredImages: 1);
    final first = await source('one.png', await _png(40, 40));
    final second =
        await source('two.png', await _png(40, 40, const Color(0xffff0000)));
    final original = await store.importFile(first.path);
    await expectLater(store.importFile(second.path),
        throwsA(isA<BackgroundImageException>()));
    expect(
        (await copies.list().toList())
            .map((entry) => path.basename(entry.path)),
        [original.id]);
    expect((await store.importFile(first.path)).id, original.id);
    expect(await first.exists(), isTrue);
    expect(await second.exists(), isTrue);
  });

  test('byte quota is enforced and an IO failure does not poison the queue',
      () async {
    var fail = true;
    store = BackgroundImageStore(directory: () async {
      if (fail) throw const FileSystemException('isolated permission failure');
      return copies;
    });
    final file = await source('image.png', await _png(24, 24));
    await expectLater(
        store.importFile(file.path), throwsA(isA<FileSystemException>()));
    fail = false;
    final asset = await store.importFile(file.path);
    expect(await store.imageFor(asset.id), isNotNull);
    final tiny = BackgroundImageStore(
        directory: () async => Directory(path.join(fixture.path, 'tiny')),
        maxStoredBytes: 1);
    await expectLater(
        tiny.importFile(file.path), throwsA(isA<BackgroundImageException>()));
    expect(await file.exists(), isTrue);
  });

  test('IDs never permit filesystem traversal or trigger lookup for a URL',
      () async {
    var reads = 0;
    final guarded = BackgroundImageStore(directory: () async {
      reads++;
      throw StateError('no directory access');
    });
    for (final id in [
      null,
      '../a.png',
      '/a.png',
      'D:\\a.png',
      'https://example.com/a.png',
      '${'a' * 64}.jpg'
    ]) {
      expect(await guarded.imageFor(id), isNull);
    }
    expect(reads, 0);
  });

  test('explicit cleanup keeps active/inactive and persisted references',
      () async {
    final assets = <ManagedBackgroundImage>[];
    for (var index = 0; index < 3; index++) {
      final file = await source('$index.png', await _png(20 + index, 20));
      assets.add(await store.importFile(file.path));
    }
    store = BackgroundImageStore(
        directory: () async => copies,
        persistedIds: () async => {assets[1].id});
    final unknown = await File(path.join(copies.path, 'do-not-delete.txt'))
        .writeAsString('user note');
    expect(await store.removeUnused(() => {assets.first.id}), 1);
    expect(
        await File(path.join(copies.path, assets.first.id)).exists(), isTrue);
    expect(await File(path.join(copies.path, assets[1].id)).exists(), isTrue);
    expect(
        await File(path.join(copies.path, assets.last.id)).exists(), isFalse);
    expect(await unknown.exists(), isTrue);
    expect(await File(path.join(fixture.path, '2.png')).exists(), isTrue);
  });

  test('unreadable saved settings prevent all cleanup, preserving recovery',
      () async {
    final file = await source('image.png', await _png(20, 20));
    final asset = await store.importFile(file.path);
    final guarded = BackgroundImageStore(
        directory: () async => copies,
        persistedIds: () async =>
            throw const FormatException('damaged settings'));
    await expectLater(guarded.removeUnused(() => {}), throwsFormatException);
    expect(await File(path.join(copies.path, asset.id)).exists(), isTrue);
  });

  test('provider metadata has a bounded LRU and missing copies fall back',
      () async {
    final firstId = '${'a' * 64}.png';
    final first = store.imageFor(firstId);
    expect(await first, isNull);
    for (var index = 0; index < 8; index++) {
      await store.imageFor('${index.toRadixString(16).padLeft(64, '0')}.png');
    }
    expect(identical(first, store.imageFor(firstId)), isFalse);
  });

  group('default saved-reference reader uses only isolated settings', () {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    late Directory appData;
    setUp(() async {
      expect(
          Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => fixture.path);
      appData = await Directory(path.join(fixture.path, 'Dan Player')).create();
      copies = Directory(path.join(appData.path, 'background-images'));
      store = BackgroundImageStore.instance;
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('saved and backup selections both survive explicit cleanup', () async {
      final assets = <ManagedBackgroundImage>[];
      for (var index = 0; index < 3; index++) {
        final original =
            await source('saved-$index.png', await _png(32 + index, 20));
        assets.add(await store.importFile(original.path));
      }
      for (var index = 0; index < 2; index++) {
        await File(path.join(appData.path,
                index == 0 ? 'settings.json' : 'settings.json.bak'))
            .writeAsString(jsonEncode({
          'Backgrounds': {
            'main': {'source': 'solid', 'customImageId': assets[index].id}
          }
        }));
      }
      expect(await store.removeUnused(() => {}), 1);
      expect(await File(path.join(copies.path, assets[0].id)).exists(), isTrue);
      expect(await File(path.join(copies.path, assets[1].id)).exists(), isTrue);
      expect(
          await File(path.join(copies.path, assets[2].id)).exists(), isFalse);
    });

    test('invalid JSON in a backup fails before deleting any managed copy',
        () async {
      final original = await source('safe.png', await _png(34, 22));
      final asset = await store.importFile(original.path);
      await File(path.join(appData.path, 'settings.json')).writeAsString('{}');
      await File(path.join(appData.path, 'settings.json.bak'))
          .writeAsString('{invalid json');
      await expectLater(store.removeUnused(() => {}), throwsFormatException);
      expect(await File(path.join(copies.path, asset.id)).exists(), isTrue);
      expect(await original.exists(), isTrue);
    });

    test('a malformed scene or image reference prevents all cleanup', () async {
      final original = await source('safe.png', await _png(35, 22));
      final asset = await store.importFile(original.path);
      for (final appearance in [
        'unreadable scene',
        {'customImageId': '../wrong.png'},
        {'customImageId': 42},
      ]) {
        await File(path.join(appData.path, 'settings.json'))
            .writeAsString(jsonEncode({
          'Backgrounds': {'mini': appearance}
        }));
        await expectLater(store.removeUnused(() => {}),
            throwsA(isA<BackgroundImageException>()));
        expect(await File(path.join(copies.path, asset.id)).exists(), isTrue);
      }
    });
  });
}
