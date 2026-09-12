import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/data/backup_selection.dart';
import 'package:path/path.dart' as path;

/// Kept only in a staged restore, never exported. Unselected data is refreshed
/// at activation so playing or editing before "restart later" cannot roll it
/// back to the snapshot taken when the restore dialog was open.
class BackupRestorePreservation {
  static const planName = '.dan-player-restore-preserve.json';

  static Future<void> writePlan(
      {required Directory staged,
      required Directory source,
      required Set<BackupComponent> selected,
      required Set<String> protectedPaths}) async {
    await File(path.join(staged.path, planName)).writeAsString(
        json.encode({
          'version': 1,
          'source': source.absolute.path,
          'selected': selected.map((value) => value.name).toList(),
          'protected': protectedPaths.toList(),
        }),
        flush: true);
  }

  static Future<void> refreshBeforeActivation(
      {required Directory? currentData,
      required Directory staged,
      required Directory destination,
      bool removePlan = true}) async {
    final current = currentData?.absolute.path;
    final stagedPath = staged.absolute.path,
        destinationPath = destination.absolute.path;
    await Isolate.run(
        () => _refresh(current, stagedPath, destinationPath, removePlan));
  }

  static Future<void> _refresh(String? currentPath, String stagedPath,
      String destinationPath, bool removePlan) async {
    final planFile = File(path.join(stagedPath, planName));
    if (!await planFile.exists()) return;
    if (await planFile.length() > 16 * 1024 * 1024)
      throw const FormatException('Invalid restore preservation plan');
    final raw = json.decode(await planFile.readAsString());
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['source'] is! String ||
        raw['selected'] is! List ||
        raw['protected'] is! List ||
        !path.isAbsolute(raw['source'] as String)) {
      throw const FormatException('Invalid restore preservation plan');
    }
    final sourcePath = raw['source'] as String;
    if (currentPath != null &&
        !path.equals(path.normalize(currentPath), path.normalize(sourcePath))) {
      throw const FormatException(
          'The active data location changed after restore preparation');
    }
    if (path.equals(path.normalize(sourcePath), path.normalize(stagedPath))) {
      throw const FormatException('Unsafe restore preservation source');
    }
    final selected = <BackupComponent>{};
    for (final value in raw['selected'] as List) {
      final matches =
          BackupComponent.values.where((component) => component.name == value);
      if (matches.isEmpty)
        throw const FormatException('Invalid selected restore component');
      selected.add(matches.single);
    }
    final protected = <String>{};
    for (final value in raw['protected'] as List) {
      if (value is! String || !_safe(value))
        throw const FormatException('Unsafe preserved resource path');
      protected.add(_relative(value));
    }
    final currentReferences = <String>{};
    bool preserve(String relative) =>
        !protected.contains(_relative(relative)) &&
        (_relative(relative).startsWith('restored-music/') ||
            currentReferences.contains(_relative(relative)) ||
            !selected.contains(backupComponentForPath(relative)));
    final source = Directory(sourcePath), staged = Directory(stagedPath);
    if (!await source.exists())
      throw const FileSystemException(
          'Original data is unavailable for selective restore');
    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: sourcePath);
      if (!_excluded(relative) &&
          (relative.endsWith('.json') || relative.endsWith('.json.bak')) &&
          !selected.contains(backupComponentForPath(relative))) {
        currentReferences.addAll(referencedCurrentCacheAssets(
            json.decode(await entity.readAsString()), sourcePath));
      }
    }

    // Remove stale unselected snapshots first. Only the private staging tree is
    // touched; an interrupted refresh is retried before activation next time.
    await for (final entity
        in staged.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: stagedPath);
      if (_excluded(relative) || !preserve(relative)) continue;
      await entity.delete();
    }
    Object? remap(Object? value) {
      if (value is String &&
          path.isAbsolute(value) &&
          (path.equals(path.normalize(sourcePath), path.normalize(value)) ||
              path.isWithin(sourcePath, value))) {
        return path.join(
            destinationPath, path.relative(value, from: sourcePath));
      }
      if (value is List) return value.map(remap).toList();
      if (value is Map)
        return {
          for (final entry in value.entries)
            remap(entry.key.toString()) as String: remap(entry.value)
        };
      return value;
    }

    await for (final entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = path.relative(entity.path, from: sourcePath);
      if (_excluded(relative) || !preserve(relative)) continue;
      if (!_safe(relative))
        throw const FormatException('Unsafe current data path');
      final before = await entity.stat();
      final output = File(path.join(stagedPath, relative));
      await output.parent.create(recursive: true);
      await entity.copy(output.path);
      final after = await entity.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const FileSystemException(
            'Current data changed while preparing restore');
      }
      if (relative.endsWith('.json') || relative.endsWith('.json.bak')) {
        await output.writeAsString(
            json.encode(remap(json.decode(await output.readAsString()))),
            flush: true);
      }
    }
    if (removePlan) await planFile.delete();
  }

  static String _relative(String value) =>
      value.replaceAll('\\', '/').toLowerCase();
  static bool _safe(String value) =>
      !path.isAbsolute(value) &&
      !value
          .split(RegExp(r'[/\\]'))
          .any((piece) => piece == '..' || piece.isEmpty) &&
      !value.contains(':') &&
      !value.contains('\u0000');
  static bool _excluded(String value) {
    final relative = _relative(value);
    return relative == planName ||
        relative.startsWith('.dan-player-') ||
        relative.startsWith('updates/') ||
        relative.startsWith('library_migrations/') ||
        relative.endsWith('.tmp') ||
        relative.endsWith('.pending') ||
        relative.endsWith('.partial') ||
        relative.endsWith('.migration-tmp') ||
        relative.endsWith('.exe') ||
        relative.endsWith('.msi') ||
        relative.startsWith('library_migration') ||
        relative.startsWith('metadata_committed');
  }
}
