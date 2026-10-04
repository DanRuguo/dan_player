import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A restart-resumable cut. The journal lives outside both trees; no destination
/// is overwritten and source files are removed only after verified delivery.
class FolderMoveTransaction {
  FolderMoveTransaction(this.journal, {this.forceCopy = false, this.onPhase});
  final File journal;
  final bool forceCopy;
  final Future<void> Function(String)? onPhase;

  Future<bool> get pending async => await journal.exists();

  static Future<void> validate(Directory source, Directory destination) async {
    final from = p.normalize(source.absolute.path);
    final to = p.normalize(destination.absolute.path);
    if (p.equals(from, p.rootPrefix(from)) ||
        p.equals(to, p.rootPrefix(to)) ||
        p.equals(from, to) ||
        p.isWithin(from, to) ||
        p.isWithin(to, from)) {
      throw const FileSystemException('Choose a separate destination folder');
    }
    await _requirePlainDirectory(source);
    await _requirePlainDirectory(destination.parent);
    if (await FileSystemEntity.type(to, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException('Destination already exists', to);
    }
  }

  static Future<void> _requirePlainDirectory(Directory directory) async {
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !p.equals(p.normalize(await directory.resolveSymbolicLinks()),
            p.normalize(directory.absolute.path))) {
      throw FileSystemException(
          'Linked or inaccessible folder', directory.path);
    }
  }

  Future<void> schedule(Directory source, Directory destination) async {
    if (await pending) throw StateError('A folder move is already pending');
    final control = p.normalize(journal.absolute.path);
    if (p.isWithin(source.absolute.path, control) ||
        p.isWithin(destination.absolute.path, control)) {
      throw const FileSystemException('Move journal must be outside both folders');
    }
    await validate(source, destination);
    final id = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    await _write({
      'version': 1,
      'id': id,
      'phase': 'pending',
      'from': p.normalize(source.absolute.path),
      'to': p.normalize(destination.absolute.path),
    });
  }

  Future<Map<String, dynamic>> read() async {
    final value = jsonDecode(await journal.readAsString());
    if (value is! Map ||
        value['version'] != 1 ||
        value['id'] is! String ||
        !RegExp(r'^\d+-\d+$').hasMatch(value['id']) ||
        value['from'] is! String ||
        value['to'] is! String ||
        !p.isAbsolute(value['from']) ||
        !p.isAbsolute(value['to'])) {
      throw const FormatException('Invalid folder move journal');
    }
    final from = value['from'] as String, to = value['to'] as String;
    if (p.equals(from, to) ||
        p.isWithin(from, to) ||
        p.isWithin(to, from) ||
        p.equals(from, p.rootPrefix(from)) ||
        p.equals(to, p.rootPrefix(to))) {
      throw const FormatException('Unsafe folder move journal');
    }
    return Map<String, dynamic>.from(value);
  }

