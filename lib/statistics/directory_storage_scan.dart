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

class DirectoryStorageScanCancelled implements Exception {
  const DirectoryStorageScanCancelled();
}

/// Metadata-only traversal shared by data and installation-directory reports.
/// Links, including a linked root or an ancestor junction, are not followed.
class DirectoryStorageScan {
  const DirectoryStorageScan({
    this.maximumEntries = 200000,
    this.maximumDuration = const Duration(seconds: 15),
    this.operationTimeout = const Duration(seconds: 3),
    this.verifyFileLinks = false,
  });
  final int maximumEntries;
  final Duration maximumDuration, operationTimeout;
  final bool verifyFileLinks;

  Future<AppDataStorageSnapshot> scan(
    Directory directory, {
    required List<String> categories,
    required String Function(String relative) categoryFor,
    required String Function(File file, String relative) locationFor,
    bool Function()? isCancelled,
  }) async {
    final totals = <String, (int, int)>{};
    final locations = <String, Set<String>>{};
    var unreadable = 0, links = 0, visited = 0, truncated = false;
    final todo = [directory];
    final clock = Stopwatch()..start();
    void checkCancellation() {
      if (isCancelled?.call() == true) {
        throw const DirectoryStorageScanCancelled();
      }
    }

    bool expired() => clock.elapsed >= maximumDuration;
    Duration timeout() {
      final remaining = maximumDuration - clock.elapsed;
      return remaining < operationTimeout ? remaining : operationTimeout;
    }

    while (todo.isNotEmpty && !truncated) {
      checkCancellation();
      if (expired()) {
        truncated = true;
        break;
      }
      final current = todo.removeLast();
      try {
        final resolved =
            await current.resolveSymbolicLinks().timeout(timeout());
        checkCancellation();
        if (!p.equals(
            p.normalize(resolved), p.normalize(current.absolute.path))) {
          links++;
          continue;
        }
        if (expired()) {
          truncated = true;
          break;
        }
        await for (final entity
            in current.list(followLinks: false).timeout(timeout())) {
          checkCancellation();
          if (++visited > maximumEntries || expired()) {
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
            // The player report rechecks file paths after enumeration. Keep
            // the existing large-cache report's one-stat-per-file cost.
            if (verifyFileLinks) {
              final resolved =
                  await entity.resolveSymbolicLinks().timeout(timeout());
              checkCancellation();
              if (!p.equals(
                  p.normalize(resolved), p.normalize(entity.absolute.path))) {
                links++;
                continue;
              }
            }
            final stat = await entity.stat().timeout(timeout());
            checkCancellation();
            if (expired()) {
              truncated = true;
              break;
            }
            if (stat.type != FileSystemEntityType.file) {
              unreadable++;
              continue;
            }
            final relative = p.relative(entity.path, from: directory.path);
            final category = categoryFor(relative);
            final old = totals[category] ?? (0, 0);
            totals[category] = (old.$1 + 1, old.$2 + stat.size);
            final paths = locations.putIfAbsent(category, () => <String>{});
            if (paths.length < 12) paths.add(locationFor(entity, relative));
          } on DirectoryStorageScanCancelled {
            rethrow;
          } catch (_) {
            unreadable++;
            if (expired()) truncated = true;
          }
        }
      } on DirectoryStorageScanCancelled {
        rethrow;
      } catch (_) {
        unreadable++;
        if (expired()) truncated = true;
      }
    }
    checkCancellation();
    return AppDataStorageSnapshot(
        path: directory.path,
        parts: List.unmodifiable([
          for (final label in categories)
            if (totals.containsKey(label))
              AppDataStoragePart(label, totals[label]!.$1, totals[label]!.$2,
                  paths: List.unmodifiable(locations[label] ?? <String>{}))
        ]),
        unreadable: unreadable,
        skippedLinks: links,
        truncated: truncated);
  }
}
