import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:flutter/foundation.dart';

class LyricSearchLine {
  LyricSearchLine(this.index, this.text, this.translation, this.start)
      : searchable = '$text\n${translation ?? ''}'.toLowerCase();
  final int index;
  final String text;
  final String? translation;

  /// Canonical time in the song/CUE segment, before the application offset.
  final Duration? start;
  final String searchable;
}

class LyricSearchSong {
  LyricSearchSong(
      this.audio, this.revision, this.source, this.offsetMs, this.lines);
  final Audio audio;
  final int revision;
  final String source;
  final int offsetMs;
  final List<LyricSearchLine> lines;

  Duration? positionFor(LyricSearchLine line) {
    final raw = line.start;
    if (raw == null) return null;
    final milliseconds = raw.inMilliseconds + offsetMs;
    return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
  }
}

class LyricSearchHit {
  const LyricSearchHit(this.song, this.lines, this.moreMatches);
  final LyricSearchSong song;
  final List<LyricSearchLine> lines;
  final bool moreMatches;
}

class LyricSearchResults {
  const LyricSearchResults(this.query, this.indexedSongs, this.hits,
      {this.limited = false});
  final String query;
  final int indexedSongs;
  final List<LyricSearchHit> hits;
  final bool limited;
}

class LyricSearchSuperseded implements Exception {
  const LyricSearchSuperseded();
}

/// Disposable, locally derived text projection. Never reads audio/directories,
/// requests a provider, or writes back to the authoritative lyric documents.
class LyricSearchIndex extends ChangeNotifier {
  LyricSearchIndex({
    required this.documents,
    required List<Audio> Function() audios,
    required int Function() libraryRevision,
    Listenable? libraryChanges,
  })  : _audios = audios,
        _libraryRevision = libraryRevision,
        _libraryChanges = libraryChanges {
    documents.changes.addListener(_documentsChanged);
    libraryChanges?.addListener(_libraryChanged);
  }

  static final instance = LyricSearchIndex(
    documents: LyricDocumentStore.instance,
    audios: () => AudioLibrary.instance.audioCollection,
    libraryRevision: () => AudioLibrary.searchRevision,
    libraryChanges: AudioLibrary.changes,
  );
  final LyricDocumentStore documents;
  final List<Audio> Function() _audios;
  final int Function() _libraryRevision;
  final Listenable? _libraryChanges;
  final _audioById = <String, Audio>{};
  final _songs = <String, LyricSearchSong>{};
  final _loaded = <String, (Lyric, String)>{};
  int _seenLibrary = -1;
  int _generation = 0;
  bool _disposed = false;
  bool _searched = false;
  int get indexedSongs => _songs.length;

  /// Called only for lyrics the normal playback flow has already loaded.
  /// A saved document (including no-lyrics) always wins over this cache.
  void rememberLoadedLocal(Audio audio, Lyric raw, {String source = '本地'}) {
    if (_disposed || audio.isOnline) return;
    final document = documents.forAudio(audio);
    if (document?.effective != null || document?.noLyrics == true) return;
    final previous = _loaded[audio.stableTrackId]?.$1;
    // Opening the searched song normally reloads its LRC. Identical content is
    // not a revision and must not cancel that very song's open-and-seek request.
    if (previous != null && _sameLyrics(previous, raw)) return;
    _loaded[audio.stableTrackId] = (raw, source);
    if (_seenLibrary != _libraryRevision()) _syncLibrary();
    _project(audio.stableTrackId);
    _changed();
  }

