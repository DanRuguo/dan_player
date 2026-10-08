import 'dart:io';
import 'package:path/path.dart' as p;
import 'directory_storage_scan.dart';
export 'directory_storage_scan.dart'
    show AppDataStoragePart, AppDataStorageSnapshot;

/// Read-only, bounded filesystem inspection on explicit page entry/refresh.
/// User documents are reported separately from disposable cached responses.
class AppDataStorageScanner {
  const AppDataStorageScanner({this.maximumEntries = 200000});
  final int maximumEntries;
  Future<AppDataStorageSnapshot> scan(Directory directory) =>
      DirectoryStorageScan(maximumEntries: maximumEntries).scan(directory,
          categories: categories,
          categoryFor: categoryFor,
          locationFor: (file, relative) =>
              categoryFor(relative) == categories[2]
                  ? p.join(directory.path, p.joinAll(p.split(relative).take(2)))
                  : p.equals(p.dirname(file.path), directory.path)
                      ? file.path
                      : p.dirname(file.path));

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
