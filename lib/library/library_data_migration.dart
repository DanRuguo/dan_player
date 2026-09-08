import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/library/cue_sheet.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:path/path.dart' as p;

/// An explicit location change, never an instruction to move/delete media.
class LibraryPathMapping {
  LibraryPathMapping(String from, String to)
      : from = p.windows.normalize(from.trim()),
        to = p.windows.normalize(to.trim()) {
    for (final value in [this.from, this.to]) {
      if (!p.windows.isAbsolute(value) ||
          p.windows.isRootRelative(value) ||
          RegExp(r'[\x00-\x1f]').hasMatch(value)) {
        throw const FormatException('请选择完整的旧目录和新目录。');
      }
    }
    if (key(this.from) == key(this.to) ||
        p.windows.isWithin(key(this.from), key(this.to)) ||
        p.windows.isWithin(key(this.to), key(this.from))) {
      throw const FormatException('旧目录和新目录不能相同或互相包含。');
    }
  }
  final String from, to;
  static String key(String value) => p.windows.normalize(value).toLowerCase();
  String apply(String value) {
    if (value.startsWith('cue://track/')) {
      final rest = value.substring('cue://track/'.length);
      final slash = rest.lastIndexOf('/');
      if (slash < 0) return value;
      final before = Uri.decodeComponent(rest.substring(0, slash));
      final after = apply(before);
      return before == after
          ? value
          : 'cue://track/${Uri.encodeComponent(key(after))}${rest.substring(slash)}';
    }
    if (!p.windows.isAbsolute(value) || value.contains('\n')) return value;
    final normalized = key(value), root = key(from);
    if (normalized == root) return to;
    if (!p.windows.isWithin(root, normalized)) return value;
    return p.windows
        .join(to, p.windows.relative(p.windows.normalize(value), from: from));
  }

  Map<String, String> toJson() => {'from': from, 'to': to};
}

/// Path fields and path-keyed legacy stores retain their ordering and duplicate
/// occurrences. Stable IDs and arbitrary text never become new identities.
Object? remapLibraryDocument(Object? value, LibraryPathMapping mapping) {
  if (value is String) return mapping.apply(value);
  if (value is List) {
    return [for (final item in value) remapLibraryDocument(item, mapping)];
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = mapping.apply(entry.key as String);
      if (result.containsKey(key)) {
        throw const FormatException('路径映射产生重复关联，请先处理冲突。');
      }
      result[key] = const {
        'originalText',
        'editedText',
        'original',
        'edited',
        'text',
        'translation',
        'content',
        'aliases',
        'title',
        'artist',
        'album',
        'name',
        'composer',
        'tags',
        'album_artist',
      }.contains(key)
          ? entry.value
          : remapLibraryDocument(entry.value, mapping);
    }
    // Identity aliases remain useful to readers holding an old reference.
    if (value['trackId'] is String &&
        value['path'] is String &&
        value['path'] != result['path']) {
      result['aliases'] = {
        ...?((value['aliases'] as List?)?.whereType<String>()),
        value['path'] as String,
      }.toList();
    }
    return result;
  }
  return value;
}

class LibraryMigrationCancelled implements Exception {
  const LibraryMigrationCancelled();
}

class LibraryRelocationPreview {
  const LibraryRelocationPreview(
      {required this.mapping,
      required this.matches,
      required this.missing,
      required this.conflicts,
      required this.examples});
  final LibraryPathMapping mapping;
  final int matches, missing;
  final List<String> conflicts;
  final List<(String, String)> examples;
  bool get canApply => matches > 0 && missing == 0 && conflicts.isEmpty;
}

