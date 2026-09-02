import 'dart:convert';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

Audio _song(String name) => Audio.fromMap({
      'path': 'D:\\fixture-music\\$name.flac',
      'title': name,
      'artist': '测试歌手',
      'album': '测试专辑',
      'duration': 180,
      'language': 'zho',
      'created': 1700000000,
    });

class _Example {
  final PlaylistTree tree = PlaylistTree([]);
  late final Playlist root = tree.createPlaylist('根歌单');
  late final PlaylistAudioEntry a = tree.addAudio(root, _song('A'));
  late final Playlist b = tree.createPlaylist('B', parent: root);
  late final PlaylistAudioEntry c = tree.addAudio(b, _song('C'));
  late final Playlist d = tree.createPlaylist('D', parent: b);
  late final PlaylistAudioEntry e = tree.addAudio(d, _song('E'));
  late final PlaylistAudioEntry f = tree.addAudio(root, _song('F'));

  _Example() {
    // Evaluate in mixed-entry order, not the order of later test access.
    a;
    b;
    c;
    d;
    e;
    f;
  }
}

String _snapshot(PlaylistTree tree) =>
    jsonEncode(tree.roots.map((playlist) => playlist.toMap()).toList());

Map<String, Object?> _node(String id, {List<Object?> entries = const []}) => {
      'version': 2,
      'id': id,
      'name': id,
      'entries': entries,
    };

