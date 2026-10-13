import 'dart:collection';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as path;

import 'audio_folder_sort.dart';
import 'audio_library.dart';
import 'audio_sort.dart';

/// A Windows directory identity, shared by expanded state and index refreshes.
String folderTreePathId(String value) =>
    path.windows.normalize(value).toLowerCase();

class FolderTreeNode {
  const FolderTreeNode({
    required this.folder,
    required this.depth,
    required this.children,
    required this.indexed,
    required this.songCount,
    required this.modified,
  });

  final AudioFolder folder;
  final int depth;
  final List<FolderTreeNode> children;
  final bool indexed;

  /// Branch statistics; [folder.audios] remains direct songs only.
  final int songCount, modified;
  String get id => folderTreePathId(folder.path);
  bool get canExpand => children.isNotEmpty || folder.audios.isNotEmpty;
}

/// Read-only projection of indexed folders, including missing intermediate
/// directories under selected scan roots. Constructing a tree performs no IO.
class FolderTree {
  FolderTree._(this.roots, this.byId);

  final List<FolderTreeNode> roots;
  final Map<String, FolderTreeNode> byId;

  factory FolderTree.project({
    required Iterable<AudioFolder> folders,
    required Iterable<String> scanRoots,
    AudioFolderSortField field = AudioFolderSortField.path,
    SortDirection direction = SortDirection.ascending,
  }) {
    final indexed = <String, AudioFolder>{};
    for (final folder in folders) {
      if (folder.path.trim().isEmpty) continue;
      final id = folderTreePathId(folder.path);
      final previous = indexed[id];
      if (previous == null) {
        indexed[id] = folder;
      } else {
        // Overlapping scan roots must not duplicate a directory or its songs.
        final audios = <String, Audio>{
          for (final audio in previous.audios) audio.path: audio,
          for (final audio in folder.audios) audio.path: audio,
        };
        indexed[id] = AudioFolder(
            audios.values.toList(),
            previous.path,
            math.max(previous.modified, folder.modified),
            math.max(previous.latest, folder.latest));
      }
    }

    final candidates = <String, String>{
      for (final folder in indexed.values)
        folderTreePathId(folder.path): path.windows.normalize(folder.path),
      for (final root in scanRoots)
        if (root.trim().isNotEmpty)
          folderTreePathId(root): path.windows.normalize(root),
    };
    // Empty scan roots remain visible. Nested roots share one natural branch.
    final rootPaths = candidates.values.where((candidate) {
      final id = folderTreePathId(candidate);
      var ancestor = folderTreePathId(path.windows.dirname(id));
      while (ancestor != id) {
        if (candidates.containsKey(ancestor)) return false;
        final parent = folderTreePathId(path.windows.dirname(ancestor));
        if (ancestor == parent) break;
        ancestor = parent;
      }
      return true;
    }).toList();
    final rootIds = rootPaths.map(folderTreePathId).toSet();
    final source = <String, AudioFolder>{...indexed};
    final parents = <String, String?>{};
    for (final root in rootPaths) {
      final rootId = folderTreePathId(root);
      source.putIfAbsent(rootId, () => AudioFolder([], root, 0, 0));
      parents[rootId] = null;
    }
    for (final value in candidates.values) {
      var current = value;
      while (!rootIds.contains(folderTreePathId(current))) {
        final id = folderTreePathId(current);
        if (parents.containsKey(id)) break;
        final parent = path.windows.dirname(current);
        final parentId = folderTreePathId(parent);
        source.putIfAbsent(id, () => AudioFolder([], current, 0, 0));
        source.putIfAbsent(parentId, () => AudioFolder([], parent, 0, 0));
        parents[id] = parentId;
        current = parent;
      }
    }
    final children = <String?, List<AudioFolder>>{};
    for (final entry in parents.entries) {
      (children[entry.value] ??= []).add(source[entry.key]!);
    }
    void sort(List<FolderTreeNode> siblings) {
      final stable = siblings.asMap().entries.toList();
      stable.sort((left, right) {
        final a = left.value;
        final b = right.value;
        final compared = switch (field) {
          AudioFolderSortField.path =>
            compareSortText(a.folder.path, b.folder.path, direction: direction),
          AudioFolderSortField.modified => compareSortNumbers(
              a.modified > 0 ? a.modified : null,
              b.modified > 0 ? b.modified : null,
              direction: direction),
          AudioFolderSortField.songCount =>
            compareSortNumbers(a.songCount, b.songCount, direction: direction),
        };
        return compared == 0 ? left.key.compareTo(right.key) : compared;
      });
      siblings.setAll(0, stable.map((entry) => entry.value));
    }

    final nodes = <String, FolderTreeNode>{};
    FolderTreeNode build(AudioFolder folder, int depth) {
      final id = folderTreePathId(folder.path);
      final nested = [
        for (final child in children[id] ?? const <AudioFolder>[])
          build(child, depth + 1),
      ];
      sort(nested);
      final node = FolderTreeNode(
          folder: folder,
          depth: depth,
          indexed: indexed.containsKey(id),
          songCount: folder.audios.length +
              nested.fold<int>(0, (sum, child) => sum + child.songCount),
          modified: nested.fold<int>(folder.modified,
              (latest, child) => math.max(latest, child.modified)),
          children: List.unmodifiable(nested));
      nodes[id] = node;
      return node;
    }

    final roots = [
      for (final root in children[null] ?? const <AudioFolder>[]) build(root, 0)
    ];
    sort(roots);
    return FolderTree._(List.unmodifiable(roots), Map.unmodifiable(nodes));
  }

