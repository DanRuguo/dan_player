import 'dart:collection';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:pinyin/pinyin.dart';

/// A revision-aware search index for raw text, full pinyin and initials.
class AudioSearchIndex {
  AudioSearchIndex._();

  static final AudioSearchIndex instance = AudioSearchIndex._();

  List<_AudioEntry> _audioEntries = const [];
  List<_NameEntry<Artist>> _artistEntries = const [];
  List<_NameEntry<Album>> _albumEntries = const [];

  int _builtRevision = -1;
  Future<void>? _building;

  bool get _isStale => _builtRevision != AudioLibrary.searchRevision;

  Future<void> ensureBuilt() async {
    // A library mutation can supersede a chunked build. Keep concurrent callers
    // on the same work, then retry against the latest structural revision.
    while (_isStale) {
      final active = _building;
      if (active != null) {
        await active;
        continue;
      }
      final build = _buildChunked();
      _building = build;
      try {
        await build;
      } finally {
        if (identical(_building, build)) _building = null;
      }
    }
  }

  void ensureBuiltSync() {
    if (!_isStale) return;
    _buildSync();
  }

  void _commit({
    required int revision,
    required List<_AudioEntry> audios,
    required List<_NameEntry<Artist>> artists,
    required List<_NameEntry<Album>> albums,
  }) {
    // Replace snapshots, so a yielding query never walks a cleared/rebuilt list.
    _audioEntries = audios;
    _artistEntries = artists;
    _albumEntries = albums;
    _builtRevision = revision;
    // Entries retain the shared keys they need. The interning map exists only
    // to avoid repeating pinyin work while a snapshot is being assembled.
    _SearchKeys.clearCache();
  }

  int get debugCachedSearchKeyCount => _SearchKeys.cachedCount;

  int get debugSearchKeyCacheLimit => _SearchKeys.cacheLimit;

  void _buildSync() {
    final library = AudioLibrary.instance;
    final revision = AudioLibrary.searchRevision;
    _commit(
      revision: revision,
      audios: [for (final audio in library.audioCollection) _AudioEntry(audio)],
      artists: [
        for (final artist in library.artistCollection.values)
          _NameEntry(artist, artist.name)
      ],
      albums: [
        for (final album in library.albumCollection.values)
          _NameEntry(album, album.name)
      ],
    );
  }

  Future<void> _buildChunked() async {
    // A changes listener must return control to the current frame before even
    // the first batch performs pinyin normalization.
    await Future<void>.delayed(Duration.zero);
    final library = AudioLibrary.instance;
    final revision = AudioLibrary.searchRevision;
    final audios = List<Audio>.of(library.audioCollection);
    final artists = List<Artist>.of(library.artistCollection.values);
    final albums = List<Album>.of(library.albumCollection.values);
    final entries = <_AudioEntry>[];

    const chunkSize = 400;
    for (var i = 0; i < audios.length; i += chunkSize) {
      final end = min(i + chunkSize, audios.length);
      for (var j = i; j < end; j++) {
        entries.add(_AudioEntry(audios[j]));
      }
      if (AudioLibrary.searchRevision != revision) return;
      if (end < audios.length) await Future<void>.delayed(Duration.zero);
    }

    final artistEntries =
        await _buildNamesChunked(artists, (artist) => artist.name, revision);
    if (AudioLibrary.searchRevision != revision) return;
    final albumEntries =
        await _buildNamesChunked(albums, (album) => album.name, revision);
    if (AudioLibrary.searchRevision == revision) {
      _commit(
        revision: revision,
        audios: entries,
        artists: artistEntries,
        albums: albumEntries,
      );
    }
  }

  static Future<List<_NameEntry<T>>> _buildNamesChunked<T>(
      List<T> values, String Function(T) name, int revision) async {
    final entries = <_NameEntry<T>>[];
    for (var start = 0; start < values.length; start += 400) {
      await Future<void>.delayed(Duration.zero);
      if (AudioLibrary.searchRevision != revision) return [];
      final end = min(start + 400, values.length);
      for (var i = start; i < end; i++) {
        entries.add(_NameEntry(values[i], name(values[i])));
      }
    }
    return entries;
  }

  List<Audio> searchAudios(String query, {int limit = 200}) =>
      _search(_audioEntries, query, limit).map((entry) => entry.audio).toList();

  List<Artist> searchArtists(String query, {int limit = 50}) =>
      _search(_artistEntries, query, limit)
          .map((entry) => entry.value)
          .toList();

  List<Album> searchAlbums(String query, {int limit = 50}) =>
      _search(_albumEntries, query, limit).map((entry) => entry.value).toList();