Map<String, Object?> _child(Map<String, Object?> node) => {
      'type': 'playlist',
      'id': node['id'],
      'playlist': node,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PLAYLISTS.clear();
    AudioLibrary.instance.replaceOnlineAudios([]);
  });

  tearDown(() {
    PLAYLISTS.clear();
    AudioLibrary.instance.replaceOnlineAudios([]);
  });

  test('mixed entries flatten depth first and return to each parent remainder',
      () {
    final example = _Example();
    expect(example.root.entries.map((entry) => entry.id),
        [example.a.id, example.b.id, example.f.id]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['A', 'C', 'E', 'F']);
    expect(example.b.flattenAudios().map((audio) => audio.title), ['C', 'E']);
    expect(example.d.flattenAudios().map((audio) => audio.title), ['E']);
    expect(example.root.flattenedIndexOf(example.e.id), 2);
    expect(example.root.flattenedIndexOf('missing'), -1);
    expect(example.root.flattenedIndexOf(example.b.id), -1);
  });

  test('empty subtrees do not create fake songs or lose following siblings',
      () {
    final example = _Example();
    example.tree.createPlaylist('空子单', parent: example.b, index: 0);
    example.tree.createPlaylist('空末尾', parent: example.root);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['A', 'C', 'E', 'F']);
  });

  test('first cover song follows depth-first order without flattening', () {
    final tree = PlaylistTree([]);
    final root = tree.createPlaylist('Root');
    final empty = tree.createPlaylist('Empty', parent: root);
    tree.createPlaylist('Still empty', parent: empty);
    final nested = tree.createPlaylist('Nested', parent: root);
    final expected = tree.addAudio(nested, _song('First nested')).audio;
    tree.addAudio(root, _song('Later direct'));

    expect(root.firstAudioOrNull, same(expected));
    expect(empty.firstAudioOrNull, isNull);
    expect(nested.firstAudioOrNull, same(expected));
  });

  test('same audio in different branches has independent occurrence indices',
      () {
    final example = _Example();
    final duplicate = example.tree.addAudio(example.d, example.a.audio);
    final all = example.root.flattenEntries();
    expect(all.map((entry) => entry.audio.title), ['A', 'C', 'E', 'A', 'F']);
    expect(duplicate.id, isNot(example.a.id));
    expect(example.root.flattenedIndexOf(duplicate.id), 3);
    expect(all[3].playlist, same(example.d));
    expect(all[0].playlist, same(example.root));
  });

  test('same-parent additions deduplicate without moving the original song',
      () {
    final example = _Example();
    final before = _snapshot(example.tree);
    expect(example.tree.addAudio(example.root, _song('A'), index: 2),
        same(example.a));
    expect(_snapshot(example.tree), before);
  });

  test('allPlaylists and breadcrumbs reflect tree order and parent identities',
      () {
    final example = _Example();
    expect(example.tree.allPlaylists, [example.root, example.b, example.d]);
    expect(example.d.parent, same(example.b));
    expect(example.d.root, same(example.root));
    expect(example.d.pathFromRoot, [example.root, example.b, example.d]);
    expect(example.tree.findPlaylist(example.d.id), same(example.d));
    expect(example.tree.findPlaylist('missing'), isNull);
  });

  test('public entries cannot bypass tree validation by mutating the list', () {
    final example = _Example();
    expect(() => example.root.entries.clear(), throwsUnsupportedError);
    expect(() => example.root.entries.add(example.a), throwsUnsupportedError);
    final queue = example.root.flattenEntries()..clear();
    expect(queue, isEmpty);
    expect(example.root.flattenAudios(), hasLength(4));
  });

  test('v3 round trip retains IDs, interleaving, parents and descriptors', () {
    final example = _Example();
    final remote = Audio.online(
      provider: 'qq',
      id: 'song/mid',
      title: '远程',
      artist: '歌手',
      album: '专辑',
      duration: 240,
      mediaId: 'media',
      numericId: 42,
      artworkUrl: 'https://example.com/art.jpg',
      created: 1700000123,
    );
    final entry = example.tree.addAudio(example.d, remote, index: 0);
    final restored =
        Playlist.fromMap(jsonDecode(jsonEncode(example.root.toMap())));
    expect(restored.toMap(), example.root.toMap());
    expect(restored.flattenedIndexOf(entry.id), 2);
    final found = restored.flattenEntries()[2];
    expect(found.audio.isOnline, isTrue);
    expect(found.audio.onlineId, 'song/mid');
    expect(found.audio.onlineMediaId, 'media');
    expect(found.audio.onlineNumericId, 42);
    expect(found.audio.artworkUrl, 'https://example.com/art.jpg');
    expect(found.playlist.pathFromRoot.map((item) => item.id),
        [example.root.id, example.b.id, example.d.id]);
  });

  test('legacy local and online songs migrate without requiring total library',
      () {
    final migrated = Playlist.fromMap({
      'name': '旧歌单',
      'audios': [
        _song('A').toMap(),
        {'path': 'online://qq/song%2Fmid', 'title': '旧联网', 'duration': 90},
      ],
    });
    expect(migrated.name, '旧歌单');
    expect(migrated.audios.values.first.isLocal, isTrue);
    expect(migrated.audios.values.first.language, 'zho');
    expect(migrated.audios.values.last.isOnline, isTrue);
    expect(migrated.audios.values.last.onlineId, 'song/mid');
    final again = Playlist.fromMap(migrated.toMap());
    expect(again.id, migrated.id);
    expect(again.entries.map((item) => item.id),
        migrated.entries.map((item) => item.id));
  });

  test('legacy duplicate paths keep last descriptor and first insertion order',
      () {
    final first = _song('A');
    final replacement = _song('A')..title = '更新的 A';
    final migrated = Playlist.fromMap({
      'name': '旧歌单',
      'audios': [first.toMap(), null, _song('B').toMap(), replacement.toMap()],
    });
    expect(
        migrated.flattenAudios().map((audio) => audio.title), ['更新的 A', 'B']);
    expect(migrated.entries, hasLength(2));
  });

  test(
      'online library references are reused but fake-local online paths are not',
      () {
    final remote = Audio.online(
        provider: 'netease',
        id: '123',
        title: '网络',
        artist: '歌手',
        album: '专辑',
        duration: 10,
        created: 1700000000);
    final saved = Playlist('保存的', {remote.path: remote}).toMap();
    AudioLibrary.instance.replaceOnlineAudios([remote]);
    expect(Playlist.fromMap(saved).audios.values.single, same(remote));
    final fake = Audio.fromMap({'path': remote.path, 'title': '错误的本地缓存'});
    AudioLibrary.instance.replaceOnlineAudios([fake]);
    final restored = Playlist.fromMap(saved).audios.values.single;
    expect(restored.isOnline, isTrue);
    expect(restored.title, '网络');
  });

  test('legacy audios remains a writable direct-song view, not a detached map',
      () {
    final example = _Example();
    final view = example.root.audios;
    expect(view.keys, [example.a.audio.path, example.f.audio.path]);
    final replacement = _song('A')..title = '编辑后 A';
    view[replacement.path] = replacement;
    expect(example.root.entries.first.id, example.a.id);
    expect(example.a.audio, same(replacement));
    final added = _song('新增');
    view[added.path] = added;
    expect(example.root.entries.last.audio, same(added));
    expect(view.remove(example.f.audio.path), same(example.f.audio));
    expect(view.remove('missing'), isNull);
    view.clear();
    expect(example.root.entries.single.childPlaylist, same(example.b));
    expect(
        example.root.flattenAudios().map((audio) => audio.title), ['C', 'E']);
  });

  test(
      'legacy map replacement retains mixed children and surviving occurrence IDs',
      () {
    final example = _Example();
    final replacement = _song('F')..title = '更新的 F';
    final added = _song('G');
    example.root.audios = {replacement.path: replacement, added.path: added};
    expect(
        example.root.entries
            .map((entry) => entry.childPlaylist?.name ?? entry.audio!.title),
        ['B', '更新的 F', 'G']);
    expect(example.root.entries[1].id, example.f.id);
    expect(example.b.parent, same(example.root));
    final before = _snapshot(example.tree);
    example.root.audios = example.root.audios;
    expect(_snapshot(example.tree), before);
  });

  test('invalid legacy map writes fail without partially replacing entries',
      () {
    final example = _Example();
    final before = _snapshot(example.tree);
    expect(
        () => example.root.audios = {'wrong': _song('G')}, throwsArgumentError);
    expect(
        () => example.root.audios['wrong'] = _song('G'), throwsArgumentError);
    expect(_snapshot(example.tree), before);
  });

  test(
      'metadata updates every branch after in-place rename without losing children',
      () {
    final example = _Example();
    PLAYLISTS.add(example.root);
    final nested = example.tree.addAudio(example.d, example.a.audio);
    final rootOrder = example.root.entries.map((entry) => entry.id).toList();
    final nestedOrder = example.d.entries.map((entry) => entry.id).toList();
    final oldPath = example.a.audio.path;
    const newPath = 'D:\\fixture-music\\renamed.flac';
    example.a.audio.applyEditedMetadata(
        newPath: newPath,
        newTitle: '改名',
        newArtist: '新歌手',
        newAlbum: '新专辑',
        newModified: 100);
    expect(example.root.audios.containsKey(oldPath), isTrue);
    expect(replaceAudioInPlaylists(oldPath, newPath, example.a.audio), isTrue);
    expect(example.root.audios.containsKey(oldPath), isFalse);
    expect(example.root.audios[newPath], same(example.a.audio));
    expect(example.d.audios[newPath], same(example.a.audio));
    expect(example.root.entries.map((entry) => entry.id), rootOrder);
    expect(example.d.entries.map((entry) => entry.id), nestedOrder);
    expect(example.root.flattenedIndexOf(nested.id), 3);
    expect(replaceAudioInPlaylists('missing', 'missing', _song('unknown')),
        isFalse);
  });

  test('metadata path collision retains both user-selected occurrences', () {
    final example = _Example();
    final oldPath = example.a.audio.path;
    final replacement = _song('F')..title = 'edited';
    expect(example.root.replaceAudio(oldPath, replacement), isTrue);
    expect(example.root.entries.map((entry) => entry.id),
        [example.a.id, example.b.id, example.f.id]);
    expect(example.root.audios.values.single, same(replacement));
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['edited', 'C', 'E', 'F']);
    example.tree.validate();
  });

  test('reorder follows Flutter old-list insertion indices for mixed entries',
      () {
    final example = _Example();
    example.tree.reorder(parent: example.root, oldIndex: 0, newIndex: 3);
    expect(example.root.entries.map((entry) => entry.id),
        [example.b.id, example.f.id, example.a.id]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['C', 'E', 'F', 'A']);
    example.tree.reorder(parent: example.root, oldIndex: 2, newIndex: 0);
    expect(example.root.entries.map((entry) => entry.id),
        [example.a.id, example.b.id, example.f.id]);
  });

  test('root reorder preserves root and subtree identities', () {
    final example = _Example();
    final second = example.tree.createPlaylist('第二个');
    example.tree.reorder(parent: null, oldIndex: 0, newIndex: 2);
    expect(example.tree.roots, [second, example.root]);
    expect(example.d.pathFromRoot, [example.root, example.b, example.d]);
  });

  test('same-parent move index is final index, while null appends', () {
    final example = _Example();
    example.tree.moveEntry(
        sourceParent: example.root,
        entryId: example.a.id,
        targetParent: example.root,
        index: 2);
    expect(example.root.entries.map((entry) => entry.id),
        [example.b.id, example.f.id, example.a.id]);
    example.tree.moveEntry(
        sourceParent: example.root,
        entryId: example.b.id,
        targetParent: example.root);
    expect(example.root.entries.map((entry) => entry.id),
        [example.f.id, example.a.id, example.b.id]);
  });

  test('reparenting a subtree and returning it to roots preserves every ID',
      () {
    final example = _Example();
    final second = example.tree.createPlaylist('第二个');
    final childIds =
        example.b.flattenEntries().map((entry) => entry.entryId).toList();
    example.tree.moveEntry(
        sourceParent: example.root,
        entryId: example.b.id,
        targetParent: second,
        index: 0);
    expect(example.b.parent, same(second));
    expect(example.d.pathFromRoot, [second, example.b, example.d]);
    expect(
        example.root.flattenAudios().map((audio) => audio.title), ['A', 'F']);
    expect(second.entries.single.id, example.b.id);
    example.tree.moveEntry(
        sourceParent: second,
        entryId: example.b.id,
        targetParent: null,
        index: 1);
    expect(example.tree.roots, [example.root, example.b, second]);
    expect(example.b.parent, isNull);
    expect(example.d.root, same(example.b));
    expect(example.b.flattenEntries().map((entry) => entry.entryId), childIds);
  });

  test('a root can move into another playlist without gaining another parent',
      () {
    final example = _Example();
    final second = example.tree.createPlaylist('第二个');
    example.tree.moveEntry(
        sourceParent: null, entryId: second.id, targetParent: example.d);
    expect(example.tree.roots, [example.root]);
    expect(second.parent, same(example.d));
    expect(second.pathFromRoot, [example.root, example.b, example.d, second]);
  });

  test('moving a song between parents preserves its occurrence ID', () {
    final example = _Example();
    example.tree.moveEntry(
        sourceParent: example.root,
        entryId: example.a.id,
        targetParent: example.b,
        index: 1);
    expect(example.b.entries.map((entry) => entry.id),
        [example.c.id, example.a.id, example.d.id]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['C', 'A', 'E', 'F']);
  });

  for (final target in ['self', 'descendant', 'root-self']) {
    test('invalid $target containment is rejected before any mutation', () {
      final example = _Example();
      final before = _snapshot(example.tree);
      final source = target == 'root-self' ? example.root : example.b;
      final destination = target == 'descendant' ? example.d : source;
      final error = example.tree.moveError(
          sourceParent: source.parent,
          entryId: source.id,
          targetParent: destination);
      expect(error, contains('不能'));
      expect(
          () => example.tree.moveEntry(
              sourceParent: source.parent,
              entryId: source.id,
              targetParent: destination),
          throwsArgumentError);
      expect(_snapshot(example.tree), before);
    });
  }

  test('duplicate target songs and loose root songs are rejected atomically',
      () {
    final example = _Example();
    example.tree.addAudio(example.b, example.a.audio);
    final before = _snapshot(example.tree);
    expect(
        example.tree.moveError(
            sourceParent: example.root,
            entryId: example.a.id,
            targetParent: example.b),
        contains('已包含'));
    expect(
        example.tree.moveError(
            sourceParent: example.root,
            entryId: example.a.id,
            targetParent: null),
        contains('内部'));
    expect(
        () => example.tree.moveEntry(
            sourceParent: example.root,
            entryId: example.a.id,
            targetParent: null),
        throwsArgumentError);
    expect(_snapshot(example.tree), before);
  });

  test(
      'stale source/target and invalid insertion positions do not remove songs',
      () {
    final example = _Example();
    final detached = Playlist('不属于这棵树', {});
    final before = _snapshot(example.tree);
    expect(
        example.tree.moveError(
            sourceParent: example.root,
            entryId: example.a.id,
            targetParent: detached),
        isNotNull);
    expect(
        example.tree.moveError(
            sourceParent: example.b,
            entryId: example.a.id,
            targetParent: example.root),
        isNotNull);
    for (final index in [-1, 3, 100]) {
      expect(
          () => example.tree.moveEntry(
              sourceParent: example.root,
              entryId: example.a.id,
              targetParent: example.root,
              index: index),
          throwsArgumentError);
    }
    expect(
        () => example.tree
            .reorder(parent: example.root, oldIndex: 3, newIndex: 0),
        throwsArgumentError);
    expect(
        () => example.tree.addAudio(detached, _song('G')), throwsArgumentError);
    expect(_snapshot(example.tree), before);
  });

  test('failed insertion into an immutable roots list restores the source link',
      () {
    final example = _Example();
    final immutableTree = PlaylistTree(List.unmodifiable(example.tree.roots));
    final before = _snapshot(example.tree);
    expect(
        () => immutableTree.moveEntry(
            sourceParent: example.root,
            entryId: example.b.id,
            targetParent: null),
        throwsUnsupportedError);
    expect(_snapshot(example.tree), before);
    expect(example.b.parent, same(example.root));
  });

  test('remove detaches only one relationship and retains the full subtree',
      () {
    final example = _Example();
    example.tree.removeEntry(parent: example.root, entryId: example.b.id);
    expect(example.tree.allPlaylists, [example.root]);
    expect(example.b.parent, isNull);
    expect(example.d.parent, same(example.b));
    expect(example.b.flattenAudios().map((audio) => audio.title), ['C', 'E']);
    expect(
        example.root.flattenAudios().map((audio) => audio.title), ['A', 'F']);
    example.tree.removeEntry(parent: example.root, entryId: example.a.id);
    expect(example.a.audio.title, 'A');
    expect(example.root.audios.values.single.title, 'F');
    example.tree.removeEntry(parent: null, entryId: example.root.id);
    expect(example.tree.roots, isEmpty);
    expect(example.root.audios.values.single.title, 'F');
  });

  test('names are trimmed without changing IDs or mixed ordering', () {
    final example = _Example();
    final ids = example.root.entries.map((entry) => entry.id).toList();
    example.tree.rename(example.b, '  新名字  ');
    expect(example.b.name, '新名字');
    expect(example.root.entries.map((entry) => entry.id), ids);
    expect(() => example.tree.rename(example.b, '  '), throwsArgumentError);
    expect(() => example.tree.createPlaylist('  '), throwsArgumentError);
    expect(example.b.name, '新名字');
  });

  test(
      'cover metadata persists and real changes update ancestors, never creation time',
      () {
    final example = _Example();
    final createdAt = example.b.createdAt;
    example.root.modifiedAt = 1;
    example.b.modifiedAt = 2;
    example.d.modifiedAt = 3;
    example.tree.setImagePath(example.b, 'Q:\\离线封面\\保留.png');
    expect(example.b.imagePath, 'Q:\\离线封面\\保留.png');
    expect(example.b.createdAt, createdAt);
    expect(example.b.modifiedAt, greaterThan(2));
    expect(example.root.modifiedAt, example.b.modifiedAt);
    expect(example.d.modifiedAt, 3);
    final snapshot = example.root.toMap();
    example.tree.setImagePath(example.b, example.b.imagePath);
    expect(example.root.toMap(), snapshot);
    expect(Playlist.fromMap(snapshot).toMap(), snapshot);
    example.tree.setImagePath(example.b, null);
    expect(example.b.imagePath, isNull);
    final withImage =
        example.tree.createPlaylist('新歌单', imagePath: 'D:\\cover.jpg');
    expect(withImage.imagePath, 'D:\\cover.jpg');
    expect(withImage.createdAt, greaterThan(0));
    expect(withImage.modifiedAt, withImage.createdAt);
  });

  test(
      'malformed v3 migration ledger and optional metadata are not silently discarded',
      () {
    final node = Playlist('原歌单', {}).toMap();
    final values = [
      {
        'version': 3,
        'playlists': [node],
        'migratedCollectionKeys': 'bad'
      },
      {
        'version': 3,
        'playlists': [node],
        'migratedCollectionKeys': ['duplicate', 'duplicate']
      },
      {
        'version': 3,
        'playlists': [node],
        'legacyCollectionsMigrated': 'true'
      },
      [
        {...node, 'imagePath': 123}
      ],
      [
        {...node, 'modifiedAt': 'bad'}
      ],
      [
        {...node, 'legacyCollectionKey': ''}
      ],
    ];
    for (final value in values) {
      expect(() => decodePlaylists(value), throwsFormatException);
    }
  });

  test(
      'depth 32 is valid while creation or subtree movement beyond it is refused',
      () {
    final tree = PlaylistTree([]);
    final root = tree.createPlaylist('1');
    var leaf = root;
    final chain = [root];
    for (var depth = 2; depth <= PlaylistTree.maxDepth; depth++) {
      leaf = tree.createPlaylist('$depth', parent: leaf);
      chain.add(leaf);
    }
    expect(leaf.pathFromRoot, hasLength(32));
    expect(() => tree.createPlaylist('too deep', parent: leaf),
        throwsArgumentError);
    final subtree = tree.createPlaylist('extra');
    tree.createPlaylist('extra child', parent: subtree);
    final before = _snapshot(tree);
    expect(
        tree.moveError(
            sourceParent: null, entryId: subtree.id, targetParent: chain[30]),
        contains('32'));
    expect(_snapshot(tree), before);
    tree.moveEntry(
        sourceParent: null, entryId: subtree.id, targetParent: chain[29]);
    expect(subtree.entries.single.childPlaylist!.pathFromRoot, hasLength(32));
    expect(Playlist.fromMap(root.toMap()).toMap(), root.toMap());
  });

  test('duplicate root objects and root-plus-child links are rejected', () {
    final example = _Example();
    expect(() => PlaylistTree([example.root, example.root]),
        throwsFormatException);
    expect(
        () => PlaylistTree([example.root, example.b]), throwsFormatException);
    final clone = Playlist.fromMap(example.root.toMap());
    expect(() => PlaylistTree([example.root, clone]), throwsFormatException);
  });

  test(
      'duplicate IDs across separately decoded roots are rejected as one forest',
      () {
    final example = _Example();
    final original = example.root.toMap();
    expect(() => decodePlaylists([original, jsonDecode(jsonEncode(original))]),
        throwsFormatException);
    final other = _node('another', entries: [
      {'type': 'audio', 'id': example.e.id, 'audio': _song('other').toMap()},
    ]);
    expect(() => decodePlaylists([original, other]), throwsFormatException);
  });

  test(
      'malformed child links, unknown kinds and duplicate direct paths are rejected',
      () {
    final malformed = [
      _node('root', entries: [
        {'type': 'playlist', 'id': 'wrong', 'playlist': _node('child')}
      ]),
      _node('root', entries: [
        {
          'type': 'playlist',
          'playlist': {'name': 'missing', 'audios': []}
        }
      ]),
      _node('root', entries: [
        {'type': 'unknown', 'id': 'x'}
      ]),
      _node('root', entries: [
        {'type': 'audio', 'id': 'track', 'audio': {}}
      ]),
      _node('root', entries: [
        {'type': 'audio', 'id': 'a', 'audio': _song('A').toMap()},
        {'type': 'audio', 'id': 'b', 'audio': _song('A').toMap()},
      ]),
      {'version': 2, 'id': 'root', 'name': 'missing entries', 'audios': []},
      {'version': 99, 'id': 'root', 'name': 'future', 'entries': []},
    ];
    for (final value in malformed) {
      expect(() => decodePlaylists([value]), throwsFormatException);
    }
    expect(() => decodePlaylists({}), throwsFormatException);
    expect(() => decodePlaylists([null]), throwsFormatException);
  });

  test(
      'recursive maps and excessive serialized depth fail before recursion overflow',
      () {
    final cycle = _node('cycle');
    cycle['entries'] = [_child(cycle)];
    expect(() => Playlist.fromMap(cycle), throwsFormatException);
    var nested = _node('level-64');
    for (var depth = 63; depth >= 1; depth--) {
      nested = _node('level-$depth', entries: [_child(nested)]);
    }
    expect(() => decodePlaylists(jsonDecode(jsonEncode([nested]))),
        throwsFormatException);
  });

  test('playlistTree getter follows the current global root list', () {
    final rootsBefore = PLAYLISTS;
    final first = Playlist('first', {});
    final second = Playlist('second', {});
    try {
      PLAYLISTS = [first];
      expect(playlistTree.allPlaylists, [first]);
      PLAYLISTS = [second];
      expect(playlistTree.allPlaylists, [second]);
    } finally {
      PLAYLISTS = rootsBefore;
    }
  });

  test(
      'batch additions deduplicate in input order while retaining child positions',
      () {
    final example = _Example();
    final g = _song('G');
    final h = _song('H');
    final added = example.tree
        .addAudios(example.root, [example.a.audio, g, _song('G'), h], index: 1);
    expect(added.map((item) => item.audio.title), ['G', 'H']);
    expect(example.root.entries.map((entry) => entry.id),
        [example.a.id, added[0].id, added[1].id, example.b.id, example.f.id]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['A', 'G', 'H', 'C', 'E', 'F']);
  });

  test(
      'an invalid batch song rejects the whole addition before changing the tree',
      () {
    final example = _Example();
    final before = _snapshot(example.tree);
    final invalid = _song('invalid')..path = '';
    expect(() => example.tree.addAudios(example.root, [_song('G'), invalid]),
        throwsArgumentError);
    expect(_snapshot(example.tree), before);
    expect(example.tree.addAudios(example.root, const []), isEmpty);
  });

  test('one bulk order sorts a mixed level or roots without reparenting', () {
    final example = _Example();
    final second = example.tree.createPlaylist('第二个');
    example.tree.setOrder(
        parent: example.root,
        entryIds: [example.f.id, example.b.id, example.a.id]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['F', 'C', 'E', 'A']);
    example.tree.setOrder(parent: null, entryIds: [second.id, example.root.id]);
    expect(example.tree.roots, [second, example.root]);
    expect(example.d.pathFromRoot, [example.root, example.b, example.d]);
  });

  test('bulk order rejects omissions, duplicate IDs and foreign IDs atomically',
      () {
    final example = _Example();
    final before = _snapshot(example.tree);
    for (final ids in [
      [example.a.id, example.b.id],
      [example.a.id, example.b.id, example.a.id],
      [example.a.id, example.b.id, example.e.id],
    ]) {
      expect(() => example.tree.setOrder(parent: example.root, entryIds: ids),
          throwsArgumentError);
    }
    expect(_snapshot(example.tree), before);
  });

  test(
      'batch removal preserves unselected mixed entries and detaches full subtrees',
      () {
    final example = _Example();
    example.tree.removeEntries(
        parent: example.root,
        entryIds: [example.a.id, example.b.id, example.a.id]);
    expect(example.root.entries.single.id, example.f.id);
    expect(example.b.parent, isNull);
    expect(example.b.flattenAudios().map((audio) => audio.title), ['C', 'E']);
    expect(example.d.parent, same(example.b));
    expect(example.a.audio.title, 'A');
  });

  test(
      'batch root removal detaches only the selected roots and retains their songs',
      () {
    final example = _Example();
    final second = example.tree.createPlaylist('第二个');
    final third = example.tree.createPlaylist('第三个');
    example.tree
        .removeEntries(parent: null, entryIds: [example.root.id, third.id]);
    expect(example.tree.roots, [second]);
    expect(example.root.flattenAudios().map((audio) => audio.title),
        ['A', 'C', 'E', 'F']);
    expect(example.b.parent, same(example.root));
    expect(third.parent, isNull);
  });

  test('a stale or nested batch removal ID rejects the complete selection', () {
    final example = _Example();
    final before = _snapshot(example.tree);
    expect(
        () => example.tree.removeEntries(
            parent: example.root, entryIds: [example.a.id, example.e.id]),
        throwsArgumentError);
    expect(
        () => example.tree.removeEntries(
            parent: example.root, entryIds: [example.a.id, 'missing']),
        throwsArgumentError);
    expect(
        () => example.tree.removeEntries(
            parent: null, entryIds: [example.root.id, example.b.id]),
        throwsArgumentError);
    example.tree.removeEntries(parent: example.root, entryIds: []);
    expect(_snapshot(example.tree), before);
  });
}
