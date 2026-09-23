import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'package:dan_player/lyric/online_lyric_cache.dart';
import 'package:dan_player/music_matcher.dart';
import 'package:dan_player/play_service/lyric_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// An explicit user job. It writes only the lyric cache and stable identities,
/// never music files, the library index or a user's selected lyric document.
class LyricCacheBatch extends ChangeNotifier {
  LyricCacheBatch(
      {this.scan, this.hasSaved, this.fetchAndCache, this.cache, this.lookup});
  static final instance = LyricCacheBatch();
  final OnlineLyricCache? cache;
  final Future<Lyric?> Function(Audio audio, bool Function() active)? lookup;
  final Future<List<Audio>> Function(String folder, bool Function() active)?
      scan;
  final Future<bool> Function(Audio audio)? hasSaved;
  final Future<bool> Function(Audio audio, bool Function() active)?
      fetchAndCache;
  bool running = false;
  bool cancelling = false;
  bool scanning = false;
  int total = 0,
      completed = 0,
      saved = 0,
      skipped = 0,
      unmatched = 0,
      instrumental = 0,
      failed = 0;
  String currentTitle = '';
  String? folder;
  String status = '选择文件夹后开始，只缓存缺失的歌词。';
  bool get _active => running && !cancelling;

  void cancel() {
    if (!running || cancelling) return;
    cancelling = true;
    status = '正在取消，等待当前请求结束…';
    notifyListeners();
  }

  Future<void> start(String selected) async {
    if (running) return;
    running = true;
    cancelling = false;
    scanning = true;
    folder = selected;
    total = completed = saved = skipped = unmatched = instrumental = failed = 0;
    currentTitle = '';
    status = '正在读取已导入的歌曲…';
    notifyListeners();
    try {
      final tracks = await (scan ?? _scan)(selected, () => _active);
      total = tracks.length;
      scanning = false;
      for (final audio in tracks) {
        if (!_active) break;
        currentTitle = audio.title;
        status = '正在匹配并缓存歌词…';
        notifyListeners();
        try {
          final existing = await (hasSaved ?? _hasSaved)(audio);
          if (!_active) break;
          if (existing) {
            skipped++;
          } else if (_active) {
            final success =
                await (fetchAndCache ?? _fetchAndCache)(audio, () => _active);
            if (!_active) break;
            success ? saved++ : unmatched++;
          }
        } on InstrumentalLyric {
          if (_active) instrumental++;
        } catch (_) {
          if (_active) failed++;
        }
        if (!_active) break;
        completed++;
        notifyListeners();
      }
      status = cancelling ? '已取消，已缓存的歌词会保留。' : '批量缓存完成';
    } catch (_) {
      status = cancelling ? '已取消，已缓存的歌词会保留。' : '读取失败，请重新选择已导入的文件夹。';
    } finally {
      running = false;
      scanning = false;
      currentTitle = '';
      notifyListeners();
    }
  }

  static List<String> get importedFolders => ({
        ...AudioLibrary.instance.scanRoots,
        ...AudioLibrary.instance.folders.map((folder) => folder.path),
      }.toList()
        ..sort());

  static List<Audio> selectImportedTracks(
      String folder, List<String> folders, Iterable<Audio> tracks) {
    String normalized(String value) =>
        path.normalize(path.absolute(value)).toLowerCase();
    final selected = normalized(folder);
    if (!folders.any((entry) => normalized(entry) == selected)) {
      throw ArgumentError('Folder is not imported');
    }
    return {
      for (final audio in tracks)
        if (audio.isLocal &&
            (normalized(path.dirname(audio.localFilePath)) == selected ||
                path.isWithin(selected, normalized(audio.localFilePath))))
          audio.path: audio,
    }.values.toList();
  }

  Future<List<Audio>> _scan(
          String folder, bool Function() active) async =>
      active()
          ? selectImportedTracks(
              folder, importedFolders, AudioLibrary.instance.audioCollection)
          : [];

  Future<bool> _hasSaved(Audio audio) async {
    final document = LyricDocumentStore.instance.forAudio(audio);
    if (document?.noLyrics == true || document?.effective != null) return true;
    if (await Lrc.fromAudioPath(audio) != null) return true;
    final source = document?.source ?? LYRIC_SOURCES[audio.path];
    if (source != null &&
        await readCachedOnlineLyric(audio, source: source) != null) {
      return true;
    }
    return await readCachedOnlineLyric(audio) != null;
  }

  Future<bool> _fetchAndCache(Audio audio, bool Function() active) async {
    final storage = cache ?? OnlineLyricCache.instance;
    final identity = onlineLyricCacheIdentity(audio);
    final lyric = await storage.resolve(identity, () async {
      if (!active() || await (hasSaved ?? _hasSaved)(audio)) return null;
      final result = await (lookup ??
          ((audio, active) =>
              getMostMatchedLyric(audio, stillCurrent: active)))(audio, active);
      // A user edit while matching must win; cancellation must not write late.
      if (!active() ||
          LyricDocumentStore.instance.forAudio(audio)?.effective != null ||
          LyricDocumentStore.instance.forAudio(audio)?.noLyrics == true) {
        return null;
      }
      return result;
    });
    if (lyric == null) return false;
    // Playback may use a downloaded lyric even if saving fails. A batch job
    // must not count it as cached unless it can actually be read back.
    if (await storage.read(identity) == null) {
      throw StateError('Lyric cache write failed');
    }
    return true;
  }
}