  /// [commit] runs before a cross-volume source is cut. It must itself be
  /// durable/idempotent, e.g. the existing library multi-document migration.
  Future<String> recover(
      {required Future<void> Function(String, String) commit,
      bool Function(String relative)? commitMayChange}) async {
    var state = await read();
    final source = Directory(state['from'] as String);
    final target = Directory(state['to'] as String);
    final staging = Directory(
        p.join(target.parent.path, '.dan-player-moving-${state['id']}'));
    Future<void> phase(String value) async {
      state['phase'] = value;
      await _write(state);
      await onPhase?.call(value);
    }

    if (state['phase'] == 'pending') {
      await validate(source, target);
      state['files'] = await _inventory(source);
      await phase('prepared');
    }
    final rows = (state['files'] as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    for (final row in rows) {
      final relative = row['name'];
      if (relative is! String ||
          p.isAbsolute(relative) ||
          relative.split(RegExp(r'[/\\]')).any((v) => v == '..') ||
          !p.isWithin(source.path, p.join(source.path, relative))) {
        throw const FormatException('Unsafe move manifest');
      }
    }
    if (state['phase'] == 'prepared') {
      await _checkInventory(source, rows);
      if (!forceCopy) {
        // Record ownership before rename: a crash afterwards can identify the
        // delivered tree without assuming an arbitrary pre-existing target.
        await phase('renaming');
      } else {
        await phase('copying');
      }
    }
    if (state['phase'] == 'renaming') {
      await _requirePlainDirectory(target.parent);
      if (await source.exists()) {
        if (await target.exists()) {
          throw StateError('Destination appeared during move');
        }
        try {
          await source.rename(target.path);
        } on FileSystemException {
          // A failed rename is not permission to overwrite a newly created
          // target. Across volumes use a verified, privately named staging tree.
          if (await target.exists()) rethrow;
          await phase('copying');
        }
      } else if (!await target.exists()) {
        throw StateError('Both move locations are unavailable');
      }
      if (state['phase'] == 'renaming') {
        await _checkInventory(target, rows);
        await phase('installed');
      }
    }
    if (state['phase'] == 'copying') {
      await _checkInventory(source, rows);
      await _requirePlainDirectory(target.parent);
      if (await target.exists()) {
        throw StateError('Destination appeared during move');
      }
      await staging.create();
      await _requirePlainDirectory(staging);
      for (final row in rows) {
        final input = File(p.join(source.path, row['name'] as String));
        final output = File(p.join(staging.path, row['name'] as String));
        if (row['directory'] == true) {
          await Directory(output.path).create(recursive: true);
          continue;
        }
        await output.parent.create(recursive: true);
        await _requirePlainDirectory(output.parent);
        if (await FileSystemEntity.type(output.path, followLinks: false) ==
            FileSystemEntityType.link) {
          throw StateError('Linked staging file');
        }
        // Copy restarts replace only this transaction's private staged file.
        await input.copy(output.path);
        final digest = await _hash(input);
        if (await output.length() != row['size'] ||
            await _hash(output) != digest) {
          throw FileSystemException(
              'Copied file verification failed', input.path);
        }
        row['sha256'] = digest;
        await output.setLastModified(
            DateTime.fromMicrosecondsSinceEpoch(row['modified'] as int));
      }
      await _checkInventory(source, rows, hashes: true);
      state['files'] = rows;
      await phase('staged');
    }
    if (state['phase'] == 'staged') {
      await _checkInventory(staging, rows, hashes: true);
      if (await target.exists()) {
        throw StateError('Destination appeared during move');
      }
      await phase('installing');
    }
    if (state['phase'] == 'installing') {
      await _requirePlainDirectory(target.parent);
      if (await staging.exists()) {
        if (await target.exists()) {
          throw StateError('Destination appeared during move');
        }
        await staging.rename(target.path);
      }
      await _checkInventory(target, rows, hashes: true);
      await phase('installed');
    }
    if (state['phase'] == 'installed') {
      await _checkInventory(target, rows,
          hashes: rows.any((r) => r['sha256'] != null));
      await phase('committing');
    }
    if (state['phase'] == 'committing') {
      // Data rebasing can be interrupted after changing a JSON file. Its own
      // durable journal replays those allowed documents; immutable transferred
      // media/artwork must still match before that replay is allowed to run.
      if (commitMayChange == null) {
        await _checkInventory(target, rows,
            hashes: rows.any((r) => r['sha256'] != null));
      } else {
        final current = await _inventory(target);
        final expected = {for (final row in rows) row['name']: row};
        for (final row in current) {
          final name = row['name'] as String;
          if (commitMayChange(name)) continue;
          final old = expected.remove(name);
          if (old == null ||
              old['directory'] != row['directory'] ||
              (row['directory'] != true &&
                  (old['size'] != row['size'] ||
                      old['modified'] != row['modified'] ||
                      (old['sha256'] != null &&
                          await _hash(File(p.join(target.path, name))) !=
                              old['sha256'])))) {
            throw StateError('An immutable moved entry changed during commit');
          }
        }
        if (expected.keys
            .whereType<String>()
            .any((name) => !commitMayChange(name))) {
          throw StateError(
              'An immutable moved entry disappeared during commit');
        }
      }
      await commit(source.path, target.path);
      // The commit can intentionally remap persistent documents in a moved
      // data directory. Record their delivered revision separately from the
      // original files that are still eligible to be cut.
      final delivered = await _inventory(target);
      if (rows.any((r) => r['sha256'] != null)) {
        for (final row in delivered.where((r) => r['directory'] != true)) {
          row['sha256'] =
              await _hash(File(p.join(target.path, row['name'] as String)));
        }
      }
      state['deliveredFiles'] = delivered;
      await phase('committed');
    }
    if (state['phase'] == 'committed') {
      if (await source.exists()) {
        // Verify the complete tree before cutting anything. Changed files or
        // new siblings abort; missing entries are allowed only after a restart
        // during this journal's already committed deletion phase.
        await _checkInventory(source, rows, hashes: true, allowMissing: true);
        await _checkInventory(
            target,
            (state['deliveredFiles'] as List)
                .map((v) => Map<String, dynamic>.from(v as Map))
                .toList(),
            hashes: true);
        for (final row in rows.where((r) => r['directory'] != true)) {
          final file = File(p.join(source.path, row['name'] as String));
          if (!await file.exists()) continue;
          if (await _hash(file) != row['sha256']) {
            throw StateError('Source changed before cut');
          }
          await file.delete();
        }
        final dirs = rows
            .where((r) => r['directory'] == true)
            .map((r) => r['name'] as String)
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        for (final name in dirs) {
          final directory = Directory(p.join(source.path, name));
          if (await directory.exists()) await directory.delete();
        }
        await source
            .delete(); // Empty only; never recursively delete user data.
      }
      await phase('done');
    }
    if (state['phase'] != 'done') {
      throw const FormatException('Unknown move phase');
    }
    return target.path;
  }

  Future<void> finish() async {
    if (await pending && (await read())['phase'] == 'done') {
      await journal.delete();
    }
  }

  static Future<List<Map<String, dynamic>>> _inventory(Directory root) async {
    await _requirePlainDirectory(root);
    final entries = <Map<String, dynamic>>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final stat = await entity.stat();
      if (entity is Link ||
          (entity is Directory &&
              !p.equals(
                  await entity.resolveSymbolicLinks(), entity.absolute.path))) {
        throw FileSystemException(
            'Linked folders cannot be moved', entity.path);
      }
      if (entity is! File && entity is! Directory) {
        throw StateError('Unsupported file type');
      }
      entries.add({
        'name': p.relative(entity.path, from: root.path),
        'directory': entity is Directory,
        'size': stat.size,
        'modified': stat.modified.microsecondsSinceEpoch
      });
    }
    return entries;
  }

