import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'old editor rename commits into reloaded index without losing playlist draft',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final parent = await Directory(p.join(Directory.current.parent.path, 'tool',
            'qa-2605', 'metadata-instance'))
        .create(recursive: true);
    final fixture = await parent.createTemp('reload-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    addTearDown(() async {
      PLAYLISTS.clear();
      messenger.setMockMethodCallHandler(channel, null);
      expect(p.isWithin(parent.path, fixture.path), isTrue);
      await fixture.delete(recursive: true);
    });
    final data = await getAppDataDir();
    expect(p.isWithin(fixture.path, data.path), isTrue);
    final music =
        await Directory(p.join(fixture.path, 'synthetic-music')).create();
    final source = File(p.join(music.path, 'old.mp3'));
    await source.writeAsBytes([0, 1, 2]);
    final renamed = p.join(music.path, 'new.mp3');
    final index = File(p.join(data.path, 'index.json'));
    Future<void> writeIndex(
            {required int duration, required String composer}) =>
        index
            .writeAsString(jsonEncode({
              'version': 113,
              'roots': [music.path],
              'folders': [
                {
                  'path': music.path,
                  'audios': [
                    {
                      'path': source.path,
                      'title': 'Old title',
                      'artist': 'Original artist',
                      'album': 'Original album',
                      'duration': duration,
                      'composer': composer,
                      'modified': 10,
                      'file_size': 3,
                    }
                  ]
                }
              ],
            }))
            .then((_) {});
    await writeIndex(duration: 1, composer: 'Old composer');
    await AudioLibrary.initFromIndex();
    final editor = AudioLibrary.instance.audioCollection.single;
    final playlist = Playlist('Original name', {editor.path: editor});
    PLAYLISTS.add(playlist);
    final entryId = playlist.entries.single.id;
    await writeIndex(duration: 222, composer: 'Fresh composer');
    await AudioLibrary.initFromIndex();
    playlistTree.refreshAudioReferences(AudioLibrary.instance.audioByPath);
    playlist.name = 'Unsaved user playlist draft';
    final current = AudioLibrary.instance.audioCollection.single;
    expect(current, isNot(same(editor)));
    var writes = 0;
    final coordinator = AudioMetadataEditCoordinator(
        currentAudio: (path) => AudioLibrary.instance.audioByPath[path],
        write: (path, request) async {
          writes++;
          expect(path, source.path);
          await File(path)
              .rename(renamed); // Synthetic bytes, no native tag writer.
          return renamed;
        },
        synchronize: synchronizeAudioMetadataEdit);
    await LibraryMutationGate.shared.run(() => coordinator.apply(
        editor,
        const AudioMetadataEdit(
            fileName: 'new.mp3',
            title: 'User draft title',
            artist: 'User artist',
            album: 'User album')));
    expect(writes, 1);
    expect(editor.title, 'User draft title');
    expect(editor.path, renamed);
    expect(AudioLibrary.instance.audioByPath.containsKey(source.path), isFalse);
    expect(AudioLibrary.instance.audioByPath[renamed], same(current));
    expect(current.title, 'User draft title');
    expect(current.duration, 222);
    expect(current.composer, 'Fresh composer');
    expect(playlist.name, 'Unsaved user playlist draft');
    expect(playlist.entries.single.id, entryId);
    expect(playlist.flattenAudios().single, same(current));
    final saved = jsonDecode(await index.readAsString()) as Map;
    final song = saved['folders'][0]['audios'][0] as Map;
    expect(song['path'], renamed);
    expect(song['title'], 'User draft title');
    expect(song['duration'], 222);
    expect(song['composer'], 'Fresh composer');
  });
}