  /// Direct songs belong immediately below their folder header; sorted child
  /// branches follow them. This is also the order used by range selection.
  List<FolderTreeSection> visibleSections(Set<String> expanded) {
    final sections = <FolderTreeSection>[];
    void visit(FolderTreeNode node) {
      sections.add(FolderTreeSection(node, songs: false));
      if (!expanded.contains(node.id)) return;
      if (node.folder.audios.isNotEmpty) {
        sections.add(FolderTreeSection(node, songs: true));
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final root in roots) {
      visit(root);
    }
    return sections;
  }

  Set<String> ancestorsOf(String value) {
    var id = folderTreePathId(value);
    final result = <String>{};
    while (true) {
      if (byId.containsKey(id)) result.add(id);
      final parent = folderTreePathId(path.windows.dirname(id));
      if (parent == id) break;
      id = parent;
    }
    return result;
  }
}

class FolderTreeSection {
  const FolderTreeSection(this.node, {required this.songs});
  final FolderTreeNode node;
  final bool songs;
  String get id => '${songs ? "songs" : "folder"}:${node.id}';
}

/// A read-only view of folder queues. Constructing a selection/sort-menu view
/// touches folder lengths, rather than copying every song on each expansion.
class FolderTreeAudioList extends ListBase<Audio> {
  FolderTreeAudioList(Iterable<List<Audio>> sources) {
    for (final source in sources) {
      if (source.isEmpty) continue;
      _sources.add(source);
      _length += source.length;
      _ends.add(_length);
    }
  }

  final _sources = <List<Audio>>[];
  final _ends = <int>[];
  int _length = 0;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Read-only folder queues');
  @override
  Audio operator [](int index) {
    RangeError.checkValidIndex(index, this);
    var low = 0, high = _ends.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (index < _ends[middle]) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return _sources[low][index - (low == 0 ? 0 : _ends[low - 1])];
  }

  @override
  void operator []=(int index, Audio value) =>
      throw UnsupportedError('Read-only folder queues');
}

typedef FolderTreeSongSorter = Future<List<Audio>> Function(
    List<Audio> songs, AudioSortField field, SortDirection direction);

class FolderTreeSortCancelled implements Exception {
  const FolderTreeSortCancelled();
}

/// Use the existing stable/missing-value/pinyin comparator in a worker. Only
/// indices return: playback and selection retain the caller's Audio objects.
Future<List<Audio>> sortFolderTreeSongs(
    List<Audio> songs, AudioSortField field, SortDirection direction,
    {bool Function()? isCancelled}) async {
  void checkOwner() {
    if (isCancelled?.call() == true) throw const FolderTreeSortCancelled();
  }

  checkOwner();
  final source = <Audio>[];
  final keys = <Object?>[];
  final length = songs.length;
  const batchSize = 512;
  for (var start = 0; start < length; start += batchSize) {
    checkOwner();
    if (songs.length != length) throw ConcurrentModificationError(songs);
    final end = math.min(start + batchSize, length);
    for (var index = start; index < end; index++) {
      final audio = songs[index];
      source.add(audio);
      keys.add(audioSortKey(audio, field));
    }
    if (end < length) await Future<void>.delayed(Duration.zero);
  }
  // Do not dispatch obsolete descriptors after collapse, replacement or a
  // newer sort. A worker already running retains the existing result guard.
  checkOwner();
  final indices = await _sortFolderKeys(keys, direction);
  return List<Audio>.unmodifiable(indices.map((index) => source[index]));
}

// Keep the closure in its own function: sortFolderTreeSongs also retains Audio
// objects, and capturing its context would deep-copy their entire graph.
Future<List<int>> _sortFolderKeys(
        List<Object?> keys, SortDirection direction) =>
    Isolate.run(() => sortedAudioSortKeyIndices(keys, direction: direction));