  /// Queries all local categories against one revision. Scoring yields between
  /// batches, and only the best requested candidates are retained for sorting.
  Future<LocalSearchResults> searchAll(
    String query, {
    int audioLimit = 200,
    int nameLimit = 50,
    void Function()? checkCancelled,
  }) async {
    checkCancelled?.call();
    while (true) {
      await ensureBuilt();
      checkCancelled?.call();
      final revision = _builtRevision;
      final audios = _audioEntries;
      final artists = _artistEntries;
      final albums = _albumEntries;
      void checkCurrent() {
        checkCancelled?.call();
        if (revision != AudioLibrary.searchRevision) {
          throw const _SearchRevisionChanged();
        }
      }

      try {
        final foundAudios =
            await _searchChunked(audios, query, audioLimit, checkCurrent);
        final foundArtists =
            await _searchChunked(artists, query, nameLimit, checkCurrent);
        final foundAlbums =
            await _searchChunked(albums, query, nameLimit, checkCurrent);
        checkCurrent();
        return LocalSearchResults(
          audios: [for (final entry in foundAudios) entry.audio],
          artists: [for (final entry in foundArtists) entry.value],
          albums: [for (final entry in foundAlbums) entry.value],
        );
      } on _SearchRevisionChanged {
        // A metadata edit/refresh superseded this query while it was yielding.
        // Join the current index build rather than publish mixed old/new rows.
        continue;
      }
    }
  }

  static Future<List<T>> _searchChunked<T extends _Scorable>(List<T> entries,
      String query, int limit, void Function() checkCurrent) async {
    final raw = query.trim().toLowerCase();
    if (raw.isEmpty || limit <= 0 || entries.isEmpty) return [];
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final best = _SearchCandidates<T>(min(limit, entries.length));
    // Even a warm index must return to the event loop before scoring starts.
    await Future<void>.delayed(Duration.zero);
    const batchSize = 256;
    for (var start = 0; start < entries.length; start += batchSize) {
      checkCurrent();
      final end = min(start + batchSize, entries.length);
      for (var i = start; i < end; i++) {
        final score = entries[i].score(raw, compact);
        if (score > 0) best.add(score, entries[i], i);
      }
      if (end < entries.length) await Future<void>.delayed(Duration.zero);
    }
    checkCurrent();
    return best.sorted();
  }

  static List<T> _search<T extends _Scorable>(
    List<T> entries,
    String query,
    int limit,
  ) {
    final rawQuery = query.trim().toLowerCase();
    if (rawQuery.isEmpty || limit <= 0) return [];
    final compactQuery = rawQuery.replaceAll(RegExp(r"\s+"), "");
    final scored = _SearchCandidates<T>(min(limit, entries.length));

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final score = entry.score(rawQuery, compactQuery);
      if (score > 0) scored.add(score, entry, i);
    }
    return scored.sorted();
  }
}

class LocalSearchResults {
  const LocalSearchResults({
    required this.audios,
    required this.artists,
    required this.albums,
  });

  final List<Audio> audios;
  final List<Artist> artists;
  final List<Album> albums;
}

class _SearchRevisionChanged implements Exception {
  const _SearchRevisionChanged();
}

/// A worst-first heap: a better late match replaces the current cutoff in
/// O(log limit), without retaining and sorting every matching library entry.
class _SearchCandidates<T extends _Scorable> {
  _SearchCandidates(this.limit);

  final int limit;
  final List<(int, T, int)> _items = [];

  static int _compare<T extends _Scorable>((int, T, int) a, (int, T, int) b) {
    final score = b.$1.compareTo(a.$1);
    if (score != 0) return score;
    final name = a.$2.sortText.compareTo(b.$2.sortText);
    return name != 0 ? name : a.$3.compareTo(b.$3);
  }

  void add(int score, T entry, int ordinal) {
    if (limit <= 0) return;
    final candidate = (score, entry, ordinal);
    if (_items.length < limit) {
      _items.add(candidate);
      var child = _items.length - 1;
      while (child > 0) {
        final parent = (child - 1) ~/ 2;
        if (_compare(_items[child], _items[parent]) <= 0) break;
        final previous = _items[parent];
        _items[parent] = _items[child];
        _items[child] = previous;
        child = parent;
      }
      return;
    }
    if (_compare(candidate, _items.first) >= 0) return;
    _items[0] = candidate;
    var parent = 0;
    while (true) {
      var child = parent * 2 + 1;
      if (child >= _items.length) break;
      if (child + 1 < _items.length &&
          _compare(_items[child + 1], _items[child]) > 0) {
        child++;
      }
      if (_compare(_items[parent], _items[child]) >= 0) break;
      final previous = _items[parent];
      _items[parent] = _items[child];
      _items[child] = previous;
      parent = child;
    }
  }

  List<T> sorted() {
    _items.sort(_compare);
    return [for (final item in _items) item.$2];
  }
}

abstract class _Scorable {
  int score(String rawQuery, String compactQuery);

  String get sortText;
}

class _AudioEntry extends _Scorable {
  _AudioEntry(this.audio)
      : sortText = audio.displayTitle,
        _display = _SearchKeys.of(audio.displayTitle),
        _tagTitle =
            audio.title.toLowerCase() == audio.displayTitle.toLowerCase()
                ? null
                : _SearchKeys.of(audio.title),
        _artist = _SearchKeys.of(audio.artist),
        _album = _SearchKeys.of(audio.album);

