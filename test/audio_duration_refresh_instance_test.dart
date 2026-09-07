import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_duration_correction.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'duration correction after index reload saves the current library instance',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent = await Directory(p.join(Directory.current.parent.path, 'tool',
            'qa-2605', 'duration-instance'))
        .create(recursive: true);
    final fixture = await parent.createTemp('reload-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    addTearDown(() async {
      await audioDurationCorrections.settled;
      messenger.setMockMethodCallHandler(channel, null);
      expect(p.isWithin(parent.path, fixture.path), isTrue);
      await fixture.delete(recursive: true);
    });
    final data = await getAppDataDir();
    expect(p.isWithin(fixture.path, data.path), isTrue);
    final index = File(p.join(data.path, 'index.json'));
    Future<void> writeIndex(List<String> names) => index
        .writeAsString(jsonEncode({
          'version': 113,
          'roots': ['C:/synthetic-duration'],
          'folders': [
            {
              'path': 'C:/synthetic-duration',
              'audios': [
                for (final name in names)
                  {
                    'path': 'C:/synthetic-duration/$name.mp3',
                    'title': name,
                    'artist': 'Fixture',
                    'album': 'Synthetic',
                    'duration': 0,
                    'modified': 10,
                    'modified_ns': '10000000100',
                    'file_size': 100,
                  }
              ],
            }
          ],
        }))
        .then((_) {});
    await writeIndex(['kept', 'removed']);
    await AudioLibrary.initFromIndex();
    final previous = AudioLibrary.instance;
    final coordinator = audioDurationCorrections;
    await writeIndex(['kept', 'added']);
    await AudioLibrary.initFromIndex();
    final current = AudioLibrary.instance;
    expect(current, isNot(same(previous)));
    coordinator.observe(current.audioCollection.first, 125.5);
    await coordinator.settled;
    final saved = jsonDecode(await index.readAsString()) as Map;
    final songs = ((saved['folders'] as List).single as Map)['audios'] as List;
    expect(songs.map((song) => song['title']), ['kept', 'added']);
    expect(songs.first['duration'], 125);
    expect(songs.first['duration_version'], 1);
    expect(previous.audioCollection.map((song) => song.title),
        ['kept', 'removed']);
    expect(previous.audioCollection.first.duration, 0);
  });
}
