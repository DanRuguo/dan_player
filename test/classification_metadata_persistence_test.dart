import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:dan_player/online/online_library.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/music_category_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory fixtureRoot;
  late Directory dataRoot;
  late List<AudioFolder> oldFolders;
  late List<Audio> oldOnline;
  final fixtureParent = path.normalize(path.join(
      Directory.current.path, '..', 'tool', 'qa-categories', 'test-data'));

  setUp(() async {
    final parent = await Directory(fixtureParent).create(recursive: true);
    fixtureRoot = await parent.createTemp('classification-metadata-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => fixtureRoot.path);
    dataRoot = await getAppDataDir();
    // Stop before any fixture is written if a future plugin bypasses the mock.
    expect(path.isWithin(fixtureRoot.path, dataRoot.path), isTrue);
    oldFolders = AudioLibrary.instance.folders;
    oldOnline = AudioLibrary.instance.onlineAudioCollection;
    AudioLibrary.instance.folders = [];
    await OnlineLibrary.instance.initialize();
  });

  tearDown(() async {
    AudioLibrary.instance.folders = oldFolders;
    AudioLibrary.instance.onlineAudioCollection = oldOnline;
    AudioLibrary.instance.rebuildDerivedCollections();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(PlayService.isInitialized, isFalse);
    if (path.isWithin(fixtureParent, fixtureRoot.path) &&
        path
            .basename(fixtureRoot.path)
            .startsWith('classification-metadata-')) {
      await fixtureRoot.delete(recursive: true);
    }
  });

  File fixture(String name) => File(path.join(dataRoot.path, name));

  test(
      'legacy version 113 index save keeps pending classification marker and order',
      () async {
    final a = CategoryTestAudio('First').toMap()
      ..remove('composer')
      ..remove('album_artist')
      ..remove('classification_version');
    final b = CategoryTestAudio('Second').toMap()
      ..remove('classification_version');
    await fixture('index.json').writeAsString(jsonEncode({
      'version': 113,
      'folders': [
        {
          'path': 'D:/category-test-fixtures',
          'modified': 99,
          'latest': 98,
          'audios': [a, b]
        },
      ],
    }));
    await AudioLibrary.initFromIndex();
    expect(AudioLibrary.instance.audioCollection.map((audio) => audio.path),
        [a['path'], b['path']]);
    expect(
        AudioLibrary.instance.audioCollection
            .every((audio) => !audio.classificationTagsRead),
        isTrue);
    await AudioLibrary.instance.saveIndex();
    final saved = jsonDecode(await fixture('index.json').readAsString()) as Map;
    expect(saved['version'], 113);
    final folder = (saved['folders'] as List).single as Map;
    expect(folder['modified'], 99);
    expect(folder['latest'], 98);
    final audios = folder['audios'] as List;
    expect(audios.map((audio) => audio['path']), [a['path'], b['path']]);
    expect(audios.map((audio) => audio['classification_version']), [0, 0]);
  });

  test(
      'classification tags and successful null reads survive local index reload',
      () async {
    final named =
        CategoryTestAudio('Named', composer: 'Writer', albumArtist: 'Owner');
    final empty = CategoryTestAudio('Empty');
    AudioLibrary.instance.folders = [
      AudioFolder([named, empty], 'D:/category-test-fixtures', 10, 9)
    ];
    AudioLibrary.instance.rebuildDerivedCollections();
    await AudioLibrary.instance.saveIndex();
    await AudioLibrary.initFromIndex();
    final loaded = AudioLibrary.instance.audioCollection;
    expect(loaded.first.composer, 'Writer');
    expect(loaded.first.albumArtist, 'Owner');
    expect(loaded.last.composer, isNull);
    expect(loaded.last.classificationTagsRead, isTrue);
    final contributors = MusicCategories(loaded)
        .groups(MusicCategoryKind.composer)
        .firstWhere((group) => group.title == 'Artist');
    expect(contributors.evidenceCounts, {ClassificationEvidence.fallback: 1});
    expect(contributors.audios.single, same(loaded.last));
    final disk = jsonDecode(await fixture('index.json').readAsString()) as Map;
    final diskAudios =
        ((disk['folders'] as List).single as Map)['audios'] as List;
    expect((diskAudios.last as Map)['composer'], isNull,
        reason:
            'the contributor browsing fallback must not persist as a composer tag');
  });

  test(
      'online metadata refresh preserves classification tags and does not lose source identity',
      () async {
    final original = CategoryTestAudio('same',
        online: true, composer: 'Writer', albumArtist: 'Owner', language: 'ja');
    await OnlineLibrary.instance.add(original);
    final refresh = Audio.online(
        provider: 'qq',
        id: 'same',
        title: 'Updated',
        artist: 'New singer',
        album: 'New album',
        duration: 121,
        classificationVersion: 0);
    await OnlineLibrary.instance.add(refresh);
    final updated = OnlineLibrary.instance.audios.single;
    expect(updated.path, original.path);
    expect(updated.created, original.created);
    expect(updated.title, 'Updated');
    expect(updated.composer, 'Writer');
    expect(updated.albumArtist, 'Owner');
    expect(updated.language, 'ja');
    expect(updated.classificationTagsRead, isTrue);
    await OnlineLibrary.instance.initialize();
    final restored = OnlineLibrary.instance.audios.single;
    expect(restored.composer, 'Writer');
    expect(restored.albumArtist, 'Owner');
    expect(restored.isOnline, isTrue);
  });

  test('online explicit replacement metadata updates all classification tags',
      () async {
    await OnlineLibrary.instance.add(CategoryTestAudio('same',
        online: true,
        composer: 'Old writer',
        albumArtist: 'Old owner',
        classificationVersion: 0));
    await OnlineLibrary.instance.add(CategoryTestAudio('same',
        online: true, composer: 'New writer', albumArtist: 'New owner'));
    final updated = OnlineLibrary.instance.audios.single;
    expect(updated.composer, 'New writer');
    expect(updated.albumArtist, 'New owner');
    expect(updated.classificationVersion, 1);
    expect(AudioLibrary.instance.onlineAudioCollection.single, same(updated));
  });
}