  final Audio audio;
  final _SearchKeys _display;
  final _SearchKeys? _tagTitle;
  final _SearchKeys _artist;
  final _SearchKeys _album;

  @override
  int score(String rawQuery, String compactQuery) {
    final titleScore = max(
      _display.score(rawQuery, compactQuery),
      _tagTitle?.score(rawQuery, compactQuery) ?? 0,
    );
    return titleScore * 3 +
        _artist.score(rawQuery, compactQuery) * 2 +
        _album.score(rawQuery, compactQuery);
  }

  // Metadata synchronization can mutate Audio before its next revision is
  // published. A yielding heap must keep the same comparator keys throughout
  // the current snapshot, just like the scoring projections above.
  @override
  final String sortText;
}

class _NameEntry<T> extends _Scorable {
  _NameEntry(this.value, this.name) : _keys = _SearchKeys.of(name);

  final T value;
  final String name;
  final _SearchKeys _keys;

  @override
  int score(String rawQuery, String compactQuery) =>
      _keys.score(rawQuery, compactQuery);

  @override
  String get sortText => name;
}

class _SearchKeys {
  const _SearchKeys._(
    this.raw,
    this.rawCompact,
    this.fullPinyin,
    this.initials,
  );

  final String raw;
  final String rawCompact;
  final String fullPinyin;
  final String initials;

  static const int cacheLimit = 8192;
  static final HashMap<String, _SearchKeyCacheEntry> _cache = HashMap();
  static final LinkedList<_SearchKeyCacheEntry> _recency = LinkedList();
  static final RegExp _nonAlphanumeric = RegExp(r"[^a-z0-9]");

  factory _SearchKeys.of(String text) {
    final cached = _cache[text];
    if (cached != null) {
      cached.unlink();
      _recency.add(cached);
      return cached.value;
    }

    final created = _SearchKeys._fromText(text);
    final entry = _SearchKeyCacheEntry(text, created);
    _cache[text] = entry;
    _recency.add(entry);
    if (_cache.length > cacheLimit) {
      // LinkedHashMap.keys.first starts its iterator at the backing array's
      // beginning. Repeated LRU remove/reinsert operations leave tombstones,
      // turning each eviction into another scan over the deleted prefix.
      // Keep the eviction head explicitly so churn beyond 8192 unique keys
      // remains constant work per lookup without changing the LRU policy.
      final oldest = _recency.first;
      oldest.unlink();
      _cache.remove(oldest.key);
    }
    return created;
  }

  factory _SearchKeys._fromText(String text) {
    final raw = text.toLowerCase();
    final compact = raw.replaceAll(RegExp(r"\s+"), "");
    return _SearchKeys._(
      raw,
      compact,
      _toFullPinyin(text, compact),
      _toInitials(text),
    );
  }

  static int get cachedCount => _cache.length;

  static void clearCache() {
    _cache.clear();
    _recency.clear();
  }

  static String _toFullPinyin(String text, String compact) {
    if (text.isEmpty || !ChineseHelper.containsChinese(text)) return "";
    final value = PinyinHelper.getPinyin(
      text,
      separator: "",
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase().replaceAll(_nonAlphanumeric, "");
    return value == compact.replaceAll(_nonAlphanumeric, "") ? "" : value;
  }

  static bool _isHan(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);

  static String _toInitials(String text) {
    final result = StringBuffer();
    for (final word in text.split(RegExp(r"\s+"))) {
      if (word.isEmpty) continue;
      var containsHan = false;
      for (final rune in word.runes) {
        if (!_isHan(rune)) continue;
        containsHan = true;
        final pinyin = PinyinHelper.getPinyin(
          String.fromCharCode(rune),
          separator: "",
          format: PinyinFormat.WITHOUT_TONE,
        );
        if (pinyin.isNotEmpty) result.write(pinyin[0].toLowerCase());
      }
      if (!containsHan) result.write(word[0].toLowerCase());
    }
    return result.toString().replaceAll(_nonAlphanumeric, "");
  }

  int score(String rawQuery, String compactQuery) {
    var value = 0;
    if (raw == rawQuery) {
      value += 100;
    } else if (raw.startsWith(rawQuery)) {
      value += 60;
    } else if (raw.contains(rawQuery)) {
      value += 30;
    } else if (rawCompact.contains(compactQuery)) {
      value += 25;
    }

    if (initials == compactQuery) {
      value += 70;
    } else if (initials.startsWith(compactQuery)) {
      value += 50;
    } else if (initials.contains(compactQuery)) {
      value += 20;
    }

    if (fullPinyin == compactQuery) {
      value += 80;
    } else if (fullPinyin.startsWith(compactQuery)) {
      value += 45;
    } else if (fullPinyin.contains(compactQuery)) {
      value += 18;
    }
    return value;
  }
}

final class _SearchKeyCacheEntry extends LinkedListEntry<_SearchKeyCacheEntry> {
  _SearchKeyCacheEntry(this.key, this.value);
  final String key;
  final _SearchKeys value;
}
