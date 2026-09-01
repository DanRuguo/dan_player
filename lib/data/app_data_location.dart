import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

const String appDataReadyMarkerName = '.dan-player-data-ready';

/// Small, process-independent pointer to the directory that owns Dan Player's
/// persistent data. A pending path becomes active only on the next process
/// start, so live services keep writing to the directory they opened at boot.
class AppDataLocationStore {
  AppDataLocationStore(this.file);

  final File file;

  Future<String?> activatePendingOrReadActive() async {
    final state = await _read();
    final pending = _validAbsolute(state['pendingPath']);
    final staged = _validAbsolute(state['pendingStagedPath']);
    final active = _validAbsolute(state['activePath']);
    if (pending == null) return active;
    final candidate = Directory(staged ?? pending);
    final marker = File(path.join(candidate.path, appDataReadyMarkerName));
    // Never activate a stale pointer after the restored directory was moved or
    // partially removed. Keep the known active root and clear only pending.
    if (!await candidate.exists() || !await marker.exists()) {
      await _write(<String, Object?>{
        'version': 1,
        'activePath': active,
        'pendingPath': null,
        'pendingStagedPath': null,
      });
      return active;
    }

    if (staged != null) {
      return _activateReplacement(
        active: active,
        target: Directory(pending),
        staged: Directory(staged),
      );
    }

    await _write(<String, Object?>{
      'version': 1,
      'activePath': pending,
      'pendingPath': null,
      'pendingStagedPath': null,
    });
    return pending;
  }

  Future<String?> _activateReplacement({
    required String? active,
    required Directory target,
    required Directory staged,
  }) async {
    await target.parent.create(recursive: true);
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final previous = Directory(
        path.join(target.parent.path, '.dan-player-before-restore-$nonce'));
    final failed = Directory(
        path.join(target.parent.path, '.dan-player-activation-failed-$nonce'));
    var movedPrevious = false;
    var installed = false;
    try {
      if (await target.exists()) {
        await target.rename(previous.path);
        movedPrevious = true;
      }
      await staged.rename(target.path);
      installed = true;
      await _write(<String, Object?>{
        'version': 1,
        'activePath': target.path,
        'pendingPath': null,
        'pendingStagedPath': null,
      });
    } catch (activationError) {
      // The stable pointer still names [active]. Put the old target back before
      // falling back to it; if that is impossible, retain every directory and
      // propagate so startup never silently creates an empty cache root.
      var rollbackComplete = true;
      try {
        if (installed && await target.exists()) {
          await target.rename(failed.path);
          installed = false;
        }
        if (movedPrevious &&
            !await target.exists() &&
            await previous.exists()) {
          await previous.rename(target.path);
          movedPrevious = false;
        }
      } catch (_) {
        rollbackComplete = false;
      }
      if (await failed.exists()) {
        try {
          await failed.rename(staged.path);
        } catch (_) {
          // Keep the failed candidate recoverable under its unique name.
          rollbackComplete = false;
        }
      }
      if (movedPrevious ||
          (active != null && !await Directory(active).exists())) {
        rollbackComplete = false;
      }
      if (!rollbackComplete) {
        throw FileSystemException(
            'Could not safely roll back restored app data activation',
            target.path,
            activationError is OSError ? activationError : null);
      }
      // A completely rolled-back transaction must not retry forever on every
      // launch. Clearing pending is itself atomic; if it fails, propagate.
      await _write(<String, Object?>{
        'version': 1,
        'activePath': active,
        'pendingPath': null,
        'pendingStagedPath': null,
      });
      return active;
    }
    if (movedPrevious && await previous.exists()) {
      // The pointer already commits the restored directory. Removing a large
      // former artwork/cache tree is best-effort housekeeping and must not
      // hold the first restored launch on disk I/O.
      unawaited(_deleteObsoleteDirectory(previous));
    }
    return target.path;
  }

  static Future<void> _deleteObsoleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A harmless old copy is preferable to failing an otherwise complete
      // activation. Its unique restore name also prevents it being loaded.
    }
  }

  /// Schedules [nextPath] for the next launch. It deliberately does not change
  /// the process-local directory returned by `getAppDataDir()`.
  Future<void> schedule({
    required String nextPath,
    required String currentPath,
    required String stagedPath,
  }) async {
    final next = _validAbsolute(nextPath);
    final current = _validAbsolute(currentPath);
    final staged = _validAbsolute(stagedPath);
    if (next == null || current == null || staged == null) {
      throw const FormatException('App data paths must be absolute');
    }
    if (!await Directory(staged).exists() ||
        !await File(path.join(staged, appDataReadyMarkerName)).exists()) {
      throw const FileSystemException(
          'Restored app data is incomplete or no longer exists');
    }
    await _write(<String, Object?>{
      'version': 1,
      'activePath': current,
      'pendingPath': next,
      'pendingStagedPath': staged,
    });
  }

  Future<Map<String, Object?>> _read() async {
    try {
      if (!await file.exists()) return const <String, Object?>{};
      final decoded = json.decode(await file.readAsString());
      return decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{};
    } catch (_) {
      // A damaged optional pointer must never prevent the player opening with
      // its documented Documents directory.
      return const <String, Object?>{};
    }
  }

  Future<void> _write(Map<String, Object?> value) async {
    await file.parent.create(recursive: true);
    final nonce = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${file.path}.$nonce.tmp');
    final previous = File('${file.path}.$nonce.previous');
    await temporary.writeAsString(json.encode(value), flush: true);
    var movedPrevious = false;
    var restoredPrevious = false;
    var committed = false;
    try {
      if (await file.exists()) {
        await file.rename(previous.path);
        movedPrevious = true;
      }
      await temporary.rename(file.path);
      committed = true;
    } catch (_) {
      if (!await file.exists() && movedPrevious && await previous.exists()) {
        await previous.rename(file.path);
        restoredPrevious = true;
      }
      rethrow;
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        // Cleanup must not hide the persistence result.
      }
      // Delete an obsolete previous copy only after the new file is known good
      // or the old file was successfully restored. If rollback itself failed,
      // previous is the only recoverable pointer and must remain on disk.
      if ((committed || restoredPrevious) && await previous.exists()) {
        try {
          await previous.delete();
        } catch (_) {}
      }
    }
  }

  static String? _validAbsolute(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final normalized = path.normalize(value.trim());
    return path.isAbsolute(normalized) ? normalized : null;
  }
}
