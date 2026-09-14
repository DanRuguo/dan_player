import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/library/cover_image_import.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Future<Uint8List> _png(int width, int height, {int color = 0xff246899}) async {
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
  test('valid small transparent images retain exact encoded bytes', () async {
    final bytes = await _png(80, 40, color: 0x68234567);
    var nativeCalls = 0;
    final importer = CoverImageImporter(normalizeLarge: (_) async {
      nativeCalls++;
      throw StateError('small covers should not be re-encoded');
    });
    final result = await importer.fromBytes(bytes);
    expect(result.bytes, bytes);
    expect([result.width, result.height, result.extension], [80, 40, 'png']);
    expect(nativeCalls, 0);
    final codec = await ui.instantiateImageCodec(result.bytes);
    final decoded = (await codec.getNextFrame()).image;
    final rgba = await decoded.toByteData();
    expect(rgba!.getUint8(3), 0x68);
    decoded.dispose();
    codec.dispose();
  });

  test(
      'bad and over-limit inputs fail before native processing and queue recovers',
      () async {
    var calls = 0;
    final importer = CoverImageImporter(normalizeLarge: (_) async {
      calls++;
      throw StateError('not reached');
    });
    final valid = await _png(32, 32);
    for (final bytes in [
      Uint8List(0),
      Uint8List(maxCoverInputBytes + 1),
      Uint8List.fromList([1, 2, 3]),
      Uint8List.sublistView(valid, 0, 35)
    ]) {
      await expectLater(
          importer.fromBytes(bytes), throwsA(isA<CoverImageException>()));
    }
    expect((await importer.fromBytes(valid)).bytes, valid);
    expect(calls, 0);
  });

  test(
      'large images use one native job at a time and enforce its output budget',
      () async {
    final large = await _png(1700, 40);
    final prepared = await _png(1600, 37);
    final jobs = <Completer<PreparedCoverImage>>[];
    final importer = CoverImageImporter(normalizeLarge: (_) {
      final job = Completer<PreparedCoverImage>();
      jobs.add(job);
      return job.future;
    });
    final first = importer.fromBytes(large);
    final second = importer.fromBytes(large);
    for (var i = 0; i < 30 && jobs.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(jobs, hasLength(1));
    jobs[0].complete(PreparedCoverImage(prepared, 'png', 1600, 37));
    expect((await first).bytes, prepared);
    for (var i = 0; i < 30 && jobs.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(jobs, hasLength(2));
    final rejected = expectLater(second, throwsA(isA<CoverImageException>()));
    jobs[1].complete(PreparedCoverImage(
        Uint8List(maxCoverOutputBytes + 1), 'png', 1600, 37));
    await rejected;
  });

  test(
      'playlist imports are independent deduplicated copies with unchanged source',
      () async {
    final parent = Directory('build/cover-import-fixtures').absolute;
    await parent.create(recursive: true);
    final fixture = await parent.createTemp('cover-');
    addTearDown(() async {
      final resolved = await fixture.resolveSymbolicLinks();
      expect(
          path.isWithin(await parent.resolveSymbolicLinks(), resolved), isTrue);
      await Directory(resolved).delete(recursive: true);
    });
    final bytes = await _png(120, 80);
    final original =
        await File(path.join(fixture.path, 'original.png')).writeAsBytes(bytes);
    final data = Directory(path.join(fixture.path, 'data'));
    final first = await importPlaylistCoverFile(original.path,
        dataDirectory: () async => data);
    final second = await importPlaylistCoverFile(original.path,
        dataDirectory: () async => data);
    expect(first, second);
    expect(first, isNot(original.path));
    expect(isImportedCoverId(path.basename(first)), isTrue);
    expect(await original.readAsBytes(), bytes);
    expect(await File(first).readAsBytes(), bytes);
    await original.delete();
    expect(await File(first).readAsBytes(), bytes);
    final files = await File(first).parent.list().toList();
    expect(files, hasLength(1), reason: 'owned temporary directory is removed');
  });

  test('fragmented image headers are rejected before a decoder runs', () async {
    final valid = await _png(10, 10);
    final bytes = BytesBuilder()..add(valid.sublist(0, 33));
    for (var i = 0; i < 4097; i++) {
      bytes.add([0, 0, 0, 0, 116, 69, 88, 116, 0, 0, 0, 0]);
    }
    bytes.add(valid.sublist(33));
    await expectLater(CoverImageImporter.shared.fromBytes(bytes.takeBytes()),
        throwsA(isA<CoverImageException>()));
  });

  test('queued cover bytes have a finite budget and recover after completion', () async {
    final png = await _png(1700, 10);
    final input = Uint8List(maxCoverInputBytes)..setRange(0, png.length, png);
    final output = await _png(1600, 9);
    final gate = Completer<void>();
    final importer = CoverImageImporter(normalizeLarge: (_) async {
      await gate.future;
      return PreparedCoverImage(output, 'png', 1600, 9);
    });
    final first = [for (var i = 0; i < 3; i++) importer.fromBytes(input)];
    await expectLater(importer.fromBytes(input), throwsA(isA<CoverImageException>()));
    gate.complete();
    await Future.wait(first);
    expect((await importer.fromBytes(output)).bytes, output);
  });
}