/// One durable batch across the existing JSON stores. Scheduling only records
/// intent; startup snapshots the latest flushed state before any loader runs.
/// A failed commit is replayed from immutable staged files, never rescanned.
class LibraryDataMigration {
  LibraryDataMigration(this.directory, {this.afterReplace});
  final Directory directory;
  final Future<void> Function(int count)? afterReplace;
  static const maxDocumentBytes = 128 * 1024 * 1024;
  static const _probeTimeout = Duration(seconds: 3);
  static const names = <String>{
    'index.json',
    'track_identities.json',
    'playlists.json',
    'collections.json',
    'custom_audio_order.json',
    'playback_state.json',
    'playback_statistics.json',
    'playback_statistics.pre-track-id-v1.json',
    'playback_bookmarks.json',
    'track_resume.json',
    'personal_library.json',
    'named_queues.json',
    'eq_presets.json',
    'smart_playlists.json',
    'lyric_source.json',
    'lyric_documents.json',
    'song_comment_associations.json',
    'category_covers.json',
    'online_library.json',
    'settings.json',
    'app_preference.json',
    'library_health.json',
  };
  File get _pending => File(p.join(directory.path, 'library_migration.json'));
  File get _latest =>
      File(p.join(directory.path, 'library_migration_last.json'));
  static bool _allowed(String name) =>
      names.contains(name) ||
      (name.endsWith('.bak') &&
          names.contains(name.substring(0, name.length - 4)));
  Directory _batch(String id) {
    if (!RegExp(r'^\d+-\d+$').hasMatch(id)) {
      throw const FormatException('无效的迁移批次。');
    }
    return Directory(p.join(directory.path, 'library_migrations', id));
  }

