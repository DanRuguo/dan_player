import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Directory music;
  late LibraryHealthService service;
  late List<AudioFolder> previousFolders;
  late List<Audio> previousAudios;
  final library = AudioLibrary.instance;
  const success = '2026-09-19T01:23:45.000Z';
  File file(String suffix) =>
      File(p.join(root.path, 'library_health.json$suffix'));
  String snapshot({int version = 1}) => jsonEncode({
        'version': version,
        'sources': {
          music.path: {'lastSuccess': success, 'failure': 'Synthetic failure'},
          'remembered-offline-root': {'lastSuccess': success}
        }
      });

  setUp(() async {
    final parent =
        await Directory(p.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    root = await parent.createTemp('health-recovery-');
    music = await Directory(p.join(root.path, 'synthetic-music')).create();
    service = LibraryHealthService(root);
    previousFolders = library.folders;
    previousAudios = library.audioCollection;
    library.folders = [AudioFolder([], music.path, 0, 0)];
    library.audioCollection = [];
  });

  tearDown(() async {
    library.folders = previousFolders;
    library.audioCollection = previousAudios;
    expect(
        p.isWithin(
            p.join(Directory.current.path, 'build', 'test-data'), root.path),
        isTrue);
    await root.delete(recursive: true);
  });

  test(
      'inspection reads a healthy backup without rewriting the corrupt primary',
      () async {
    final backup = snapshot();
    await file('').writeAsString('{corrupt');
    await file('.bak').writeAsString(backup);

    final report = await service.inspect(library);

    expect(report.sources.single.lastSuccess, DateTime.parse(success));
    expect(report.sources.single.reason, 'Synthetic failure');
    expect(report.sources.single.availability, LibraryAvailability.available);
    expect(await file('').readAsString(), '{corrupt');
    expect(await file('.bak').readAsString(), backup);
    expect(await file('.tmp').exists(), isFalse);
  });

  test(
      'recording after recovery preserves the good backup and old root history',
      () async {
    final backup = snapshot();
    await file('').writeAsString('{corrupt');
    await file('.bak').writeAsString(backup);

    await service.recordScan([music.path], failure: 'Synthetic offline');

    final saved = jsonDecode(await file('').readAsString()) as Map;
    expect(saved['sources'][music.path]['lastSuccess'], success);
    expect(saved['sources'][music.path]['failure'], isNotNull);
    expect(saved['sources']['remembered-offline-root']['lastSuccess'], success);
    expect(await file('.bak').readAsString(), backup);
    expect(await file('.tmp').exists(), isFalse);
  });

  test(
      'a missing primary recovers history without creating a file on inspection',
      () async {
    final backup = snapshot();
    await file('.bak').writeAsString(backup);

    final report = await service.inspect(library);

    expect(report.sources.single.lastSuccess, DateTime.parse(success));
    expect(await file('').exists(), isFalse);
    expect(await file('.bak').readAsString(), backup);
  });

  test(
      'two corrupt snapshots are surfaced and never replaced with empty history',
      () async {
    await file('').writeAsString('{corrupt primary');
    await file('.bak').writeAsString('{corrupt backup');

    await expectLater(service.inspect(library), throwsFormatException);
    await expectLater(service.recordScan([music.path]), throwsFormatException);

    expect(await file('').readAsString(), '{corrupt primary');
    expect(await file('.bak').readAsString(), '{corrupt backup');
    expect(await file('.tmp').exists(), isFalse);
  });

  test('a future primary is protected even when a version one backup exists',
      () async {
    final future = snapshot(version: 2);
    final backup = snapshot();
    await file('').writeAsString(future);
    await file('.bak').writeAsString(backup);

    await expectLater(service.inspect(library), throwsUnsupportedError);
    await expectLater(service.recordScan([music.path]), throwsUnsupportedError);

    expect(await file('').readAsString(), future);
    expect(await file('.bak').readAsString(), backup);
    expect(await file('.tmp').exists(), isFalse);
  });

  test(
      'malformed source records fall back before the report casts their fields',
      () async {
    final broken = jsonEncode({
      'version': 1,
      'sources': {
        music.path: {'lastSuccess': 123, 'failure': []}
      }
    });
    await file('').writeAsString(broken);
    await file('.bak').writeAsString(snapshot());

    final report = await service.inspect(library);

    expect(report.sources.single.lastSuccess, DateTime.parse(success));
    expect(await file('').readAsString(), broken);
  });
}
