import 'package:dan_player/component/folder_tree_pane.dart';
import 'package:dan_player/library/audio_folder_sort.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/library/folder_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/music_category_fixtures.dart';

AudioFolder _folder(String name, {int count = 0, int modified = 0}) =>
    AudioFolder([
      for (var i = 0; i < count; i++) CategoryTestAudio('$name-$i'),
    ], name, modified, 0);

void main() {
  test('empty library and empty roots produce an empty forest', () {
    final tree = FolderTree.project(folders: [], scanRoots: []);
    expect(tree.roots, isEmpty);
    expect(tree.byId, isEmpty);
    expect(tree.visibleSections({}), isEmpty);
    expect(tree.ancestorsOf(r'J:\absent'), isEmpty);
  });

  test('selected empty roots are visible without inventing disk contents', () {
    final tree = FolderTree.project(folders: [], scanRoots: [r'J:\music']);
    expect(tree.roots.single.folder.path, r'J:\music');
    expect(tree.roots.single.canExpand, isFalse);
    expect(tree.roots.single.songCount, 0);
    expect(tree.roots.single.modified, 0);
  });

  test('missing intermediate directories retain each true path level', () {
    final leaf = _folder(r'J:\music\A\B\C', count: 2, modified: 42);
    final tree = FolderTree.project(folders: [leaf], scanRoots: [r'J:\music']);
    var node = tree.roots.single;
    for (final name in [r'J:\music', r'J:\music\A', r'J:\music\A\B']) {
      expect(node.folder.path, name);
      expect(node.indexed, isFalse);
      expect(node.folder.audios, isEmpty);
      expect(node.songCount, 2);
      expect(node.modified, 42);
      node = node.children.single;
    }
    expect(node.folder, same(leaf));
    expect(node.depth, 3);
    expect(node.indexed, isTrue);
    expect(leaf.audios, hasLength(2));
  });

  test('component boundaries do not parent Music2 below Music', () {
    final tree = FolderTree.project(
        folders: [_folder(r'J:\Music\C'), _folder(r'J:\Music2\D')],
        scanRoots: [r'J:\Music', r'J:\Music2']);
    expect(tree.roots.map((node) => node.folder.path),
        [r'J:\Music', r'J:\Music2']);
    expect(tree.roots[0].children.single.folder.path, r'J:\Music\C');
    expect(tree.roots[1].children.single.folder.path, r'J:\Music2\D');
  });

  test('Windows case aliases and overlapping roots do not duplicate songs', () {
    final original = _folder(r'J:\Music\Album', count: 2);
    final alias = AudioFolder(original.audios, r'j:/music/ALBUM', 8, 0);
    final tree = FolderTree.project(
        folders: [original, alias],
        scanRoots: [r'J:\Music', r'j:/MUSIC/Album']);
    expect(tree.roots, hasLength(1));
    expect(tree.byId, hasLength(2));
    expect(tree.roots.single.songCount, 2);
    expect(tree.roots.single.children.single.folder.audios, original.audios);
    expect(tree.ancestorsOf(r'j:/MUSIC/album'), {
      folderTreePathId(r'J:\Music'),
      folderTreePathId(r'J:\Music\Album'),
    });
  });

  test('UNC roots preserve boundaries and empty nested scan roots', () {
    final tree = FolderTree.project(
        folders: [_folder(r'\\server\share\Music\A\B')],
        scanRoots: [r'\\server\share\Music', r'\\server\share\Music\Empty']);
    expect(tree.byId, hasLength(4));
    expect(tree.roots.single.children.map((node) => node.folder.path),
        [r'\\server\share\Music\A', r'\\server\share\Music\Empty']);
  });

  test('every parent direct song section precedes expanded child branches', () {
    final a = _folder(r'J:\A', count: 1);
    final b = _folder(r'J:\A\B', count: 2);
    final c = _folder(r'J:\A\B\C', count: 3);
    final d = _folder(r'J:\A\D', count: 4);
    final tree = FolderTree.project(folders: [d, c, b, a], scanRoots: []);
    final sections = tree.visibleSections(tree.byId.keys.toSet());
    expect(
        sections.map((section) => (section.node.folder.path, section.songs)), [
      (a.path, false),
      (a.path, true),
      (b.path, false),
      (b.path, true),
      (c.path, false),
      (c.path, true),
      (d.path, false),
      (d.path, true),
    ]);
    expect(
        sections
            .where((section) => section.songs)
            .expand((section) => section.node.folder.audios),
        hasLength(10));
    expect(tree.roots.single.folder.audios, same(a.audios));
  });

  for (final direction in SortDirection.values) {
    test('subtree song count ${direction.name} sorts each sibling level stably',
        () {
      final tree = FolderTree.project(folders: [
        _folder(r'J:\root\B\leaf', count: 2),
        _folder(r'J:\root\A\leaf', count: 1),
        _folder(r'J:\root\Equal\leaf', count: 1),
      ], scanRoots: [
        r'J:\root'
      ], field: AudioFolderSortField.songCount, direction: direction);
      expect(
          tree.roots.single.children.map((node) => node.folder.path),
          direction == SortDirection.ascending
              ? [r'J:\root\A', r'J:\root\Equal', r'J:\root\B']
              : [r'J:\root\B', r'J:\root\A', r'J:\root\Equal']);
      expect(tree.roots.single.folder.audios, isEmpty);
      expect(tree.roots.single.songCount, 4);
    });

    test('subtree modified ${direction.name} keeps unknown dates last', () {
      final tree = FolderTree.project(folders: [
        _folder(r'J:\root\unknown'),
        _folder(r'J:\root\new\leaf', modified: 20),
        _folder(r'J:\root\old\leaf', modified: 10),
      ], scanRoots: [
        r'J:\root'
      ], field: AudioFolderSortField.modified, direction: direction);
      expect(
          tree.roots.single.children.map((node) => node.folder.path),
          direction == SortDirection.ascending
              ? [r'J:\root\old', r'J:\root\new', r'J:\root\unknown']
              : [r'J:\root\new', r'J:\root\old', r'J:\root\unknown']);
    });
  }

  test('deep tree indentation remains bounded without skipping path levels',
      () {
    final leaf = r'J:\root' + List.filled(120, r'\next').join();
    final tree = FolderTree.project(
        folders: [_folder(leaf, count: 1)], scanRoots: [r'J:\root']);
    expect(tree.byId, hasLength(121));
    expect(tree.byId[folderTreePathId(leaf)]!.depth, 120);
    final step = folderTreeIndentStep(360, 121);
    expect(step * 121, closeTo(360 * .18, 1e-8));
    expect(step, greaterThan(0));
  });
}
