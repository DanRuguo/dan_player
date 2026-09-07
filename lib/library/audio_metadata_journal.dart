import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/library_data_migration.dart';
import 'package:path/path.dart' as p;

/// Only a confirmed native commit is written here. Recovery synchronizes app
/// documents and never retries tag writing or claims the media was rolled back.
class AudioMetadataJournal {
  AudioMetadataJournal(this.directory);
  final Directory directory;
  File get file => File(p.join(directory.path, 'metadata_committed.json'));
  Future<bool> get hasPending async =>
      await file.exists() || await File('${file.path}.tmp').exists();
  Future<void> record(
      {required String oldPath,
      required String newPath,
      required String title,
      required String artist,
      required String album}) async {
    final temp = File('${file.path}.tmp');
    await directory.create(recursive: true);
    await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'oldPath': oldPath,
          'newPath': newPath,
          'title': title,
          'artist': artist,
          'album': album
        }),
        flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<void> clear() async {
    if (await file.exists()) await file.delete();
    final temp = File('${file.path}.tmp');
    if (await temp.exists()) await temp.delete();
  }

  Future<void> recover() async {
    final temp = File('${file.path}.tmp');
    if (!await file.exists() && await temp.exists()) {
      await temp.rename(file.path);
    }
    if (!await file.exists()) return;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map ||
        value['version'] != 1 ||
        ['oldPath', 'newPath', 'title', 'artist', 'album']
            .any((key) => value[key] is! String)) {
      throw const FormatException('已写入标签的同步记录损坏；请保留文件并恢复资料备份。');
    }
    final oldPath = value['oldPath'] as String,
        newPath = value['newPath'] as String;
    final stat = await File(newPath).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FileSystemException('歌曲文件已保存，但当前不可访问；请连接来源后重试关系同步。');
    }
    final mapping =
        oldPath == newPath ? null : LibraryPathMapping(oldPath, newPath);
    Object? tags(Object? item) {
      if (item is List) return item.map(tags).toList();
      if (item is! Map) return item;
      final next = {
        for (final entry in item.entries) entry.key as String: tags(entry.value)
      };
      if (next['path'] == newPath &&
          next.containsKey('title') &&
          !next.containsKey('cue_track')) {
        next.addAll({
          'title': value['title'],
          'artist': value['artist'],
          'album': value['album'],
          'modified': stat.modified.millisecondsSinceEpoch ~/ 1000,
          'file_size': stat.size
        });
      }
      return next;
    }

    final documents = <String, Object?>{};
    for (final name in LibraryDataMigration.names) {
      final source = File(p.join(directory.path, name));
      final backup = File('${source.path}.bak');
      Object? backupRaw;
      if (await backup.exists()) {
        try {
          backupRaw = await _readDocument(backup);
          documents['$name.bak'] = tags(mapping == null
              ? backupRaw
              : remapLibraryDocument(backupRaw, mapping));
        } on FormatException {
          // An invalid historical backup must not block a healthy primary.
          // It stays untouched; the staged batch preserves the current file.
        }
      }
      if (!await source.exists()) {
        if (backupRaw == null) continue;
        // Restore the pre-commit primary first if an earlier atomic save was
        // interrupted. Replaying this journal will still apply the new path.
        await backup.copy(source.path);
      }
      Object? raw;
      try {
        raw = await _readDocument(source);
      } on FormatException {
        if (backupRaw == null) rethrow;
        raw = backupRaw;
      }
      documents[name] =
          tags(mapping == null ? raw : remapLibraryDocument(raw, mapping));
    }
    await LibraryDataMigration(directory).commitDocuments(documents);
    await clear();
  }

  static Future<Object?> _readDocument(File file) async {
    if (await file.length() > LibraryDataMigration.maxDocumentBytes) {
      throw const FormatException('待同步资料超过 128 MiB，已保留原文件。');
    }
    final text = await file.readAsString();
    if (utf8.encode(text).length > LibraryDataMigration.maxDocumentBytes) {
      throw const FormatException('待同步资料超过 128 MiB，已保留原文件。');
    }
    final value = jsonDecode(text);
    if (value is! Map && value is! List) {
      throw const FormatException('待同步资料格式错误，已保留原文件。');
    }
    return value;
  }
}
