import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _HealthAudio extends Fake implements Audio {
  _HealthAudio(this.path);
  @override final String path;
  @override bool get isLocal => true;
  @override String get localFilePath => path;
  @override bool get metadataReadPending => true;
}

void main() {
  late Directory root, music;
  setUp(() async {
    final base = Directory(Platform.environment['DAN_PLAYER_DATA_DIR'] ?? 'build/qa-health');
    await base.create(recursive: true);
    root = await base.createTemp('health-');
    music = await Directory(p.join(root.path, 'music')).create();
  });
  tearDown(() async { await root.delete(recursive: true); });

  test('offline root preserves files and does not classify every song as missing', () async {
    final offline = p.join(root.path, 'offline');
    final library = AudioLibrary.instance;
    library.folders = [AudioFolder([], music.path, 0, 0), AudioFolder([], offline, 0, 0)];
    library.audioCollection = [_HealthAudio(p.join(music.path, 'gone.flac')),
      _HealthAudio(p.join(offline, 'offline.flac'))];
    final report = await LibraryHealthService(root).inspect(library, files: true);
    expect(report.sources[0].availability, LibraryAvailability.available);
    expect(report.sources[1].availability, LibraryAvailability.sourceOffline);
    expect(report.missing, 1);
    expect(report.unverified, 1);
    expect(library.audioCollection.length, 2);
  });
  test('failed scan retains previous success time and reopening source clears failure', () async {
    final service = LibraryHealthService(root);
    await service.recordScan([music.path]);
    final file = File(p.join(root.path, 'library_health.json'));
    final first = jsonDecode(await file.readAsString())['sources'][music.path]['lastSuccess'];
    await service.recordScan([music.path], failure: 'offline');
    final failed = jsonDecode(await file.readAsString())['sources'][music.path];
    expect(failed['lastSuccess'], first);
    expect(failed['failure'], isNotNull);
    await service.recordScan([music.path]);
    expect(jsonDecode(await file.readAsString())['sources'][music.path]['failure'], isNull);
  });
}
