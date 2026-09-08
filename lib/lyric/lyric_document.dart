import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/lyric/krc.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/qrc.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Captures the existing parsed model, including word timing and translations.
/// Parser offsets have already been applied. The application offset is applied
/// only to a fresh display copy, never written back into this source snapshot.
class LyricSnapshot {
  LyricSnapshot._(this._data);
  final Map<String, dynamic> _data;

  factory LyricSnapshot.capture(Lyric lyric) => LyricSnapshot._({
        'format': lyric is PlainLyric
            ? 'plain'
            : lyric is Krc
                ? 'krc'
                : lyric is Qrc
                    ? 'qrc'
                    : 'lrc',
        if (lyric is PlainLyric) 'text': lyric.text,
        if (lyric is Lrc) 'local': lyric.source == LrcSource.local,
        'lines': [
          for (final line in lyric.lines)
            {
              'start': line.start.inMicroseconds,
              if (line is SyncLyricLine) ...{
                'length': line.length.inMicroseconds,
                'translation': line.translation,
                'words': [
                  for (final word in line.words)
                    {
                      'start': word.start.inMicroseconds,
                      'length': word.length.inMicroseconds,
                      'text': word.content,
                    },
                ],
              } else if (line is UnsyncLyricLine) ...{
                'text': line.content,
                'length': line is LrcLine ? line.length.inMicroseconds : 0,
              },
            },
        ],
      });

  static LyricSnapshot? fromJson(Object? data) {
    if (data == null) return null;
    if (data is! Map || data['lines'] is! List) {
      throw const FormatException('Invalid saved lyric');
    }
    final snapshot = LyricSnapshot._(Map<String, dynamic>.from(data));
    // Validate the complete document; do not silently drop a damaged revision.
    snapshot.toLyric();
    return snapshot;
  }

  Map<String, dynamic> toJson() =>
      jsonDecode(jsonEncode(_data)) as Map<String, dynamic>;

  Lyric toLyric({int offsetMs = 0}) {
    final format = _data['format'];
    if (format == 'plain') return PlainLyric(_data['text'] as String);
    final delta = Duration(milliseconds: offsetMs);
    final lines = <LyricLine>[];
    for (final raw in _data['lines'] as List) {
      final item = raw as Map;
      final start = Duration(microseconds: item['start'] as int) + delta;
      final length = Duration(microseconds: item['length'] as int);
      if (length.isNegative) throw const FormatException('Negative lyric span');
      if (item['words'] is List) {
        final words = <SyncLyricWord>[
          for (final word in item['words'] as List)
            QrcWord(
              Duration(microseconds: word['start'] as int) + delta,
              Duration(microseconds: word['length'] as int),
              word['text'] as String,
            ),
        ];
        lines.add(format == 'krc'
            ? KrcLine(start, length, words, item['translation'] as String?)
            : QrcLine(start, length, words, item['translation'] as String?));
      } else {
        final text = item['text'] as String;
        lines.add(
            LrcLine(start, text, isBlank: text.trim().isEmpty, length: length));
      }
    }
    return switch (format) {
      'qrc' => Qrc(lines),
      'krc' => Krc(lines),
      _ => Lrc(lines, _data['local'] == true ? LrcSource.local : LrcSource.web),
    };
  }
}

class LyricDocument {
  const LyricDocument({
    required this.trackId,
    required this.path,
    this.revision = 0,
    this.source,
    this.original,
    this.edited,
    this.originalText,
    this.editedText,
    this.locked = false,
    this.noLyrics = false,
    this.offsetMs = 0,
    this.history = const [],
  });

  final String trackId;
  final String path;
  final int revision;
  final LyricSource? source;
  final LyricSnapshot? original;
  final LyricSnapshot? edited;
  final String? originalText;
  final String? editedText;
  final bool locked;
  final bool noLyrics;
  final int offsetMs;
  // Previous user versions, without recursive history. Explicit source changes
  // and restores preserve previous work instead of replacing it irreversibly.
  final List<Map<String, dynamic>> history;

