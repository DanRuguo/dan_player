import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/online/song_comments.dart';
import 'package:path/path.dart' as path;

/// Private, bounded snapshots of already displayed public comments. Keys use
/// exact platform IDs; a title or local file path is never a cache identity.
class SongCommentsCache {
  SongCommentsCache({
    Future<Directory> Function()? directory,
    int totalBytesLimit = maxTotalBytes,
  })  : _totalBytesLimit = totalBytesLimit,
        _directory = directory ??
            (() async => Directory(path.join(
                (await getAppDataDir()).path, 'cache', 'song_comments')));

  static final instance = SongCommentsCache();
  static const maxEntryBytes = 512 * 1024;
  static const maxTotalBytes = 32 * 1024 * 1024;
  final Future<Directory> Function() _directory;
  final int _totalBytesLimit;
  Future<void> _pendingWrite = Future.value();
  int? _knownTotalBytes;
  DateTime? _lastReconcile;

  Future<File> _file(
      SongCommentsTarget target, SongCommentSort sort, int page) async {
    final key =
        sha256.convert(utf8.encode('1:${target.identity}:${sort.name}'));
    return File(path.join((await _directory()).path, '$key', '$page.json'));
  }

  Future<SongCommentsPage?> read(
      SongCommentsTarget target, SongCommentSort sort, int page) async {
    try {
      final file = await _file(target, sort, page);
      if (!await file.exists() || await file.length() > maxEntryBytes) {
        return null;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map ||
          value['version'] != 1 ||
          value['identity'] != target.identity ||
          value['sort'] != sort.name ||
          value['page'] != page) {
        return null;
      }
      final entries = value['comments'];
      if (entries is! List || entries.length > SongCommentsService.pageSize) {
        return null;
      }
      final comments = entries.map((item) {
        if (item is! Map ||
            item['id'] is! String ||
            item['author'] is! String ||
            item['content'] is! String ||
            item['likes'] is! int ||
            item['replies'] is! List) {
          throw const FormatException('Invalid comment cache row');
        }
        final replies = item['replies'] as List;
        if (replies.length > 3) {
          throw const FormatException('Invalid comment cache replies');
        }
        final time = item['time'];
        if (time != null && time is! int) {
          throw const FormatException('Invalid comment cache time');
        }
        return SongComment(
          id: item['id'] as String,
          author: item['author'] as String,
          content: item['content'] as String,
          publishedAt: time == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(time as int),
          likeCount: item['likes'] as int,
          replies: replies.map((reply) {
            if (reply is! Map ||
                reply['author'] is! String ||
                reply['content'] is! String) {
              throw const FormatException('Invalid comment cache reply');
            }
            return SongCommentReply(
                author: reply['author'] as String,
                content: reply['content'] as String);
          }).toList(),
        );
      }).toList();
      final sorts = value['availableSorts'];
      if (sorts is! List || sorts.length > SongCommentSort.values.length) {
        return null;
      }
      final availableSorts = sorts
          .map((name) =>
              SongCommentSort.values.firstWhere((item) => item.name == name))
          .toList();
      if (value['hasMore'] is! bool || value['reachedLimit'] is! bool) {
        return null;
      }
      final total = value['total'];
      if (total != null && total is! int) return null;
      return SongCommentsPage(
        comments: comments,
        hasMore: value['hasMore'] as bool,
        page: page,
        reportedTotal: total as int?,
        reachedLimit: value['reachedLimit'] as bool,
        availableSorts: availableSorts,
      );
    } catch (_) {
      // A missing, corrupt, or read-only cache must not block comment viewing.
      return null;
    }
  }

  Future<void> write(
      SongCommentsTarget target, SongCommentSort sort, SongCommentsPage result,
      {bool replaceSort = false}) {
    // A second dialog/request can finish the same page concurrently. Keep the
    // atomic rename and size accounting in one order on Windows.
    final pending = _pendingWrite
        .then((_) => _write(target, sort, result, replaceSort: replaceSort));
    _pendingWrite = pending;
    return pending;
  }

  Future<void> _write(
      SongCommentsTarget target, SongCommentSort sort, SongCommentsPage result,
      {required bool replaceSort}) async {
    File? temporary;
    try {
      final file = await _file(target, sort, result.page);
      final bytes = utf8.encode(jsonEncode({
        'version': 1,
        'identity': target.identity,
        'sort': sort.name,
        'page': result.page,
        'hasMore': result.hasMore,
        'reachedLimit': result.reachedLimit,
        'total': result.reportedTotal,
        'availableSorts':
            result.availableSorts.map((item) => item.name).toList(),
        'comments': [
          for (final comment in result.comments)
            {
              'id': comment.id,
              'author': comment.author,
              'content': comment.content,
              'time': comment.publishedAt?.millisecondsSinceEpoch,
              'likes': comment.likeCount,
              'replies': [
                for (final reply in comment.replies)
                  {'author': reply.author, 'content': reply.content}
              ]
            }
        ],
      }));
      if (bytes.length > maxEntryBytes) return;
      await file.parent.create(recursive: true);
      final root = await _directory();
      final now = DateTime.now();
      if (_knownTotalBytes == null ||
          _lastReconcile == null ||
          now.difference(_lastReconcile!) >= const Duration(minutes: 10)) {
        _knownTotalBytes = await _scanBytes(root);
        _lastReconcile = now;
      }
      final previousBytes = await file.exists() ? await file.length() : 0;
      temporary = File(
          '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      _knownTotalBytes = _knownTotalBytes! + bytes.length - previousBytes;
      if (replaceSort && result.page == 0) {
        await for (final entry in file.parent.list(followLinks: false)) {
          if (entry is File &&
              entry.path.endsWith('.json') &&
              entry.path != file.path) {
            final size = await entry.length();
            await entry.delete();
            _knownTotalBytes = _knownTotalBytes! - size;
          }
        }
      }
      if (_knownTotalBytes! > _totalBytesLimit) {
        await _prune(root, file.path);
      }
    } catch (_) {
      _knownTotalBytes = null;
      // The fetched page is still usable when storage is unavailable.
    } finally {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<int> _scanBytes(Directory root) async {
    var bytes = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File && entry.path.endsWith('.json')) {
        bytes += await entry.length();
      }
    }
    return bytes;
  }

  Future<void> _prune(Directory root, String keep) async {
    final entries = <(File, FileStat)>[];
    var size = 0;
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      final stat = await entry.stat();
      size += stat.size;
      entries.add((entry, stat));
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in entries) {
      if (size <= _totalBytesLimit) break;
      if (file.path == keep) continue;
      await file.delete();
      size -= stat.size;
    }
    _knownTotalBytes = size;
    _lastReconcile = DateTime.now();
  }
}