  bool _sameLyrics(Lyric a, Lyric b) {
    if (a.runtimeType != b.runtimeType || a.lines.length != b.lines.length) {
      return false;
    }
    for (var i = 0; i < a.lines.length; i++) {
      final left = a.lines[i], right = b.lines[i];
      if (left.start != right.start) return false;
      if (left is UnsyncLyricLine && right is UnsyncLyricLine) {
        if (left.content != right.content) return false;
      } else if (left is SyncLyricLine && right is SyncLyricLine) {
        if (left.content != right.content ||
            left.translation != right.translation) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  void _libraryChanged() {
    if (_seenLibrary == _libraryRevision()) return;
    _syncLibrary();
    _changed();
  }

  void _syncLibrary() {
    _seenLibrary = _libraryRevision();
    final next = {for (final audio in _audios()) audio.stableTrackId: audio};
    _songs.removeWhere((id, _) => !next.containsKey(id));
    _loaded.removeWhere((id, _) => !next.containsKey(id));
    final previous = Map<String, Audio>.of(_audioById);
    _audioById
      ..clear()
      ..addAll(next);
    for (final entry in next.entries) {
      if (!identical(previous[entry.key], entry.value)) _project(entry.key);
    }
  }

  void _documentsChanged() {
    for (final id in documents.changes.value) {
      // Offset-only changes retain already loaded local text. A saved source
      // or explicit no-lyrics decision supersedes that fallback.
      final audio = _audioById[id];
      final document = audio == null ? null : documents.forAudio(audio);
      if (document?.effective != null || document?.noLyrics == true) {
        _loaded.remove(id);
      }
      _project(id);
    }
    _changed();
  }

  void _changed() {
    _generation++;
    if (!_disposed) notifyListeners();
  }

  void _project(String id) {
    final audio = _audioById[id];
    if (audio == null) return;
    final document = documents.forAudio(audio);
    final raw = document?.noLyrics == true
        ? null
        : document?.effective?.toLyric() ?? _loaded[id]?.$1;
    if (raw == null) {
      _songs.remove(id);
      return;
    }
    final lines = <LyricSearchLine>[];
    if (raw is PlainLyric) {
      for (final text in raw.text.split(RegExp(r'\r?\n'))) {
        if (text.trim().isNotEmpty) {
          lines.add(LyricSearchLine(lines.length, text, null, null));
        }
      }
    } else {
      for (final line in raw.lines) {
        final text = switch (line) {
          SyncLyricLine() => line.content,
          UnsyncLyricLine() => line.content,
          _ => '',
        };
        final translation = line is SyncLyricLine ? line.translation : null;
        if (text.trim().isEmpty && (translation?.trim().isEmpty ?? true)) {
          continue;
        }
        lines.add(LyricSearchLine(lines.length, text, translation, line.start));
      }
    }
    if (lines.isEmpty) {
      _songs.remove(id);
      return;
    }
    _songs[id] = LyricSearchSong(
        audio,
        document?.revision ?? 0,
        document?.edited != null
            ? '人工修订'
            : document?.sourceLabel ?? _loaded[id]?.$2 ?? '本地',
        document?.offsetMs ?? 0,
        List.unmodifiable(lines));
  }

  bool isCurrent(LyricSearchSong song) =>
      !_disposed &&
      identical(_songs[song.audio.stableTrackId], song) &&
      documents.revisionFor(song.audio) == song.revision &&
      _audioById.containsKey(song.audio.stableTrackId);

  Future<LyricSearchResults> search(String query,
      {VoidCallback? checkCancelled,
      int maxSongs = 40,
      int maxLines = 3}) async {
    await documents.load();
    if (!_searched) {
      _searched = true;
      _seenLibrary = -1;
      _audioById.clear();
    }
    if (_seenLibrary != _libraryRevision()) _syncLibrary();
    final generation = _generation;
    void check() {
      checkCancelled?.call();
      if (_disposed || generation != _generation) {
        throw const LyricSearchSuperseded();
      }
    }

    check();
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final results = <LyricSearchHit>[];
    if (terms.isEmpty) return LyricSearchResults(query, indexedSongs, results);
    final budget = Stopwatch()..start();
    var limited = false;
    for (final song in _songs.values.toList(growable: false)) {
      final matching = <LyricSearchLine>[];
      var more = false;
      for (final line in song.lines) {
        if (terms.every(line.searchable.contains)) {
          if (matching.length < maxLines) {
            matching.add(line);
          } else {
            more = true;
            break;
          }
        }
        if (budget.elapsedMilliseconds >= 6) {
          await Future<void>.delayed(Duration.zero);
          check();
          budget.reset();
        }
      }
      if (matching.isNotEmpty) {
        if (results.length >= maxSongs) {
          limited = true;
          break;
        }
        results.add(LyricSearchHit(song, matching, more));
      }
    }
    check();
    return LyricSearchResults(query, indexedSongs, results, limited: limited);
  }

  @override
  void dispose() {
    _disposed = true;
    documents.changes.removeListener(_documentsChanged);
    _libraryChanges?.removeListener(_libraryChanged);
    super.dispose();
  }
}