  LyricSnapshot? get effective => edited ?? original;
  String? get sourceLabel => switch (source?.source) {
        LyricSourceType.qq => 'QQ音乐',
        LyricSourceType.kugou => '酷狗音乐',
        LyricSourceType.netease => '网易云音乐',
        LyricSourceType.lrclib => 'LRCLIB',
        LyricSourceType.local => '本地',
        null => null,
      };
  Lyric? render() => noLyrics ? null : effective?.toLyric(offsetMs: offsetMs);
  String get stateLabel => noLyrics
      ? '无歌词 · 不再自动查找'
      : locked
          ? edited != null
              ? '人工修订 · 已锁定'
              : '已确认 · 已锁定'
          : effective != null
              ? '手动选定'
              : '自动匹配';

  Map<String, dynamic> toJson({bool includeHistory = true}) => {
        'trackId': trackId,
        'path': path,
        'revision': revision,
        'source': source?.toMap(),
        'original': original?.toJson(),
        'edited': edited?.toJson(),
        'originalText': originalText,
        'editedText': editedText,
        'locked': locked,
        'noLyrics': noLyrics,
        'offsetMs': offsetMs,
        if (includeHistory) 'history': history,
      };

  factory LyricDocument.fromJson(Map data) {
    final offset = data['offsetMs'] as int? ?? 0;
    if (offset.abs() > maxOffsetMs) {
      throw const FormatException('Invalid lyric offset');
    }
    final document = LyricDocument(
      trackId: data['trackId'] as String,
      path: data['path'] as String,
      revision: data['revision'] as int,
      source: data['source'] is Map
          ? LyricSource.fromMap(data['source'] as Map)
          : null,
      original: LyricSnapshot.fromJson(data['original']),
      edited: LyricSnapshot.fromJson(data['edited']),
      originalText: data['originalText'] as String?,
      editedText: data['editedText'] as String?,
      locked: data['locked'] == true,
      noLyrics: data['noLyrics'] == true,
      offsetMs: offset,
      history: [
        for (final item in data['history'] as List? ?? const [])
          Map<String, dynamic>.from(item as Map),
      ],
    );
    if (document.trackId.isEmpty ||
        document.revision < 0 ||
        (document.source != null &&
            !isLyricSourceCompatible(
              isOnline: document.path.startsWith('online://'),
              source: document.source!.source,
            ))) {
      throw const FormatException('Invalid lyric document identity/source');
    }
    return document;
  }

  static const maxOffsetMs = 10 * 60 * 1000;
}

class StaleLyricRevision implements Exception {
  const StaleLyricRevision();
  @override
  String toString() => '歌词已被另一操作修改，旧结果未覆盖当前版本，请重新打开后重试。';
}

/// One authoritative file for a user's selected document, lock and revision.
/// Saves serialize, publish only after durable success, and retain .bak.
class LyricDocumentStore extends ChangeNotifier {
  LyricDocumentStore(
      {Directory? storageDirectory, Future<void> Function()? persistIdentity})
      : _directory = storageDirectory,
        _persistIdentity = persistIdentity ??
            (storageDirectory == null
                ? () => TrackIdentityRegistry.instance.flush()
                : () async {});

  static final instance = LyricDocumentStore();
  final Directory? _directory;
  final Future<void> Function() _persistIdentity;
  final Map<String, LyricDocument> _documents = {};

  /// Derived consumers invalidate only documents successfully committed to disk.
  final changes = ValueNotifier<Set<String>>(const {});
  Iterable<LyricDocument> get documents => _documents.values;
  bool _loaded = false;
  bool _recoveredBackup = false;
  Future<void> _pending = Future.value();
  Future<File> get _file async => File(path.join(
      (_directory ?? await getAppDataDir()).path, 'lyric_documents.json'));

  LyricDocument? forAudio(Audio audio) => _documents[audio.stableTrackId];
  int revisionFor(Audio audio) => forAudio(audio)?.revision ?? 0;

  @override
  void dispose() {
    changes.dispose();
    super.dispose();
  }

