import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/collection.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

Audio _local(String title) => Audio.fromMap({
      'path': 'D:\\migration-fixture\\$title.flac',
      'title': title,
      'artist': '原歌手',
      'album': '原专辑',
      'duration': 123,
      'created': 1700000000,
      'language': 'zho',
    });

Map<String, Object?> _collection(String? id, String name, List<String> paths,
        {String? imagePath,
        int createdAt = 1700000000123,
        int modifiedAt = 1700000000456}) =>
    {
      if (id != null) 'id': id,
      'name': name,
      'audioPaths': paths,
      'imagePath': imagePath,
      'createdAt': createdAt,
      'modifiedAt': modifiedAt,
    };

String _legacy(List<Object?> collections) =>
    jsonEncode({'version': 1, 'collections': collections});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;
  late Directory dataRoot;
  late List<AudioFolder> priorFolders;
  final remote = Audio.online(
    provider: 'qq',
    id: 'mid/with slash',
    title: '已入库在线歌曲',
    artist: '远程歌手',
    album: '远程专辑',
    duration: 240,
    mediaId: 'media-id',
    numericId: 12345,
    artworkUrl: 'https://example.com/cover.jpg',
    created: 1700000000,
  );

  void restorePathHandler() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => testRoot.path);

  File fixture(String name) => File(path.join(dataRoot.path, name));

  Future<Map> savedStore() async =>
      jsonDecode(await fixture('playlists.json').readAsString()) as Map;

  Future<void> putCollections(List<Object?> records) async =>
      fixture('collections.json').writeAsString(_legacy(records));

  setUp(() async {
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    testRoot = await parent.createTemp('collection-migration-');
    restorePathHandler();
    dataRoot = await getAppDataDir();
    // Abort before reading/writing fixtures if the platform plugin ever stops
    // honoring the mock. Never touch installed-app or real library data.
    expect(path.isWithin(testRoot.path, dataRoot.path), isTrue);
    priorFolders = AudioLibrary.instance.folders;
    AudioLibrary.instance.folders = [];
    AudioLibrary.instance.replaceOnlineAudios([]);
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    expect(playlistStorageWarning, isNull);
  });

  tearDown(() async {
    restorePathHandler();
    if (playlistsHaveUnsavedChanges) {
      final blocked = Directory(fixture('playlists.json.tmp').path);
      if (await blocked.exists()) {
        expect(path.isWithin(testRoot.path, blocked.path), isTrue);
        await blocked.delete();
      }
      await savePlaylists();
    }
    PLAYLISTS.clear();
    AudioLibrary.instance.folders = priorFolders;
    AudioLibrary.instance.replaceOnlineAudios([]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final expectedParent =
        path.join(Directory.current.path, 'build', 'test-data');
    if (path.isWithin(expectedParent, testRoot.path)) {
      await testRoot.delete(recursive: true);
    }
  });

  test(
      'merge preserves existing nested entries, every collection and source files',
      () async {
    final tree = playlistTree;
    final root = tree.createPlaylist('同名');
    tree.addAudio(root, _local('A'));
    final child = tree.createPlaylist('子歌单', parent: root);
    tree.addAudio(child, remote);
    tree.addAudio(root, _local('F'));
    final before = root.toMap();
    final original = jsonEncode([before]);
    final previous = jsonEncode([Playlist('更早的备份', {}).toMap()]);
    await fixture('playlists.json').writeAsString(original);
    await fixture('playlists.json.bak').writeAsString(previous);
    final known = _local('已入库');
    AudioLibrary.instance.replaceOnlineAudios([remote]);
    AudioLibrary.instance.audioByPath[known.path] = known;
    const missing = 'Z:\\暂未挂载\\仍要保留.flac';
    const image = 'Z:\\自选封面\\不存在也不能丢.png';
    final source = _legacy([
      _collection(
          'collection-1', '同名', [known.path, missing, remote.path, known.path],
          imagePath: image),
      _collection('collection-2', '同名', [remote.path], imagePath: null),
      _collection('empty', '  原标题空格也保留  ', []),
    ]);
    const oldBackup = 'original collection backup bytes';
    const customOrder = '{"version":1,"paths":["Z:\\custom-2","Z:\\custom-1"]}';
    await fixture('collections.json').writeAsString(source);
    await fixture('collections.json.bak').writeAsString(oldBackup);
    await fixture('custom_audio_order.json').writeAsString(customOrder);

    await readPlaylists();

    expect(PLAYLISTS.map((p) => p.name), ['同名', '同名', '同名', '  原标题空格也保留  ']);
    expect(PLAYLISTS.first.toMap(), before);
    final migrated = playlistTree.findByLegacyCollectionId('collection-1')!;
    expect(migrated.imagePath, image);
    expect(migrated.createdAt, 1700000000123);
    expect(migrated.modifiedAt, 1700000000456);
    expect(migrated.flattenAudios().map((a) => a.path),
        [known.path, missing, remote.path, known.path]);
    expect(migrated.entries.first.audio, same(known));
    expect(migrated.entries[2].audio, same(remote));
    expect(migrated.entries.map((e) => e.id).toSet(), hasLength(4));
    expect(migrated.audios.keys, [known.path, missing, remote.path]);
    final saved = await savedStore();
    expect(saved['version'], 4);
    expect(saved['legacyCollectionsMigrated'], isTrue);
    expect(saved['migratedCollectionKeys'], hasLength(3));
    expect(await fixture('collections.json').readAsString(), source);
    expect(await fixture('collections.json.bak').readAsString(), oldBackup);
    expect(
        await fixture('custom_audio_order.json').readAsString(), customOrder);
    expect(
        await fixture('playlists.before-collection-merge.json.bak')
            .readAsString(),
        original);
    expect(
        await fixture('playlists.before-collection-merge.previous.bak')
            .readAsString(),
        previous);
    expect(await fixture('playlists.json.bak').readAsString(), original);
    expect(playlistStorageWarning, isNull);
  });

  test(
      'duplicate source IDs and missing IDs never deduplicate by name or content',
      () async {
    final a = _local('A');
    final records = [
      _collection('same-id', '同名', [a.path]),
      _collection('same-id', '同名', [a.path]),
      _collection('other-id', '同名', [a.path]),
      _collection(null, '同名', [a.path]),
      _collection(null, '同名', [a.path]),
    ];
    await putCollections(records);
    await readPlaylists();
    final first = playlistTree.findByLegacyCollectionId('same-id')!;
    final second =
        playlistTree.findByLegacyCollectionId('same-id', occurrence: 1)!;
    expect(first, isNot(same(second)));
    expect(PLAYLISTS.map((p) => p.id).toSet(), hasLength(5));
    expect(PLAYLISTS.map((p) => p.legacyCollectionKey).toSet(), hasLength(5));
    final ids = PLAYLISTS.map((p) => p.id).toList();
    playlistTree.setOrder(parent: null, entryIds: ids.reversed.toList());
    playlistTree.moveEntry(
        sourceParent: null, entryId: first.id, targetParent: second);
    expect(playlistTree.findByLegacyCollectionId('same-id'), same(first));
    expect(playlistTree.findByLegacyCollectionId('same-id', occurrence: 1),
        same(second));
    expect(playlistTree.findByLegacyCollectionId('same-id', occurrence: -1),
        isNull);
    await savePlaylists();
    await readPlaylists();
    expect(playlistTree.allPlaylists.map((p) => p.id).toSet(), ids.toSet());
    expect(playlistTree.findByLegacyCollectionId('same-id')!.parent!.id,
        second.id);
  });

  test(
      'unknown local and online references persist without requiring a library scan',
      () async {
    const missing = 'Q:\\音乐\\待重新挂载.mp3';
    const online = 'online://netease/998877';
    await putCollections([
      _collection('missing', '保留未解析引用', [missing, online, missing])
    ]);
    await readPlaylists();
    final migrated = PLAYLISTS.single;
    final before = migrated.toMap();
    expect(migrated.flattenAudios().map((a) => a.path),
        [missing, online, missing]);
    expect(
        migrated.flattenAudios().map((a) => a.isOnline), [false, true, false]);
    expect(migrated.entries[1].audio!.onlineId, '998877');
    expect(migrated.entries[1].audio!.created, 0);
    expect(AudioLibrary.instance.audioCollection, isEmpty);
    await readPlaylists();
    expect(PLAYLISTS.single.toMap(), before);
  });

  test('song selection retains repeated occurrences and interleaved children',
      () async {
    final a = _local('A');
    final b = _local('B');
    await putCollections([
      _collection('repeat', '重复', [a.path, b.path, a.path])
    ]);
    await readPlaylists();
    final p = PLAYLISTS.single;
    final originalIds = p.entries.map((e) => e.id).toList();
    final child = playlistTree.createPlaylist('子', parent: p, index: 1);
    final childSong = playlistTree.addAudio(child, b);
    final c = _local('C');
    playlistTree.setDirectAudios(p, [a, b, c]);
    expect(p.entries.take(4).map((e) => e.id),
        [originalIds[0], child.id, originalIds[1], originalIds[2]]);
    expect(p.flattenAudios().map((audio) => audio.path),
        [a.path, b.path, b.path, a.path, c.path]);
    expect(p.flattenedIndexOf(originalIds[2]), 3);
    expect(p.flattenedIndexOf(childSong.id), 1);
    p.audios = p.audios;
    expect(p.entries, hasLength(5));
    playlistTree.setDirectAudios(p, [b, c]);
    expect(p.entries.first.childPlaylist, same(child));
    expect(child.entries.single.id, childSong.id);
    expect(p.entries.where((e) => e.audio?.path == a.path), isEmpty);
    await savePlaylists();
    await readPlaylists();
    expect(PLAYLISTS.single.flattenAudios().map((a) => a.path),
        [b.path, b.path, c.path]);
  });

  test(
      'compatibility Map writes update or remove all direct aliases, not children',
      () async {
    final a = _local('A');
    final b = _local('B');
    await putCollections([
      _collection('repeat', '重复', [a.path, a.path])
    ]);
    await readPlaylists();
    final p = PLAYLISTS.single;
    final ids = p.entries.map((e) => e.id).toList();
    final child = playlistTree.createPlaylist('子', parent: p, index: 1);
    playlistTree.addAudio(child, a);
    p.audios[a.path] = a;
    expect(p.audios, hasLength(1));
    expect(p.entries.where((e) => e.audio != null).map((e) => e.id), ids);
    expect(
        p.entries
            .where((e) => e.audio != null)
            .every((e) => identical(e.audio, a)),
        isTrue);
    p.audios[b.path] = b;
    expect(p.audios.remove(a.path), same(a));
    expect(p.entries.map((e) => e.childPlaylist?.name ?? e.audio!.title),
        ['子', 'B']);
    expect(child.flattenAudios(), [a]);
  });

  test(
      'reordering repeated legacy songs keeps each occurrence and its playback index',
      () async {
    final a = _local('A');
    final b = _local('B');
    await putCollections([
      _collection('repeat', '重复', [a.path, b.path, a.path])
    ]);
    await readPlaylists();
    final p = PLAYLISTS.single;
    final ids = p.entries.map((e) => e.id).toList();
    playlistTree.reorder(parent: p, oldIndex: 2, newIndex: 0);
    expect(p.entries.map((e) => e.id), [ids[2], ids[0], ids[1]]);
    expect(p.flattenedIndexOf(ids[2]), 0);
    expect(p.flattenedIndexOf(ids[0]), 1);
    expect(playlistTree.addAudio(p, a).id, ids[2]);
    expect(p.entries, hasLength(3));
  });

  test(
      'metadata/path refresh preserves all migrated occurrences and source files',
      () async {
    final a = _local('旧文件名');
    final source = _legacy([
      _collection('rename', '来源', [a.path, a.path])
    ]);
    await fixture('collections.json').writeAsString(source);
    AudioLibrary.instance.audioByPath[a.path] = a;
    await readPlaylists();
    final p = PLAYLISTS.single;
    final child = playlistTree.createPlaylist('子', parent: p, index: 1);
    playlistTree.addAudio(child, a);
    final ids = p.flattenEntries().map((e) => e.entryId).toList();
    final old = a.path;
    const renamed = 'D:\\migration-fixture\\新文件名.flac';
    a.applyEditedMetadata(
        newPath: renamed,
        newTitle: '新标题',
        newArtist: '新歌手',
        newAlbum: '新专辑',
        newModified: 42);
    expect(replaceAudioInPlaylists(old, renamed, a), isTrue);
    expect(p.flattenEntries().map((e) => e.entryId), ids);
    expect(p.flattenAudios().map((e) => e.path), [renamed, renamed, renamed]);
    expect(p.createdAt, 1700000000123);
    expect(p.modifiedAt, greaterThan(1700000000456));
    await savePlaylists();
    await readPlaylists();
    expect(PLAYLISTS.single.flattenAudios().map((e) => e.path),
        [renamed, renamed, renamed]);
    expect(await fixture('collections.json').readAsString(), source);
    expect(userCollections.single.audioPaths, [renamed, renamed]);
  });

  test(
      'repeated reads and saves keep migration idempotent and original backups immutable',
      () async {
    final existing = playlistTree.createPlaylist('已有歌单');
    await savePlaylists();
    final original = await fixture('playlists.json').readAsString();
    await putCollections([
      _collection('id', '旧合集', [_local('A').path])
    ]);
    final source = await fixture('collections.json').readAsString();
    await readPlaylists();
    final ids = PLAYLISTS.map((p) => p.id).toList();
    final importedId = PLAYLISTS.last.id;
    for (var i = 0; i < 3; i++) {
      await readPlaylists();
      playlistTree.rename(playlistTree.findPlaylist(importedId)!, '重命名 $i');
      await savePlaylists();
    }
    expect(PLAYLISTS.map((p) => p.id), ids);
    expect(PLAYLISTS.first.id, existing.id);
    expect((await savedStore())['migratedCollectionKeys'], hasLength(1));
    expect(await fixture('collections.json').readAsString(), source);
    expect(
        await fixture('playlists.before-collection-merge.json.bak')
            .readAsString(),
        original);
  });

  test(
      'deleting every migrated node cannot resurrect it from the retained old source',
      () async {
    final source = _legacy([
      _collection('deleted', '删除后不复活', [_local('A').path])
    ]);
    await fixture('collections.json').writeAsString(source);
    await readPlaylists();
    final key = PLAYLISTS.single.legacyCollectionKey!;
    playlistTree.removeEntry(parent: null, entryId: PLAYLISTS.single.id);
    await savePlaylists();
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    expect((await savedStore())['migratedCollectionKeys'], [key]);
    expect((await savedStore())['legacyCollectionsMigrated'], isTrue);
    expect(await fixture('collections.json').readAsString(), source);
    // Once committed, a damaged old read-only source cannot block the new DB.
    await fixture('collections.json').writeAsString('{damaged after migration');
    await readPlaylists();
    expect(playlistStorageWarning, isNull);
    await savePlaylists();
    expect(PLAYLISTS, isEmpty);
  });

  test(
      'failed migration save keeps the merged tree dirty and retries without duplicates',
      () async {
    final old = playlistTree.createPlaylist('已有');
    await savePlaylists();
    final original = await fixture('playlists.json').readAsString();
    final source = _legacy([
      _collection('new', '待合并', [_local('A').path])
    ]);
    await fixture('collections.json').writeAsString(source);
    final blocked = Directory(fixture('playlists.json.tmp').path);
    await blocked.create();
    try {
      await readPlaylists();
      expect(PLAYLISTS.map((p) => p.name), ['已有', '待合并']);
      final migrated = PLAYLISTS.last;
      expect(PLAYLISTS.first.id, old.id);
      expect(playlistsHaveUnsavedChanges, isTrue);
      expect(playlistsReadBlocked, isFalse);
      expect(playlistStorageWarning, contains('尚未保存'));
      expect(await fixture('playlists.json').readAsString(), original);
      expect(await fixture('collections.json').readAsString(), source);
      await readPlaylists();
      expect(PLAYLISTS.last, same(migrated));
      expect(PLAYLISTS, hasLength(2));
      playlistTree.rename(migrated, '失败后仍可继续编辑');
      expect(migrated.name, '失败后仍可继续编辑');
      await blocked.delete();
      await savePlaylists();
      expect(playlistsHaveUnsavedChanges, isFalse);
      expect(playlistStorageWarning, isNull);
      await readPlaylists();
      expect(PLAYLISTS, hasLength(2));
      expect(PLAYLISTS.last.id, migrated.id);
      expect((await savedStore())['migratedCollectionKeys'],
          [migrated.legacyCollectionKey]);
    } finally {
      if (await blocked.exists()) await blocked.delete();
    }
  });

  test(
      'restarting from pre-migration bytes regenerates identical source occurrence IDs',
      () async {
    final old = playlistTree.createPlaylist('原始');
    await savePlaylists();
    final original = await fixture('playlists.json').readAsString();
    await putCollections([
      _collection('duplicate', '同名', [_local('A').path, _local('A').path]),
      _collection('duplicate', '同名', [_local('B').path]),
      _collection(null, '缺少旧ID', ['online://netease/12']),
    ]);
    final blocked = Directory(fixture('playlists.json.tmp').path);
    await blocked.create();
    await readPlaylists();
    final first = PLAYLISTS.map((p) => p.toMap()).toList();
    await blocked.delete();
    await savePlaylists();
    // Reset disk to the state a new process would observe after the failed
    // migration, rather than exposing a production reset/dirty-bypass API.
    await fixture('playlists.json').writeAsString(original);
    await fixture('playlists.json.bak').delete();
    PLAYLISTS.clear();
    await readPlaylists();
    expect(PLAYLISTS.first.id, old.id);
    expect(PLAYLISTS.map((p) => p.toMap()), first);
  });

  test(
      'whole legacy backup is recovered without repairing or overwriting the old files',
      () async {
    const broken = '{broken collection primary';
    final backup = _legacy([
      _collection('backup', '备份恢复', [_local('A').path, _local('A').path],
          imagePath: 'D:\\covers\\keep.jpg'),
    ]);
    await fixture('collections.json').writeAsString(broken);
    await fixture('collections.json.bak').writeAsString(backup);
    await readPlaylists();
    expect(PLAYLISTS.single.name, '备份恢复');
    expect(PLAYLISTS.single.entries, hasLength(2));
    expect(await fixture('collections.json').readAsString(), broken);
    expect(await fixture('collections.json.bak').readAsString(), backup);
    expect(playlistStorageWarning, isNull);
  });

  test(
      'semantically invalid legacy primary also falls back to the complete backup',
      () async {
    final primary = _legacy([
      _collection('partial', '不能部分导入', [_local('A').path]),
      _collection('invalid', '坏在线引用', ['online://']),
    ]);
    final backup = _legacy([
      _collection('backup', '完整备份', [_local('B').path])
    ]);
    await fixture('collections.json').writeAsString(primary);
    await fixture('collections.json.bak').writeAsString(backup);
    await readPlaylists();
    expect(PLAYLISTS.map((p) => p.name), ['完整备份']);
    expect(await fixture('collections.json').readAsString(), primary);
    expect(await fixture('collections.json.bak').readAsString(), backup);
    expect(playlistStorageWarning, isNull);
  });

  final invalidRecords = <String, Object?>{
    'null record': null,
    'non-list paths': {'id': 'bad', 'name': 'bad', 'audioPaths': 'not a list'},
    'non-string path': {
      'id': 'bad',
      'name': 'bad',
      'audioPaths': [12]
    },
    'empty path': {
      'id': 'bad',
      'name': 'bad',
      'audioPaths': ['']
    },
    'invalid online identity': _collection('bad', 'bad', ['online://']),
    'invalid timestamp': {
      ..._collection('bad', 'bad', []),
      'createdAt': 'invalid'
    },
  };
  for (final invalid in invalidRecords.entries) {
    test(
        'invalid ${invalid.key} never commits a partial merge or writes an empty source',
        () async {
      final old = playlistTree.createPlaylist('未损坏的内存歌单');
      await savePlaylists();
      final original = await fixture('playlists.json').readAsString();
      final good = _collection('good', '本次也不能部分写入', [_local('A').path]);
      final damaged = _legacy([good, invalid.value]);
      await fixture('collections.json').writeAsString(damaged);
      await readPlaylists();
      expect(PLAYLISTS, [old]);
      expect(playlistStorageWarning, contains('无法完整读取'));
      expect(playlistsReadBlocked, isTrue);
      expect(playlistsHaveUnsavedChanges, isFalse);
      await expectLater(savePlaylists(), throwsStateError);
      expect(await fixture('playlists.json').readAsString(), original);
      expect(await fixture('collections.json').readAsString(), damaged);
      expect(
          await fixture('playlists.before-collection-merge.json.bak').exists(),
          isFalse);
      await putCollections([good]);
      await readPlaylists();
      expect(PLAYLISTS.map((p) => p.name), ['未损坏的内存歌单', '本次也不能部分写入']);
      expect(playlistStorageWarning, isNull);
      expect(playlistsReadBlocked, isFalse);
    });
  }

  test(
      'unreadable canonical files are not bypassed just because collections are valid',
      () async {
    final memory = playlistTree.createPlaylist('保留当前内存');
    const primary = '{broken canonical';
    const backup = '[not valid json';
    final source = _legacy([
      _collection('source', '源', [_local('A').path])
    ]);
    await fixture('playlists.json').writeAsString(primary);
    await fixture('playlists.json.bak').writeAsString(backup);
    await fixture('collections.json').writeAsString(source);
    await readPlaylists();
    expect(PLAYLISTS, [memory]);
    await expectLater(savePlaylists(), throwsStateError);
    expect(await fixture('playlists.json').readAsString(), primary);
    expect(await fixture('playlists.json.bak').readAsString(), backup);
    expect(await fixture('collections.json').readAsString(), source);
  });

  for (final brokenSource in ['playlists', 'collections']) {
    test(
        '$brokenSource read protection rejects every canonical mutation before changing memory',
        () async {
      final tree = playlistTree;
      final root = tree.createPlaylist('真实根');
      final first = tree.addAudio(root, _local('A'));
      final child = tree.createPlaylist('真实子单', parent: root);
      tree.addAudio(child, _local('B'));
      final last = tree.addAudio(root, _local('C'));
      final second = tree.createPlaylist('第二根');
      await savePlaylists();
      final before = PLAYLISTS.map((playlist) => playlist.toMap()).toList();
      final beforeText = jsonEncode(before);
      const primary = '{broken primary';
      const backup = '[broken backup';
      await fixture('$brokenSource.json').writeAsString(primary);
      await fixture('$brokenSource.json.bak').writeAsString(backup);
      await readPlaylists();
      expect(playlistsReadBlocked, isTrue);
      expect(PLAYLISTS, [root, second]);

      final mutations = <String, void Function()>{
        'create root': () => tree.createPlaylist('拒绝新根'),
        'create child': () => tree.createPlaylist('拒绝子单', parent: root),
        'single add': () => tree.addAudio(root, _local('new')),
        'batch add': () => tree.addAudios(root, [_local('new')]),
        'selection edit': () => tree.setDirectAudios(root, [_local('new')]),
        'cover': () => tree.setImagePath(root, 'D:\\new-cover.jpg'),
        'rename': () => tree.rename(root, '不能改名'),
        'move child': () => tree.moveEntry(
            sourceParent: root, entryId: child.id, targetParent: second),
        'move root': () => tree.moveEntry(
            sourceParent: null, entryId: second.id, targetParent: root),
        'move song': () => tree.moveEntry(
            sourceParent: root, entryId: first.id, targetParent: second),
        'remove child': () => tree.removeEntry(parent: root, entryId: child.id),
        'remove root': () => tree.removeEntry(parent: null, entryId: second.id),
        'batch remove': () =>
            tree.removeEntries(parent: root, entryIds: [first.id, child.id]),
        'reorder': () => tree.reorder(parent: root, oldIndex: 0, newIndex: 3),
        'set root order': () =>
            tree.setOrder(parent: null, entryIds: [second.id, root.id]),
        'set mixed order': () => tree
            .setOrder(parent: root, entryIds: [last.id, child.id, first.id]),
      };
      for (final mutation in mutations.entries) {
        expect(
            mutation.value,
            throwsA(isA<StateError>()
                .having((e) => e.message, 'message', contains('只读'))),
            reason: mutation.key);
        expect(jsonEncode(PLAYLISTS.map((p) => p.toMap()).toList()), beforeText,
            reason: '${mutation.key} must fail before mutation');
        expect(child.parent, same(root));
        expect(playlistsHaveUnsavedChanges, isFalse);
      }
      expect(
          tree.moveError(
              sourceParent: root, entryId: first.id, targetParent: second),
          contains('只读'));
      expect(tree.findPlaylist(child.id), same(child));
      expect(root.flattenAudios().map((a) => a.title), ['A', 'B', 'C']);
      expect(await fixture('$brokenSource.json').readAsString(), primary);
      expect(await fixture('$brokenSource.json.bak').readAsString(), backup);

      // Standalone fixture/import trees are not the canonical list even while
      // the process's real store is blocked. Exercise every mutation family.
      final independent = PlaylistTree([]);
      final localRoot = independent.createPlaylist('独立根');
      final localChild = independent.createPlaylist('独立子单', parent: localRoot);
      final localFirst = independent.addAudio(localRoot, _local('fixture-A'));
      final localAdded =
          independent.addAudios(localRoot, [_local('fixture-B')]).single;
      independent
          .setDirectAudios(localRoot, [localFirst.audio, localAdded.audio]);
      independent.setImagePath(localRoot, 'D:\\fixture-cover.jpg');
      independent.rename(localRoot, '独立树可编辑');
      independent.moveEntry(
          sourceParent: localRoot,
          entryId: localAdded.id,
          targetParent: localChild);
      independent.reorder(parent: localRoot, oldIndex: 0, newIndex: 2);
      independent.setOrder(
          parent: localRoot, entryIds: [localChild.id, localFirst.id]);
      independent.removeEntry(parent: localChild, entryId: localAdded.id);
      independent.removeEntries(parent: localRoot, entryIds: [localFirst.id]);
      expect(localRoot.name, '独立树可编辑');
      expect(localRoot.imagePath, 'D:\\fixture-cover.jpg');
      expect(localRoot.entries.single.childPlaylist, same(localChild));
      expect(jsonEncode(PLAYLISTS.map((p) => p.toMap()).toList()), beforeText);

      if (brokenSource == 'playlists') {
        await fixture('playlists.json').writeAsString(beforeText);
      } else {
        await putCollections([_collection('restored', '修复后迁移', [])]);
      }
      await readPlaylists();
      expect(playlistsReadBlocked, isFalse);
      expect(playlistStorageWarning, isNull);
      final loadedRoot = tree.findPlaylist(root.id)!;
      tree.rename(loadedRoot, '恢复后可编辑');
      final restored = tree.createPlaylist('恢复后新建', parent: loadedRoot);
      tree.addAudio(restored, _local('恢复后歌曲'));
      await savePlaylists();
      expect(loadedRoot.name, '恢复后可编辑');
      expect(restored.audios, hasLength(1));
    });
  }

  test(
      'canonical backup recovery and legacy merge retain the good canonical backup',
      () async {
    final original = Playlist('原有树', {});
    final tree = PlaylistTree([original]);
    final child = tree.createPlaylist('原子单', parent: original);
    tree.addAudio(child, remote);
    final backup = jsonEncode([original.toMap()]);
    await fixture('playlists.json').writeAsString('{broken');
    await fixture('playlists.json.bak').writeAsString(backup);
    await putCollections([_collection('source', '新根', [])]);
    await readPlaylists();
    expect(PLAYLISTS.map((p) => p.name), ['原有树', '新根']);
    expect(PLAYLISTS.first.toMap(), original.toMap());
    expect(await fixture('playlists.json.bak').readAsString(), backup);
    expect(
        await fixture('playlists.before-collection-merge.previous.bak')
            .readAsString(),
        backup);
  });

  test(
      'legacy absence creates no collection file, while a valid empty source gets a durable marker',
      () async {
    await readCollections();
    expect(await fixture('playlists.json').exists(), isFalse);
    expect(await fixture('collections.json').exists(), isFalse);
    final empty = _legacy([]);
    await fixture('collections.json').writeAsString(empty);
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    expect((await savedStore())['legacyCollectionsMigrated'], isTrue);
    expect((await savedStore())['migratedCollectionKeys'], isEmpty);
    expect(await fixture('collections.json').readAsString(), empty);
  });

  test(
      'old and new loaders share one migration and compatibility saves only write canonical data',
      () async {
    await putCollections([
      _collection('source', '原名', [_local('A').path])
    ]);
    final source = await fixture('collections.json').readAsString();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return testRoot.path;
    });
    try {
      final modern = readPlaylists();
      await entered.future.timeout(const Duration(seconds: 5));
      final legacy = readCollections();
      expect(legacy, same(modern));
      release.complete();
      await Future.wait([modern, legacy]);
      expect(PLAYLISTS, hasLength(1));
      expect(await fixture('playlists.json.bak').exists(), isFalse);
      playlistTree.rename(PLAYLISTS.single, '统一改名');
      await saveCollections();
      expect(userCollections.single.name, '统一改名');
      expect(() => userCollections.clear(), throwsUnsupportedError);
      expect(await fixture('collections.json').readAsString(), source);
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
    }
  });

  test(
      'a stale migration read cannot discard a newer edit or prematurely complete its ledger',
      () async {
    final old = playlistTree.createPlaylist('已有');
    await savePlaylists();
    await putCollections([
      _collection('source', '稍后迁移', [_local('A').path])
    ]);
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
      }
      return testRoot.path;
    });
    try {
      final reload = readPlaylists();
      await entered.future.timeout(const Duration(seconds: 5));
      playlistTree.rename(old, '读取期间改名');
      await savePlaylists();
      release.complete();
      await reload;
      expect(PLAYLISTS, [old]);
      expect(old.name, '读取期间改名');
      expect((await savedStore())['legacyCollectionsMigrated'], isFalse);
      expect((await savedStore())['migratedCollectionKeys'], isEmpty);
      await readPlaylists();
      expect(PLAYLISTS.map((p) => p.name), ['读取期间改名', '稍后迁移']);
      expect((await savedStore())['legacyCollectionsMigrated'], isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
    }
  });

  test(
      'failure to preserve pre-migration originals stops before changing canonical files',
      () async {
    final old = playlistTree.createPlaylist('原有');
    await savePlaylists();
    final original = await fixture('playlists.json').readAsString();
    await putCollections([_collection('source', '源', [])]);
    final blocked =
        Directory(fixture('playlists.before-collection-merge.json.bak').path);
    await blocked.create();
    try {
      await readPlaylists();
      expect(PLAYLISTS, [old]);
      expect(await fixture('playlists.json').readAsString(), original);
      await expectLater(savePlaylists(), throwsStateError);
      final leftovers = await dataRoot
          .list()
          .where((file) => file.path.contains('.tmp_'))
          .toList();
      expect(leftovers, isEmpty);
      await blocked.delete();
      await readPlaylists();
      expect(PLAYLISTS.map((p) => p.name), ['原有', '源']);
    } finally {
      if (await blocked.exists()) await blocked.delete();
    }
  });

  test(
      'missing optional old metadata has stable defaults, not new timestamps on each load',
      () async {
    await putCollections([
      {
        'name': '无旧ID和时间',
        'audioPaths': ['online://qq/identity']
      }
    ]);
    await readPlaylists();
    final first = PLAYLISTS.single;
    final before = first.toMap();
    expect(first.createdAt, 0);
    expect(first.modifiedAt, 0);
    expect(first.imagePath, isNull);
    expect(first.legacyCollectionId, isNull);
    await readPlaylists();
    expect(PLAYLISTS.single.toMap(), before);
  });
}
