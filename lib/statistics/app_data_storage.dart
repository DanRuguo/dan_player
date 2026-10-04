import 'dart:io';
import 'package:path/path.dart' as p;

class AppDataStoragePart {
  const AppDataStoragePart(this.label, this.files, this.bytes,
      {this.paths = const []});
  final String label;
  final int files, bytes;
  final List<String> paths;
}

class AppDataStorageSnapshot {
  const AppDataStorageSnapshot(
      {required this.path,
      required this.parts,
      required this.unreadable,
      required this.skippedLinks,
      required this.truncated});
  final String path;
  final List<AppDataStoragePart> parts;
  final int unreadable, skippedLinks;
  final bool truncated;
  int get bytes => parts.fold(0, (v, part) => v + part.bytes);
  int get files => parts.fold(0, (v, part) => v + part.files);
}

/// Read-only, bounded filesystem inspection on explicit page entry/refresh.
/// User documents are reported separately from disposable cached responses.
class AppDataStorageScanner {
  const AppDataStorageScanner({this.maximumEntries = 200000});
  final int maximumEntries;
  Future<AppDataStorageSnapshot> scan(Directory directory) async {
    final totals = <String, (int, int)>{};
    final locations = <String, Set<String>>{};
    var unreadable = 0, links = 0, visited = 0, truncated = false;
    final todo = [directory];
    final clock = Stopwatch()..start();
    while (todo.isNotEmpty && !truncated) {
      final current = todo.removeLast();
      try {
        final resolved = await current.resolveSymbolicLinks();
        if (!p.equals(
            p.normalize(resolved), p.normalize(current.absolute.path))) {
          links++;
          continue;
        }
        await for (final entity in current
            .list(followLinks: false)
            .timeout(const Duration(seconds: 3))) {
          if (++visited > maximumEntries ||
              clock.elapsed > const Duration(seconds: 15)) {
            truncated = true;
            break;
          }
          if (entity is Link) {
            links++;
            continue;
          }
          if (entity is Directory) {
            todo.add(entity);
            continue;
          }
          if (entity is! File) continue;
          try {
            final stat =
                await entity.stat().timeout(const Duration(seconds: 3));
            if (stat.type != FileSystemEntityType.file) {
              unreadable++;
              continue;
            }
            final category =
                categoryFor(p.relative(entity.path, from: directory.path));
            final old = totals[category] ?? (0, 0);
            totals[category] = (old.$1 + 1, old.$2 + stat.size);
            final paths = locations.putIfAbsent(category, () => <String>{});
            if (paths.length < 12) {
              paths.add(category == categories[2]
                  ? p.join(
                      directory.path,
                      p.joinAll(p
                          .split(p.relative(entity.path, from: directory.path))
                          .take(2)))
                  : p.equals(p.dirname(entity.path), directory.path)
                      ? entity.path
                      : p.dirname(entity.path));
            }
          } catch (_) {
            unreadable++;
          }
        }
      } catch (_) {
        unreadable++;
      }
    }
    return AppDataStorageSnapshot(
        path: directory.path,
        parts: [
          for (final label in categories)
            if (totals.containsKey(label))
              AppDataStoragePart(label, totals[label]!.$1, totals[label]!.$2,
                  paths: List.unmodifiable(locations[label] ?? <String>{}))
        ],
        unreadable: unreadable,
        skippedLinks: links,
        truncated: truncated);
  }

  static const categories = [
    '封面缓存',
    '联网歌词缓存',
    '评论缓存',
    '其他缓存',
    '自选图片与封面',
    '曲库与用户资料',
    '迁移与恢复快照',
    '更新与临时文件',
    '其他数据'
  ];

  static String categoryFor(String relative) {
    final value = relative.replaceAll('\\', '/').toLowerCase();
    if (value.startsWith('covers/') || value.startsWith('metadata_preview/')) {
      return categories[0];
    }
    if (value.startsWith('cache/online_lyrics/')) return categories[1];
    if (value.startsWith('cache/song_comments/')) return categories[2];
    if (value.startsWith('cache/')) return categories[3];
    if (value.startsWith('background-images/') ||
        value.startsWith('category-covers/') ||
        value.startsWith('playlist-covers/') ||
        value.startsWith('imported-assets/')) {
      return categories[4];
    }
    if (value.startsWith('library_migrations/') ||
        value.startsWith('.dan-player-')) {
      return categories[6];
    }
    if (value.startsWith('updates/') ||
        value.endsWith('.tmp') ||
        value.endsWith('.partial') ||
        value.endsWith('.pending')) {
      return categories[7];
    }
    if (value.endsWith('.json') ||
        value.endsWith('.json.bak') ||
        value.startsWith('lyric_tap_progress/')) {
      return categories[5];
    }
    return categories[8];
  }
}
