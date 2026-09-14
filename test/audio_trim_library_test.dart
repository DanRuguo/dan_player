import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:dan_player/library/track_resume_store.dart';
import 'package:dan_player/play_service/track_resume_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'copy in another folder survives refresh; overwrite updates playlist identity and duration',
      () async {
    expect(Platform.environment['DAN_PLAYER_DATA_DIR']?.trim() ?? '', isEmpty);
    final root = await Directory(p.absolute(
            '..', 'tool', 'validation', 'sep14-audio-trim', 'library'))
        .create(recursive: true);
    final fixture = await root.createTemp('sync-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => fixture.path);
    addTearDown(() async {
      PLAYLISTS.clear();
      messenger.setMockMethodCallHandler(channel, null);
      expect(p.isWithin(root.path, fixture.path), isTrue);
      await fixture.delete(recursive: true);
    });
    final data = await getAppDataDir();
    expect(p.isWithin(fixture.path, data.path), isTrue);
    final music = await Directory(p.join(fixture.path, 'music')).create();
    final export = await Directory(p.join(fixture.path, 'export')).create();
    final source = File(p.join(music.path, 'original.wav'));
    await source.writeAsBytes([1, 2, 3]);
    final index = File(p.join(data.path, 'index.json'));
    final sourceMap = <String, dynamic>{
      'path': source.path,
      'title': 'Original',
      'artist': 'Artist',
      'album': 'Album',
      'composer': 'Composer',
      'duration': 180,
      'file_size': 3,
      'sample_rate': 48000,
      'track': 4
    };
    await index.writeAsString(jsonEncode({
      'version': 113,
      'roots': [music.path],
      'folders': [
        {
          'path': music.path,
          'audios': [sourceMap]
        }
      ]
    }));
    await AudioLibrary.initFromIndex();
    final original = AudioLibrary.instance.audioCollection.single;
    final identity = original.stableTrackId;
    final playlist = Playlist('Keep this order', {source.path: original});
    PLAYLISTS.add(playlist);
    final entryId = playlist.entries.single.id;
    final personal = await PersonalLibrary.instance;
    await personal.apply([original],
        changeRating: true,
        rating: 4,
        changeTags: true,
        addTags: ['收藏', '日本語']);
    final copied = File(p.join(export.path, 'copy.wav'));
    await copied.writeAsBytes([4, 5, 6]);
    final copyRequest = AudioTrimRequest(
        destinationPath: copied.path, startSeconds: 10, endSeconds: 60);
    await synchronizeTrimmedAudio(original, copyRequest,
        {...sourceMap, 'path': copied.path, 'duration': 50});
    final copy = AudioLibrary.instance.audioByPath[copied.path]!;
    expect(copy.stableTrackId, isNot(identity));
    expect(copy.composer, 'Composer');
    expect(copy.track, 4);
    expect(AudioLibrary.instance.scanRoots, contains(export.path));
    final copiedPersonal = (await personal.snapshot())[copy.stableTrackId]!;
    expect(copiedPersonal.rating, 4);
    expect(copiedPersonal.tags, ['收藏', '日本語']);
    expect(playlist.entries.single.id, entryId);
    expect(playlist.flattenAudios().single.duration, 180);

    final resume = await TrackResumeStore.instance;
    await resume.remember(
        track: original.path,
        position: 60,
        duration: 180,
        preferences:
            const TrackResumePreferences(mode: TrackResumeMode.allLocal),
        force: true);
    await synchronizeTrimmedAudio(
        original,
        AudioTrimRequest(
            destinationPath: source.path,
            startSeconds: 15,
            endSeconds: 80,
            overwrite: true),
        {...sourceMap, 'duration': 65, 'title': 'Edited title'});
    final current = AudioLibrary.instance.audioByPath[source.path]!;
    expect(current.stableTrackId, identity);
    expect(current.duration, 65);
    expect(playlist.entries.single.id, entryId);
    expect(playlist.flattenAudios().single, same(current));
    expect((await personal.snapshot())[identity]!.rating, 4);
    expect(
        await resume.resumePosition(
            track: original.path,
            duration: 180,
            preferences:
                const TrackResumePreferences(mode: TrackResumeMode.allLocal)),
        isNull);
    await AudioLibrary.initFromIndex();
    expect(AudioLibrary.instance.audioByPath[copied.path]!.duration, 50);
    expect(AudioLibrary.instance.audioByPath[source.path]!.duration, 65);
    expect(AudioLibrary.instance.scanRoots, contains(export.path));
  });
}
