import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;
  late Directory dataRoot;
  final audio = Audio.online(
    provider: 'qq',
    id: 'song/mid',
    title: '保存测试',
    artist: '测试歌手',
    album: '测试专辑',
    duration: 180,
    mediaId: 'media-identity',
    artworkUrl: 'https://example.com/cover.jpg',
    created: 1700000000,
  );

  setUp(() async {
    final parent =
        await Directory(path.join(Directory.current.path, 'build', 'test-data'))
            .create(recursive: true);
    testRoot = await parent.createTemp('playlist-storage-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => testRoot.path);
    dataRoot = await getAppDataDir();
    // Abort before any fixture write if a future platform plugin bypasses the
    // mock channel; these tests must never touch the real user's library.
    expect(path.isWithin(testRoot.path, dataRoot.path), isTrue);
    AudioLibrary.instance.replaceOnlineAudios([]);
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
  });

  tearDown(() async {
    PLAYLISTS.clear();
    AudioLibrary.instance.replaceOnlineAudios([]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final expectedParent =
        path.join(Directory.current.path, 'build', 'test-data');
    if (path.isWithin(expectedParent, testRoot.path)) {
      await testRoot.delete(recursive: true);
    }
  });

  File fixture(String name) => File(path.join(dataRoot.path, name));

  void restorePathHandler() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => testRoot.path);

  // Each data-root resolution asks for Documents and then ApplicationSupport
  // (the data_location.json pointer). Gate only Documents, once per operation:
  // counting both calls would block/fail the older operation's support lookup
  // instead of the newer read/write this test is meant to control.
  void gateDataDirectoryRequests(Future<void> Function() gate) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        await gate();
      }
      return testRoot.path;
    });
  }

  Playlist createNested() {
    final tree = playlistTree;
    final root = tree.createPlaylist('根');
    final child = tree.createPlaylist('子', parent: root);
    tree.addAudio(child, audio);
    tree.addAudio(root,
        Audio.fromMap({'path': 'D:\\fixture\\local.flac', 'title': '本地'}));
    return root;
  }

  test('trash survives reload and restores nested views and order', () async {
    final root = createNested();
    root.presentation = {
      'columns': ['album'],
      'widths': {'album': 180}
    };
    final snapshot = root.toMap();
    playlistTree.removeEntries(parent: null, entryIds: [root.id]);
    await savePlaylists();
    await readPlaylists();
    expect(PLAYLISTS, isEmpty);
    expect(playlistTrash.single['playlist'], snapshot);
    final restored = restorePlaylistTrash(playlistTrash.single['id'] as String);
    expect(restored.toMap(), snapshot);
    expect(playlistTrash, isEmpty);
    await savePlaylists();
    await readPlaylists();
    expect(PLAYLISTS.single.toMap(), snapshot);
    expect(playlistTrash, isEmpty);
  });

  test('invalid trash date recovers whole backup before the dialog can crash',
      () async {
    final root = createNested();
    playlistTree.removeEntries(parent: null, entryIds: [root.id]);
    await savePlaylists();
    final original = await fixture('playlists.json').readAsString();
    await fixture('playlists.json.bak').writeAsString(original);
    final damaged = jsonDecode(original) as Map;
    damaged['trash'][0]['deletedAt'] = 8640000000000001;
    await fixture('playlists.json').writeAsString(jsonEncode(damaged));
    await readPlaylists();
    expect(playlistsReadBlocked, isFalse);
    expect(playlistTrash.single['deletedAt'],
        (jsonDecode(original) as Map)['trash'][0]['deletedAt']);
    expect(await fixture('playlists.json.bak').readAsString(), original);
  });

  test(
      'legacy load is read-only, then migration preserves the original as backup',
      () async {
    final legacy = jsonEncode([
      {
        'name': '旧歌单',
        'audios': [
          {'kind': 'online', 'path': audio.path, ...audio.toOnlineMap()},
          {'path': 'D:\\fixture\\missing.flac', 'title': '未挂载磁盘上的歌曲'},
        ],
      },
    ]);
    await fixture('playlists.json').writeAsString(legacy);
    await readPlaylists();
    final root = PLAYLISTS.single;
    final ids = root.entries.map((entry) => entry.id).toList();
    expect(root.flattenAudios().map((song) => song.isOnline), [true, false]);
    expect(await fixture('playlists.json').readAsString(), legacy);
    expect(await fixture('playlists.json.bak').exists(), isFalse);

    await savePlaylists();
    expect(await fixture('playlists.json.bak').readAsString(), legacy);
    final saved =
        jsonDecode(await fixture('playlists.json').readAsString()) as Map;
    expect(saved['version'], 4);
    expect(saved['playlists'].single['version'], 3);
    expect(saved['playlists'].single['id'], root.id);
    PLAYLISTS.clear();
    await readPlaylists();
    expect(PLAYLISTS.single.id, root.id);
    expect(PLAYLISTS.single.entries.map((entry) => entry.id), ids);
  });

  test('mixed tree saves and reloads IDs, order and full online descriptions',
      () async {
    final root = createNested();
    final child = root.entries.first.childPlaylist!;
    final tree = playlistTree;
    final grandchild = tree.createPlaylist('更深', parent: child, index: 0);
    tree.addAudio(grandchild, audio);
    final before = root.toMap();
    await savePlaylists();
    PLAYLISTS.clear();
    await readPlaylists();
    expect(PLAYLISTS.single.toMap(), before);
    final restored = PLAYLISTS.single.flattenEntries();
    expect(restored.map((item) => item.audio.title), ['保存测试', '保存测试', '本地']);
    expect(restored.first.audio.onlineId, 'song/mid');
    expect(restored.first.audio.onlineMediaId, 'media-identity');
    expect(restored.first.playlist.pathFromRoot.map((item) => item.name),
        ['根', '子', '更深']);
    expect(await fixture('playlists.json.tmp').exists(), isFalse);
  });

  test(
      'overlapping nested saves capture state before the serialized write queue',
      () async {
    final root = createNested();
    final child = root.entries.first.childPlaylist!;
    final oldIds = root.flattenEntries().map((item) => item.entryId).toList();
    final first = savePlaylists();
    playlistTree.rename(child, '改名后的子歌单');
    playlistTree.reorder(parent: root, oldIndex: 0, newIndex: 2);
    final second = savePlaylists();
    await Future.wait([first, second]);
    final primary = decodePlaylists(
            jsonDecode(await fixture('playlists.json').readAsString()))
        .single;
    final backup = decodePlaylists(
            jsonDecode(await fixture('playlists.json.bak').readAsString()))
        .single;
    expect(backup.entries.first.childPlaylist!.name, '子');
    expect(primary.entries.last.childPlaylist!.name, '改名后的子歌单');
    expect(backup.flattenEntries().map((item) => item.entryId), oldIds);
    expect(
        primary.flattenEntries().map((item) => item.entryId), oldIds.reversed);
  });

  test(
      'semantic corruption falls back to the whole good tree without rotating it away',
      () async {
    final root = createNested();
    final valid = jsonEncode([root.toMap()]);
    final corrupt = jsonEncode([root.toMap(), root.toMap()]);
    await fixture('playlists.json').writeAsString(corrupt);
    await fixture('playlists.json.bak').writeAsString(valid);
    PLAYLISTS.clear();
    await readPlaylists();
    expect(PLAYLISTS.single.flattenAudios(), hasLength(2));
    expect(PLAYLISTS.single.id, root.id);
    await savePlaylists();
    expect(await fixture('playlists.json.bak').readAsString(), valid);
    expect(
        decodePlaylists(
            jsonDecode(await fixture('playlists.json').readAsString())),
        hasLength(1));
    expect(await fixture('playlists.json.tmp').exists(), isFalse);
  });

  test(
      'a malformed root is not silently skipped while accepting the remaining forest',
      () async {
    final root = createNested();
    final backup = jsonEncode([root.toMap()]);
    final damaged = jsonEncode([root.toMap(), null]);
    await fixture('playlists.json').writeAsString(damaged);
    await fixture('playlists.json.bak').writeAsString(backup);
    PLAYLISTS.clear();
    await readPlaylists();
    await savePlaylists();
    expect(await fixture('playlists.json.bak').readAsString(), backup);
    expect(PLAYLISTS.single.entries.first.childPlaylist!.name, '子');
  });

  test('invalid in-memory forest fails before changing the primary or backup',
      () async {
    final root = createNested();
    await savePlaylists();
    final primary = await fixture('playlists.json').readAsString();
    PLAYLISTS.add(root);
    await expectLater(savePlaylists(), throwsFormatException);
    expect(await fixture('playlists.json').readAsString(), primary);
    expect(await fixture('playlists.json.bak').exists(), isFalse);
    expect(await fixture('playlists.json.tmp').exists(), isFalse);
    PLAYLISTS.removeLast();
  });

  test(
      'write failures are observable, preserve existing files and do not poison later saves',
      () async {
    final root = createNested();
    await savePlaylists();
    root.name = '第二次';
    await savePlaylists();
    final primary = await fixture('playlists.json').readAsString();
    final backup = await fixture('playlists.json.bak').readAsString();
    // A directory where the temporary file should be makes this independent of
    // platform-specific chmod/read-only attribute behavior.
    final blockedTemporary = Directory(fixture('playlists.json.tmp').path);
    await blockedTemporary.create();
    root.name = '仍在内存，写入失败';
    await expectLater(savePlaylists(), throwsA(isA<FileSystemException>()));
    expect(await fixture('playlists.json').readAsString(), primary);
    expect(await fixture('playlists.json.bak').readAsString(), backup);
    expect(root.name, '仍在内存，写入失败');

    expect(path.isWithin(testRoot.path, blockedTemporary.path), isTrue);
    await blockedTemporary.delete();
    root.name = '重试成功';
    await savePlaylists();
    expect(
        decodePlaylists(
                jsonDecode(await fixture('playlists.json').readAsString()))
            .single
            .name,
        '重试成功');
    expect(await fixture('playlists.json.bak').readAsString(), primary);
  });

  test(
      'an unreadable primary and backup cannot be overwritten by an empty autosave',
      () async {
    final root = createNested();
    final valid = jsonEncode([root.toMap()]);
    const damagedPrimary = '{not-json';
    const damagedBackup = '[{"name":"missing mandatory fields"}]';
    await fixture('playlists.json').writeAsString(damagedPrimary);
    await fixture('playlists.json.bak').writeAsString(damagedBackup);
    await readPlaylists();
    expect(PLAYLISTS.single, same(root));
    await expectLater(savePlaylists(), throwsStateError);
    expect(await fixture('playlists.json').readAsString(), damagedPrimary);
    expect(await fixture('playlists.json.bak').readAsString(), damagedBackup);
    expect(await fixture('playlists.json.tmp').exists(), isFalse);

    await fixture('playlists.json').writeAsString(valid);
    await readPlaylists();
    await savePlaylists();
    expect(PLAYLISTS.single.id, root.id);
    expect(await fixture('playlists.json.bak').readAsString(), valid);
  });

  test(
      'failed save then reload preserves new subtrees and cross-parent moves until retry',
      () async {
    final root = createNested();
    final child = root.entries.first.childPlaylist!;
    await savePlaylists();
    final originalDisk = await fixture('playlists.json').readAsString();
    final second = playlistTree.createPlaylist('新根');
    playlistTree.moveEntry(
        sourceParent: root, entryId: child.id, targetParent: second);
    final added = playlistTree.createPlaylist('尚未保存的子树', parent: child);
    playlistTree.addAudio(added, audio);
    final pending = PLAYLISTS.map((item) => item.toMap()).toList();
    final blockedTemporary = Directory(fixture('playlists.json.tmp').path);
    await blockedTemporary.create();
    try {
      await expectLater(savePlaylists(), throwsA(isA<FileSystemException>()));
      await readPlaylists();
      expect(PLAYLISTS, [root, second]);
      expect(child.parent, same(second));
      expect(playlistTree.findPlaylist(added.id), same(added));
      expect(PLAYLISTS.map((item) => item.toMap()), pending);
      expect(await fixture('playlists.json').readAsString(), originalDisk);

      expect(path.isWithin(testRoot.path, blockedTemporary.path), isTrue);
      await blockedTemporary.delete();
      await savePlaylists();
      await readPlaylists();
      expect(PLAYLISTS.map((item) => item.toMap()), pending);
      expect(PLAYLISTS.first, isNot(same(root)));
      expect(playlistTree.findPlaylist(added.id)!.parent!.id, child.id);
    } finally {
      if (await blockedTemporary.exists()) await blockedTemporary.delete();
      await savePlaylists();
    }
  });

  test(
      'a failed first-ever save cannot let a missing-file reload clear the new tree',
      () async {
    final root = createNested();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel,
            (_) async => throw PlatformException(code: 'write-denied'));
    try {
      await expectLater(savePlaylists(), throwsA(isA<PlatformException>()));
      restorePathHandler();
      expect(await fixture('playlists.json').exists(), isFalse);
      await readPlaylists();
      expect(PLAYLISTS.single, same(root));
      expect(root.entries.first.childPlaylist!.audios.values.single.path,
          audio.path);
      await savePlaylists();
      await readPlaylists();
      expect(PLAYLISTS.single.id, root.id);
      expect(PLAYLISTS.single, isNot(same(root)));
    } finally {
      restorePathHandler();
      await savePlaylists();
    }
  });

  test(
      'an older successful save never clears the dirty state of a newer failed save',
      () async {
    final root = createNested();
    await savePlaylists();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    gateDataDirectoryRequests(() async {
      final call = ++calls;
      if (call == 1) {
        entered.complete();
        await release.future;
      } else if (call == 2) {
        throw PlatformException(code: 'newest-write-denied');
      }
    });
    try {
      root.name = '较早快照';
      final older = savePlaylists();
      await entered.future.timeout(const Duration(seconds: 5));
      root.name = '最新但失败';
      final newer = savePlaylists();
      final newerFailure =
          expectLater(newer, throwsA(isA<PlatformException>()));
      release.complete();
      await older;
      await newerFailure;
      expect(calls, 2);
      restorePathHandler();
      expect(
          decodePlaylists(
                  jsonDecode(await fixture('playlists.json').readAsString()))
              .single
              .name,
          '较早快照');
      await readPlaylists();
      expect(PLAYLISTS.single, same(root));
      expect(root.name, '最新但失败');
      await savePlaylists();
      await readPlaylists();
      expect(PLAYLISTS.single.name, '最新但失败');
      expect(PLAYLISTS.single, isNot(same(root)));
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
      await savePlaylists();
    }
  });

  test('an older failed save cannot keep a newer successful generation dirty',
      () async {
    final root = createNested();
    await savePlaylists();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    gateDataDirectoryRequests(() async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
        throw PlatformException(code: 'older-write-denied');
      }
    });
    try {
      root.name = '旧失败';
      final older = savePlaylists();
      final olderFailure =
          expectLater(older, throwsA(isA<PlatformException>()));
      await entered.future.timeout(const Duration(seconds: 5));
      root.name = '新成功';
      final newer = savePlaylists();
      release.complete();
      await olderFailure;
      await newer;
      restorePathHandler();
      await readPlaylists();
      expect(PLAYLISTS.single.name, '新成功');
      expect(PLAYLISTS.single, isNot(same(root)));
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
      await savePlaylists();
    }
  });

  test(
      'a read already in flight cannot apply an old file after a newer write fails',
      () async {
    final root = createNested();
    await savePlaylists();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    gateDataDirectoryRequests(() async {
      final call = ++calls;
      if (call == 1) {
        entered.complete();
        await release.future;
      } else if (call == 2) {
        throw PlatformException(code: 'concurrent-save-denied');
      }
    });
    try {
      final reload = readPlaylists();
      await entered.future.timeout(const Duration(seconds: 5));
      final added = playlistTree.createPlaylist('读取期间新增', parent: root);
      await expectLater(savePlaylists(), throwsA(isA<PlatformException>()));
      release.complete();
      await reload;
      expect(PLAYLISTS.single, same(root));
      expect(playlistTree.findPlaylist(added.id), same(added));
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
      await savePlaylists();
    }
  });

  test('reload waits for a newer save added while an earlier write is pending',
      () async {
    final root = createNested();
    await savePlaylists();
    final enteredOlder = Completer<void>();
    final enteredNewer = Completer<void>();
    final releaseOlder = Completer<void>();
    final releaseNewer = Completer<void>();
    var calls = 0;
    gateDataDirectoryRequests(() async {
      final call = ++calls;
      if (call == 1) {
        enteredOlder.complete();
        await releaseOlder.future;
      } else if (call == 2) {
        enteredNewer.complete();
        await releaseNewer.future;
      }
    });
    try {
      root.name = '旧的';
      final older = savePlaylists();
      await enteredOlder.future.timeout(const Duration(seconds: 5));
      var reloadSettled = false;
      final reload = readPlaylists().then((_) => reloadSettled = true);
      root.name = '最新的';
      final newer = savePlaylists();
      releaseOlder.complete();
      await older;
      await enteredNewer.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(reloadSettled, isFalse);
      releaseNewer.complete();
      await newer;
      await reload;
      expect(PLAYLISTS.single.name, '最新的');
      expect(PLAYLISTS.single, isNot(same(root)));
    } finally {
      if (!releaseOlder.isCompleted) releaseOlder.complete();
      if (!releaseNewer.isCompleted) releaseNewer.complete();
      restorePathHandler();
      await savePlaylists();
    }
  });

  test(
      'skipping a dirty reload retains a recovered backup until the retry succeeds',
      () async {
    final root = createNested();
    final backup = jsonEncode([root.toMap()]);
    await fixture('playlists.json').writeAsString('{broken');
    await fixture('playlists.json.bak').writeAsString(backup);
    await readPlaylists();
    final recovered = PLAYLISTS.single;
    playlistTree.createPlaylist('恢复后新增', parent: recovered);
    final blockedTemporary = Directory(fixture('playlists.json.tmp').path);
    await blockedTemporary.create();
    try {
      await expectLater(savePlaylists(), throwsA(isA<FileSystemException>()));
      await readPlaylists();
      expect(PLAYLISTS.single, same(recovered));
      expect(recovered.entries.last.childPlaylist!.name, '恢复后新增');
      expect(path.isWithin(testRoot.path, blockedTemporary.path), isTrue);
      await blockedTemporary.delete();
      await savePlaylists();
      expect(await fixture('playlists.json.bak').readAsString(), backup);
      await readPlaylists();
      expect(PLAYLISTS.single.entries.last.childPlaylist!.name, '恢复后新增');
    } finally {
      if (await blockedTemporary.exists()) await blockedTemporary.delete();
      await savePlaylists();
    }
  });

  test('a stale read failure cannot block retry after a newer save succeeded',
      () async {
    final root = createNested();
    await savePlaylists();
    final entered = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    gateDataDirectoryRequests(() async {
      if (++calls == 1) {
        entered.complete();
        await release.future;
        throw PlatformException(code: 'stale-read-failed');
      }
    });
    try {
      final reload = readPlaylists();
      await entered.future.timeout(const Duration(seconds: 5));
      final added = playlistTree.createPlaylist('旧读取开始后的新修改', parent: root);
      await savePlaylists();
      release.complete();
      await reload;
      expect(PLAYLISTS.single, same(root));
      expect(playlistTree.findPlaylist(added.id), same(added));
      // A stale catch must not set the corrupt-file read guard and prevent a
      // perfectly valid retry/new write after that later generation succeeded.
      await savePlaylists();
      await readPlaylists();
      expect(PLAYLISTS.single.entries.last.childPlaylist!.id, added.id);
    } finally {
      if (!release.isCompleted) release.complete();
      restorePathHandler();
      await savePlaylists();
    }
  });
}
