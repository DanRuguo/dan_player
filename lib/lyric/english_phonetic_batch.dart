import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/lyric/english_lyric_phonetics.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class EnglishPhoneticBatchItem {
  const EnglishPhoneticBatchItem({required this.read});
  final Future<Lyric?> Function() read;
}

typedef EnglishPhoneticBatchScan = Future<List<EnglishPhoneticBatchItem>>
    Function(bool Function() active);

/// Explicitly started offline batch job that pre-computes English IPA caches
/// for saved lyrics without modifying authored files or foreground playback.
class EnglishPhoneticBatch extends ChangeNotifier {
  EnglishPhoneticBatch({
    this.scan,
    EnglishPhoneticProjector? projector,
    this.taskbarProgress,
  }) : _projector = projector ?? EnglishPhoneticProjector.background();

  final EnglishPhoneticBatchScan? scan;
  final TaskbarProgress? taskbarProgress;
  final EnglishPhoneticProjector _projector;
  bool running = false, cancelling = false, scanning = false;
  int total = 0, completed = 0, generated = 0, skipped = 0, failed = 0;
  String status = '开始后扫描已缓存歌词；离线批量生成，可随时取消。';
  bool _disposed = false;
  TaskbarProgressTask? _taskbar;
  bool get _active => !_disposed && running && !cancelling;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!running || cancelling) return;
    cancelling = true;
    status = '正在取消音标生成…';
    _projector.cancel();
    _taskbar?.dispose();
    _taskbar = null;
    _publish();
  }

  Future<void> start() async {
    if (_disposed || running) return;
    running = scanning = true;
    cancelling = false;
    total = completed = generated = skipped = failed = 0;
    status = '正在读取已缓存歌词…';
    _taskbar = (taskbarProgress ?? TaskbarProgress.instance).begin();
    _publish();
    try {
      final items =
          await (scan ?? scanSavedEnglishPhoneticLyrics)(() => _active);
      if (!_active) return;
      total = items.length;
      scanning = false;
      _taskbar?.update(total == 0 ? 1 : 0);
      status = '正在批量生成英语音标…';
      _publish();
      for (final item in items) {
        if (!_active) break;
        try {
          final source = await item.read();
          if (!_active) break;
          if (source == null || !hasLyricContent(source)) {
            skipped++;
          } else {
            final projection = await _projector.project(
              source,
              enabled: true,
              stillCurrent: () => _active,
            );
            if (!_active) break;
            switch (projection.result) {
              case EnglishPhoneticResult.applied:
                generated++;
              case EnglishPhoneticResult.unchanged:
                skipped++;
              case EnglishPhoneticResult.unavailable:
              case EnglishPhoneticResult.tooLarge:
                failed++;
              case EnglishPhoneticResult.stale:
                if (_active) failed++;
            }
          }
        } catch (_) {
          if (_active) failed++;
        }
        if (!_active) break;
        completed++;
        _taskbar?.update(completed / total);
        _publish();
      }
      status = cancelling ? '已取消，已生成的音标缓存会保留。' : '批量生成英语音标完成';
    } catch (_) {
      status = cancelling ? '已取消，已生成的音标缓存会保留。' : '读取缓存失败，请重试。';
    } finally {
      if (cancelling) status = '已取消，已生成的音标缓存会保留。';
      _taskbar?.dispose();
      _taskbar = null;
      running = scanning = false;
      _publish();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
    _projector.dispose();
    super.dispose();
  }
}

/// Enumerates cached lyrics without network lookup or audio file reads.
Future<List<EnglishPhoneticBatchItem>> scanSavedEnglishPhoneticLyrics(
  bool Function() active, {
  Directory? directory,
  int maximumEntries = 10000,
}) async {
  final root = directory ??
      Directory(p.join((await getAppDataDir()).path, 'cache', 'online_lyrics'));
  if (!active() || !await root.exists()) return [];
  if (await FileSystemEntity.isLink(root.path)) {
    throw const FileSystemException('Lyric cache directory is a link');
  }
  final files = <File>[];
  var visited = 0;
  await for (final entry in root.list(followLinks: false)) {
    if (!active()) return [];
    if (++visited > maximumEntries) {
      throw const FileSystemException('Lyric cache scan limit reached');
    }
    if (entry is File &&
        RegExp(r'^[0-9a-f]{64}\.json$').hasMatch(p.basename(entry.path))) {
      files.add(entry);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      EnglishPhoneticBatchItem(
        read: () async {
          if (!active() || await FileSystemEntity.isLink(file.path)) {
            return null;
          }
          final before = await file.stat();
          if (before.type != FileSystemEntityType.file ||
              before.size > OnlineLyricCache.maxEntryBytes) {
            throw const FormatException('Invalid cached lyric size');
          }
          final bytes = await file.readAsBytes();
          final after = await file.stat();
          if (!active() ||
              before.size != after.size ||
              before.modified != after.modified ||
              bytes.length != before.size) {
            return null;
          }
          return LyricSnapshot.fromJson(jsonDecode(utf8.decode(bytes)))
              ?.toLyric();
        },
      ),
  ];
}
