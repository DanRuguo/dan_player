import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/japanese_lyric_readings.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class JapaneseReadingBatchItem {
  const JapaneseReadingBatchItem({
    required this.read,
    this.language,
  });
  final Future<Lyric?> Function() read;
  final String? language;
}

typedef JapaneseReadingBatchScan = Future<List<JapaneseReadingBatchItem>>
    Function(bool Function() active);

/// An explicitly started job. It reads disposable lyric snapshots and
/// writes derived readings through a background projector. Author documents,
/// source lyrics, audio tags and foreground playback state remain untouched.
class JapaneseReadingBatch extends ChangeNotifier {
  JapaneseReadingBatch({
    this.scan,
    JapaneseReadingProjector? projector,
    this.taskbarProgress,
  }) : _projector = projector ?? JapaneseReadingProjector.background();

  final JapaneseReadingBatchScan? scan;
  final TaskbarProgress? taskbarProgress;
  final JapaneseReadingProjector _projector;
  bool running = false, cancelling = false, scanning = false;
  int total = 0, completed = 0, generated = 0, skipped = 0, failed = 0;
  String status = '开始后扫描已缓存歌词；可随时取消。';
  bool _disposed = false;
  TaskbarProgressTask? _taskbar;
  bool get _active => !_disposed && running && !cancelling;

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    if (!running || cancelling) return;
    cancelling = true;
    status = '正在取消假名生成…';
    _projector.cancel();
    _taskbar?.dispose();
    _taskbar = null;
    _publish();
  }

  Future<void> start({
    JapaneseReadingRequestMode mode = JapaneseReadingRequestMode.automatic,
  }) async {
    if (_disposed || running) return;
    running = scanning = true;
    cancelling = false;
    total = completed = generated = skipped = failed = 0;
    status = '正在读取已缓存歌词…';
    _taskbar = (taskbarProgress ?? TaskbarProgress.instance).begin();
    _publish();
    var missingDictionary = false;
    try {
      final items =
          await (scan ?? scanSavedJapaneseReadingLyrics)(() => _active);
      if (!_active) return;
      total = items.length;
      scanning = false;
      _taskbar?.update(total == 0 ? 1 : 0);
      status = '正在批量生成日语假名…';
      _publish();
      for (final item in items) {
        if (!_active) break;
        try {
          final source = await item.read();
          if (!_active) break;
          if (source == null || !hasLyricContent(source)) {
            skipped++;
          } else {
            final projection = await _projector.project(source,
                language: item.language,
                enabled: true,
                requestMode: mode,
                stillCurrent: () => _active);
            if (!_active) break;
            switch (projection.result) {
              case JapaneseReadingResult.applied:
                generated++;
              case JapaneseReadingResult.unchanged:
                skipped++;
              case JapaneseReadingResult.dictionaryMissing:
                missingDictionary = true;
              case JapaneseReadingResult.unavailable:
              case JapaneseReadingResult.tooLarge:
                failed++;
              case JapaneseReadingResult.stale:
                if (_active) failed++;
            }
          }
        } catch (_) {
          if (_active) failed++;
        }
        if (!_active || missingDictionary) break;
        completed++;
        _taskbar?.update(completed / total);
        _publish();
      }
      status = missingDictionary
          ? '需要日语假名字典组件'
          : cancelling
              ? '已取消，已生成的假名缓存会保留。'
              : '批量生成日语假名完成';
    } catch (_) {
      status = cancelling ? '已取消，已生成的假名缓存会保留。' : '读取缓存失败，请重试。';
    } finally {
      if (cancelling) status = '已取消，已生成的假名缓存会保留。';
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

/// Enumerates fixed cache files without network lookup, source promotion or
/// music-file reads. Metadata already in the library assists all-Han Japanese
/// lyrics; unassociated snapshots use the projector's conservative kana gate.
Future<List<JapaneseReadingBatchItem>> scanSavedJapaneseReadingLyrics(
    bool Function() active,
    {Directory? directory,
    Iterable<Audio>? tracks,
    int maximumEntries = 10000}) async {
  final root = directory ??
      Directory(p.join((await getAppDataDir()).path, 'cache', 'online_lyrics'));
  if (!active() || !await root.exists()) return [];
  if (await FileSystemEntity.isLink(root.path)) {
    throw const FileSystemException('Lyric cache directory is a link');
  }
  final languages = <String, String>{};
  var trackCount = 0;
  for (final audio in tracks ?? AudioLibrary.instance.audioCollection) {
    if (!active()) return [];
    if (isJapaneseReadingLanguage(audio.language)) {
      final id = audio.isOnline
          ? audio.path
          : TrackIdentityRegistry.instance.resolvePath(audio.path);
      if (id != null) {
        for (final source in <LyricSource?>[
          null,
          for (final type in LyricSourceType.values) LyricSource(type),
        ]) {
          final key =
              sha256.convert(utf8.encode(jsonEncode([2, id, source?.toMap()])));
          languages['$key.json'] = audio.language!;
        }
      }
    }
    if (++trackCount % 64 == 0) await Future<void>.delayed(Duration.zero);
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
      JapaneseReadingBatchItem(
          language: languages[p.basename(file.path)],
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
          }),
  ];
}