  Future<T> _exclusive<T>(Future<T> Function() work) {
    final result = _pending.then((_) => work());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> load() => _exclusive(_load);
  Future<void> _load() async {
    if (_loaded) return;
    final file = await _file;
    Object? failure;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        if (await candidate.length() > 64 * 1024 * 1024) {
          throw const FormatException('Saved lyric documents exceed 64 MiB');
        }
        final data = jsonDecode(await candidate.readAsString());
        if (data is! Map || data['version'] != 1 || data['documents'] is! Map) {
          throw const FormatException('Invalid lyric document storage');
        }
        final restored = <String, LyricDocument>{};
        for (final entry in (data['documents'] as Map).entries) {
          final document = LyricDocument.fromJson(entry.value as Map);
          if (document.trackId != entry.key) {
            throw const FormatException('Lyric document identity mismatch');
          }
          restored[document.trackId] = document;
        }
        _documents.addAll(restored);
        _loaded = true;
        _recoveredBackup = candidate.path != file.path;
        return;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) throw failure;
    _loaded = true;
  }

  Future<void> _write(Map<String, LyricDocument> next,
      {bool Function()? stillCurrent}) async {
    final file = await _file;
    final text = jsonEncode({
      'version': 1,
      'documents': {
        for (final entry in next.entries) entry.key: entry.value.toJson(),
      }
    });
    if (utf8.encode(text).length > 64 * 1024 * 1024) {
      throw StateError('歌词副本超过 64 MiB 保存上限，请先备份。');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.$pid.tmp');
    final backup = File('${file.path}.bak');
    try {
      await temporary.writeAsString(text, flush: true);
      if (stillCurrent != null && !stillCurrent()) {
        throw const StaleLyricRevision();
      }
      if (_recoveredBackup && await file.exists()) {
        // Keep the failed primary for inspection and the last good backup.
        await file.rename(
            '${file.path}.corrupt.${DateTime.now().microsecondsSinceEpoch}');
      } else if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      await temporary.rename(file.path);
      final changed = <String>{
        for (final id in {..._documents.keys, ...next.keys})
          if (!identical(_documents[id], next[id])) id,
      };
      _documents
        ..clear()
        ..addAll(next);
      if (changed.isNotEmpty) changes.value = changed;
      _recoveredBackup = false;
      // A session may have changed during the atomic rename. Keep its saved
      // track document, but do not interrupt the replacement playback session.
      if (stillCurrent == null || stillCurrent()) notifyListeners();
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<LyricDocument> _change(Audio audio,
          Map<String, dynamic> Function(LyricDocument previous) transform,
          {int? expectedRevision,
          bool archive = false,
          bool Function()? stillCurrent}) =>
      _exclusive(() async {
        await _load();
        final id = audio.stableTrackId;
        if (stillCurrent != null && !stillCurrent()) {
          throw const StaleLyricRevision();
        }
        final previous = _documents[id] ??
            LyricDocument(
                trackId: id,
                path: audio.path,
                source: LYRIC_SOURCES[audio.path]);
        if (expectedRevision != null && previous.revision != expectedRevision) {
          throw const StaleLyricRevision();
        }
        await _persistIdentity();
        final map = transform(previous);
        map['trackId'] = id;
        map['path'] = audio.path;
        map['revision'] = previous.revision + 1;
        if (archive && previous.effective != null) {
          map['history'] = [
            ...previous.history,
            previous.toJson(includeHistory: false)
          ];
        }
        final next = LyricDocument.fromJson(map);
        await _write({..._documents, id: next}, stillCurrent: stillCurrent);
        return next;
      });

  Future<Set<String>> selectLocalBatch(
          List<({Audio audio, Lyric lyric, int revision})> entries,
          {bool keepOffset = true}) =>
      _exclusive(() async {
        await _load();
        if (entries.length > 16) throw ArgumentError('歌词提交每组最多 16 首');
        await _persistIdentity();
        final next = Map<String, LyricDocument>.of(_documents);
        final conflicts = <String>{};
        for (final entry in entries) {
          final audio = entry.audio, id = audio.stableTrackId;
          final old = next[id] ?? LyricDocument(trackId: id, path: audio.path);
          if (audio.isOnline ||
              audio.isCueTrack ||
              old.revision != entry.revision ||
              old.locked ||
              old.edited != null ||
              old.noLyrics) {
            conflicts.add(id);
            continue;
          }
          final map = old.toJson()
            ..['original'] = LyricSnapshot.capture(entry.lyric).toJson()
            ..['edited'] = null
            ..['editedText'] = null
            ..['originalText'] = null
            ..['source'] = null
            ..['locked'] = true
            ..['noLyrics'] = false
            ..['offsetMs'] = keepOffset ? old.offsetMs : 0
            ..['revision'] = old.revision + 1;
          if (old.effective != null)
            map['history'] = [
              ...old.history,
              old.toJson(includeHistory: false)
            ];
          next[id] = LyricDocument.fromJson(map);
        }
        if (next.entries.any((e) => !identical(_documents[e.key], e.value)))
          await _write(next);
        return conflicts;
      });

  Future<LyricDocument> select(Audio audio, Lyric lyric,
          {LyricSource? source,
          int? expectedRevision,
          bool locked = false,
          bool Function()? stillCurrent}) =>
      _change(
          audio,
          (old) => old.toJson()
            ..['source'] = source?.toMap()
            ..['original'] = LyricSnapshot.capture(lyric).toJson()
            ..['edited'] = null
            ..['originalText'] = null
            ..['editedText'] = null
            ..['locked'] = locked
            ..['noLyrics'] = false,
          expectedRevision: expectedRevision,
          stillCurrent: stillCurrent,
          archive: true);

  Future<LyricDocument> edit(Audio audio, String text,
      {Lyric? original, String? originalText, int? expectedRevision}) {
    if (audio.isOnline) throw StateError('联网音乐的歌词为只读，不能修改');
    final parsed = Lrc.fromLrcText(text, LrcSource.local, separator: '┃');
    if (parsed == null) throw const FormatException('没有识别到有效的 LRC 时间戳');
    return _change(
        audio,
        (old) => old.toJson()
          ..['original'] = old.original?.toJson() ??
              (original == null || old.edited != null
                  ? null
                  : LyricSnapshot.capture(original).toJson())
          ..['originalText'] = old.originalText ?? originalText
          ..['edited'] = LyricSnapshot.capture(parsed).toJson()
          ..['editedText'] = text
          ..['locked'] = true
          ..['noLyrics'] = false,
        expectedRevision: expectedRevision,
        archive: true);
  }

  Future<LyricDocument> setOffset(Audio audio, int milliseconds,
          {int? expectedRevision}) =>
      _change(audio, (old) => old.toJson()..['offsetMs'] = milliseconds,
          expectedRevision: expectedRevision);

  Future<LyricDocument> setLocked(Audio audio, bool locked,
          {Lyric? current, int? expectedRevision}) =>
      _change(audio, (old) {
        if (locked && old.effective == null && current == null) {
          throw StateError('当前没有可以确认的歌词');
        }
        return old.toJson()
          ..['original'] = old.original?.toJson() ??
              (current == null || old.edited != null
                  ? null
                  : LyricSnapshot.capture(current).toJson())
          ..['locked'] = locked;
      }, expectedRevision: expectedRevision);

  Future<LyricDocument> setNoLyrics(Audio audio, bool value,
          {int? expectedRevision}) =>
      _change(audio, (old) => old.toJson()..['noLyrics'] = value,
          expectedRevision: expectedRevision);

  Future<LyricDocument> restoreOriginal(Audio audio, {int? expectedRevision}) =>
      _change(audio, (old) {
        if (old.original == null) throw StateError('尚未保存原始歌词');
        return old.toJson()
          ..['edited'] = null
          ..['editedText'] = null
          ..['locked'] = true
          ..['noLyrics'] = false;
      }, expectedRevision: expectedRevision, archive: true);

  Future<LyricDocument> restoreVersion(Audio audio, int index,
          {int? expectedRevision}) =>
      _change(audio, (old) {
        final restored = Map<String, dynamic>.from(old.history[index]);
        restored['history'] = old.history;
        return restored
          ..['locked'] = true
          ..['noLyrics'] = false;
      }, expectedRevision: expectedRevision, archive: true);

  Future<void> relocatePath(String oldPath, String newPath) =>
      _exclusive(() async {
        await _load();
        final next = <String, LyricDocument>{};
        var changed = false;
        for (final entry in _documents.entries) {
          final document = entry.value;
          if (path.windows.equals(document.path, oldPath)) {
            final map = document.toJson()..['path'] = newPath;
            // Historical paths are only diagnostic; keep them in the same mapping.
            map['history'] = [
              for (final item in document.history) {...item, 'path': newPath}
            ];
            next[entry.key] = LyricDocument.fromJson(map);
            changed = true;
          } else {
            next[entry.key] = document;
          }
        }
        if (changed) await _write(next);
      });
}