  static Future<void> _checkInventory(
      Directory root, List<Map<String, dynamic>> expected,
      {bool hashes = false, bool allowMissing = false}) async {
    final actual = {for (final r in await _inventory(root)) r['name']: r};
    final names = expected.map((r) => r['name']).toSet();
    if (actual.keys.any((n) => !names.contains(n))) {
      throw StateError('Folder contents changed');
    }
    for (final row in expected) {
      final current = actual[row['name']];
      if (current == null) {
        if (allowMissing) continue;
        throw StateError('A moved entry is missing');
      }
      if (current['directory'] != row['directory'] ||
          (row['directory'] != true &&
              (current['size'] != row['size'] ||
                  current['modified'] != row['modified']))) {
        throw StateError('A moved file changed');
      }
      if (hashes &&
          row['directory'] != true &&
          row['sha256'] != null &&
          await _hash(File(p.join(root.path, row['name'] as String))) !=
              row['sha256']) {
        throw StateError('A moved file checksum changed');
      }
    }
  }

  static Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).single).toString();

  Future<void> _write(Map<String, dynamic> state) async {
    await journal.parent.create(recursive: true);
    final temporary = File('${journal.path}.tmp');
    await temporary.writeAsString(jsonEncode(state), flush: true);
    // Windows rename replaces files atomically; keep the previous journal on
    // platforms that reject replacement rather than removing it first.
    await temporary.rename(journal.path);
  }
}