  static Future<void> _atomic(File file, List<int> bytes) async {
    if (bytes.length > maxDocumentBytes) {
      throw const FormatException('迁移资料超过 128 MiB，请先备份并检查文件。');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.migration-tmp');
    await temp.writeAsBytes(bytes, flush: true);
    // The durable batch can replay after interruption between removal and rename.
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  static Future<void> _json(File file, Object value) =>
      _atomic(file, utf8.encode(jsonEncode(value)));
  static Future<Map<String, dynamic>> _read(File file) async {
    final value = jsonDecode(utf8.decode(await _readBytes(file)));
    if (value is! Map<String, dynamic>) throw const FormatException('迁移记录损坏。');
    return value;
  }

  static Future<List<int>> _readBytes(File file) async {
    final handle = await file.open();
    try {
      final length = await handle.length();
      if (length > maxDocumentBytes) {
        throw const FormatException('迁移资料超过 128 MiB，原始文件已保留。');
      }
      final bytes = await handle.read(length + 1);
      if (bytes.length > maxDocumentBytes) {
        throw const FormatException('迁移资料读取期间超过 128 MiB。');
      }
      return bytes;
    } finally {
      await handle.close();
    }
  }

  Future<bool> get hasPending async =>
      await _pending.exists() ||
      await File('${_pending.path}.migration-tmp').exists();

  Future<LibraryRelocationPreview> preview(LibraryPathMapping mapping,
      {bool Function()? cancelled}) async {
    void checkCancelled() {
      if (cancelled?.call() == true) throw const LibraryMigrationCancelled();
    }

    checkCancelled();
    final index = await _read(File(p.join(directory.path, 'index.json')));
    checkCancelled();
    final rows = <Map>[];
    for (final folder in (index['folders'] as List)) {
      rows.addAll((folder['audios'] as List).whereType<Map>());
    }
    final occupied = {
      for (final row in rows) LibraryPathMapping.key(row['path'] as String)
    };
    final targets = <String>{};
    final conflicts = <String>[];
    final examples = <(String, String)>[];
    final candidates = <(Map, String, CueTrackReference?)>[];
    for (var index = 0; index < rows.length; index++) {
      checkCancelled();
      final row = rows[index];
      final before = row['path'] as String, after = mapping.apply(before);
      final cue = row['cue_track'] is Map
          ? CueTrackReference.fromMap(row['cue_track'] as Map)
          : null;
      if (before == after &&
          (cue == null ||
              (mapping.apply(cue.sourcePath) == cue.sourcePath &&
                  mapping.apply(cue.cuePath) == cue.cuePath))) {
        continue;
      }
      candidates.add((row, after, cue));
      if (examples.length < 8) examples.add((before, after));
      if (index % 128 == 0) await Future<void>.delayed(Duration.zero);
    }
    final matches = candidates.length;
    var missing = 0;
    LibraryRelocationPreview result() => LibraryRelocationPreview(
        mapping: mapping,
        matches: matches,
        missing: missing,
        conflicts: conflicts,
        examples: examples);
    if (matches == 0) return result();
    try {
      final root = await File(mapping.to).stat().timeout(_probeTimeout);
      checkCancelled();
      if (root.type != FileSystemEntityType.directory) {
        missing = matches;
        return result();
      }
    } on LibraryMigrationCancelled {
      rethrow;
    } catch (_) {
      checkCancelled();
      missing = matches;
      return result();
    }
    final cueDocuments = <String, CueDocument>{};
    for (var index = 0; index < candidates.length; index++) {
      checkCancelled();
      final (row, after, cue) = candidates[index];
      final before = row['path'] as String;
      final targetKey = LibraryPathMapping.key(after);
      if (!targets.add(targetKey) ||
          (after != before && occupied.contains(targetKey))) {
        if (conflicts.length < 20) conflicts.add('目标已在曲库中：$after');
        continue;
      }
      try {
        final target = cue == null ? after : mapping.apply(cue.sourcePath);
        final info = await File(target).stat().timeout(_probeTimeout);
        checkCancelled();
        if (info.type != FileSystemEntityType.file) {
          missing++;
          continue;
        }
        final expectedSize = row['file_size'];
        if (expectedSize is num &&
            expectedSize > 0 &&
            info.size != expectedSize) {
          if (conflicts.length < 20) conflicts.add('文件大小不同，请核对：$target');
        }
        if (cue != null) {
          final cuePath = mapping.apply(cue.cuePath);
          final document = cueDocuments[cuePath] ??=
              await readCueFile(File(cuePath)).timeout(_probeTimeout);
          checkCancelled();
          final matched = document.entries
              .where((entry) => entry.reference.number == cue.number)
              .toList();
          if (matched.length != 1 ||
              LibraryPathMapping.key(matched.single.reference.sourcePath) !=
                  LibraryPathMapping.key(target) ||
              matched.single.reference.startFrame != cue.startFrame ||
              matched.single.reference.endFrame != cue.endFrame) {
            if (conflicts.length < 20) {
              conflicts.add('CUE 轨号、音频来源或分轨边界已变化：$cuePath');
            }
          }
        }
      } on LibraryMigrationCancelled {
        rethrow;
      } on TimeoutException {
        // A disconnected target cannot incur another three-second wait for
        // every remaining row. The whole mapping remains uncommitted.
        missing += candidates.length - index;
        break;
      } catch (_) {
        checkCancelled();
        missing++;
      }
      if (index % 128 == 0) await Future<void>.delayed(Duration.zero);
    }
    checkCancelled();
    return result();
  }

  Future<void> schedule(LibraryPathMapping mapping) async {
    await _requireMetadataSyncComplete();
    if (await hasPending) throw const FormatException('已有待重启应用的迁移，请先完成或取消。');
    final checked = await preview(mapping);
    if (!checked.canApply) throw const FormatException('映射包含缺失文件或冲突，请重新预览。');
    await _json(_pending, {
      'version': 1,
      'id': '${DateTime.now().microsecondsSinceEpoch}-$pid',
      'phase': 'pending',
      'mapping': mapping.toJson()
    });
  }

  Future<void> cancelPending() async {
    if (!await _pending.exists()) return;
    if ((await _read(_pending))['phase'] != 'pending') {
      throw const FormatException('迁移已经开始，请使用恢复入口。');
    }
    await _pending.delete();
  }

  Future<void> scheduleRestore() async {
    await _requireMetadataSyncComplete();
    if (await hasPending) throw const FormatException('请先处理当前迁移。');
    final latest = await _read(_latest);
    final batch = _batch(latest['id'] as String);
    if (!await File(p.join(batch.path, 'manifest.json')).exists()) {
      throw const FormatException('未找到可恢复的迁移快照。');
    }
    await _json(_pending, {
      'version': 1,
      'id': latest['id'],
      'phase': 'restoring',
      'manifestSha256': latest['manifestSha256'],
    });
  }

  Future<void> _requireMetadataSyncComplete() async {
    for (final name in [
      'metadata_committed.json',
      'metadata_committed.json.tmp'
    ]) {
      if (await File(p.join(directory.path, name)).exists()) {
        throw const FormatException('歌曲标签已保存但关系同步尚未完成，请先重启播放器完成同步。');
      }
    }
  }

  /// Used by recovery of a confirmed native tag commit. All replacements are
  /// prepared before any file is changed; restart uses the same replay path.
  Future<void> commitDocuments(Map<String, Object?> replacements) async {
    if (await hasPending) await recover();
    if (replacements.keys.any((name) => !_allowed(name))) {
      throw const FormatException('无效的关系同步文件。');
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    final batch = _batch(id);
    final files = <Map<String, Object>>[];
    for (final entry in replacements.entries) {
      final file = File(p.join(directory.path, entry.key));
      if (!await file.exists()) continue;
      final before = await _readBytes(file);
      final after = utf8.encode(jsonEncode(entry.value));
      await _atomic(File(p.join(batch.path, 'before', entry.key)), before);
      await _atomic(File(p.join(batch.path, 'after', entry.key)), after);
      files.add({
        'name': entry.key,
        'before': sha256.convert(before).toString(),
        'after': sha256.convert(after).toString()
      });
    }
    final manifestFile = File(p.join(batch.path, 'manifest.json'));
    await _json(
        manifestFile, {'version': 1, 'id': id, 'files': files, 'absent': []});
    await _json(_pending, {
      'version': 1,
      'id': id,
      'phase': 'prepared',
      'keepLatest': true,
      'manifestSha256':
          sha256.convert(await _readBytes(manifestFile)).toString(),
    });
    await recover();
  }

  Future<void> recover() async {
    // A crash during replacement of the tiny intent record must not hide it.
    final temp = File('${_pending.path}.migration-tmp');
    if (!await _pending.exists() && await temp.exists()) {
      await temp.rename(_pending.path);
    }
    if (!await _pending.exists()) return;
    var intent = await _read(_pending);
    if (intent['version'] != 1) throw const FormatException('不支持此迁移记录版本。');
    final batch = _batch(intent['id'] as String);
    final manifestFile = File(p.join(batch.path, 'manifest.json'));
    if (intent['phase'] == 'pending') {
      final raw = intent['mapping'] as Map;
      final mapping =
          LibraryPathMapping(raw['from'] as String, raw['to'] as String);
      if (!(await preview(mapping)).canApply) {
        throw const FormatException('新目录的文件已变化或不可访问，迁移尚未开始，原数据保留。');
      }
      final records = <Map<String, Object>>[];
      final absent = <String>[];
      for (final name in [
        for (final item in names) ...[item, '$item.bak']
      ]) {
        final source = File(p.join(directory.path, name));
        if (!await source.exists()) {
          absent.add(name);
          continue;
        }
        final bytes = await _readBytes(source);
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } catch (_) {
          // Historical .bak can be invalid while the primary is healthy.
          if (name.endsWith('.bak')) {
            await _atomic(File(p.join(batch.path, 'before', name)), bytes);
            await _atomic(File(p.join(batch.path, 'after', name)), bytes);
            records.add({
              'name': name,
              'before': sha256.convert(bytes).toString(),
              'after': sha256.convert(bytes).toString()
            });
            continue;
          }
          throw FormatException('$name 无法读取，迁移已停止，原数据未修改。');
        }
        final after =
            utf8.encode(jsonEncode(remapLibraryDocument(decoded, mapping)));
        await _atomic(File(p.join(batch.path, 'before', name)), bytes);
        await _atomic(File(p.join(batch.path, 'after', name)), after);
        records.add({
          'name': name,
          'before': sha256.convert(bytes).toString(),
          'after': sha256.convert(after).toString()
        });
      }
      await _json(manifestFile, {
        'version': 1,
        'id': intent['id'],
        'files': records,
        'absent': absent
      });
      intent = {
        ...intent,
        'phase': 'prepared',
        'manifestSha256':
            sha256.convert(await _readBytes(manifestFile)).toString()
      };
      await _json(_pending, intent);
    }
    if (!const {'prepared', 'restoring'}.contains(intent['phase'])) {
      throw const FormatException('迁移阶段无效，请保留当前资料并恢复备份。');
    }
    await _install(batch, intent['phase'] == 'restoring' ? 'before' : 'after',
        manifestHash: intent['manifestSha256'] as String?);
    if (intent['keepLatest'] != true) {
      await _json(_latest, {
        'version': 1,
        'id': intent['id'],
        'manifestSha256': intent['manifestSha256'],
        'result': intent['phase'] == 'restoring' ? 'restored' : 'completed'
      });
    }
    await _pending.delete();
  }

  Future<void> _install(Directory batch, String side,
      {required String? manifestHash}) async {
    final manifestBytes =
        await _readBytes(File(p.join(batch.path, 'manifest.json')));
    if (manifestHash == null ||
        sha256.convert(manifestBytes).toString() != manifestHash) {
      throw const FormatException('迁移快照清单校验失败，已保留现场。');
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes));
    if (manifest is! Map ||
        manifest['version'] != 1 ||
        manifest['id'] != p.basename(batch.path) ||
        manifest['files'] is! List ||
        manifest['absent'] is! List) {
      throw const FormatException('迁移快照清单损坏。');
    }
    final payload = <String, List<int>>{};
    final absent = <String>{};
    for (final value in manifest['absent'] as List) {
      if (value is! String || !_allowed(value) || !absent.add(value)) {
        throw const FormatException('迁移快照缺省文件记录无效。');
      }
    }
    var totalBytes = 0;
    // Validate every staged file before touching any authoritative document.
    for (final row in manifest['files'] as List) {
      final name = row['name'] as String;
      if (!_allowed(name) ||
          payload.containsKey(name) ||
          absent.contains(name)) {
        throw const FormatException('迁移文件名无效。');
      }
      final bytes = await _readBytes(File(p.join(batch.path, side, name)));
      totalBytes += bytes.length;
      if (totalBytes > 512 * 1024 * 1024) {
        throw const FormatException('迁移快照超过 512 MiB，请保留备份并分批处理。');
      }
      if (sha256.convert(bytes).toString() != row[side]) {
        throw FormatException('$name 快照校验失败，已保留现场。');
      }
      payload[name] = bytes;
    }
    var count = 0;
    if (side == 'before') {
      // A file created since the snapshot cannot remain alongside old paths.
      // Preserve it inside this batch, instead of deleting new user work.
      for (final name in absent) {
        final current = File(p.join(directory.path, name));
        if (!await current.exists()) continue;
        final displaced = Directory(p.join(batch.path, 'displaced'));
        await displaced.create(recursive: true);
        var destination = File(p.join(displaced.path, name));
        if (await destination.exists()) {
          destination = File(
              '${destination.path}.${DateTime.now().microsecondsSinceEpoch}');
        }
        await current.rename(destination.path);
        await afterReplace?.call(++count);
      }
    }
    for (final entry in payload.entries) {
      await _atomic(File(p.join(directory.path, entry.key)), entry.value);
      await afterReplace?.call(++count);
    }
  }

  /// Before loaders run, roll back the entire batch (including counters), not
  /// an arbitrary subset of files. Media locations themselves never change.
  Future<void> restorePrevious() async {
    final record = await _read(await _pending.exists() ? _pending : _latest);
    if (record['phase'] == 'pending') {
      await cancelPending();
      return;
    }
    _batch(record['id'] as String);
    await _json(_pending, {
      'version': 1,
      'id': record['id'],
      'phase': 'restoring',
      'manifestSha256': record['manifestSha256'],
    });
    await recover();
  }
}
