import 'dart:collection';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:pinyin/pinyin.dart';

/// A revision-aware search index for raw text, full pinyin and initials.
class AudioSearchIndex {
  AudioSearchIndex._();

  static final AudioSearchIndex instance = AudioSearchIndex._();

  final List<_AudioEntry> _audioEntries = [];
  final List<_NameEntry<Artist>> _artistEntries = [];
  final List<_NameEntry<Album>> _albumEntries = [];

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
    required List<Artist> artists,
    required List<Album> albums,
  }) {
    _audioEntries
      ..clear()
      ..addAll(audios);
    _artistEntries
      ..clear()
      ..addAll([for (final item in artists) _NameEntry(item, item.name)]);
    _albumEntries
      ..clear()
      ..addAll([for (final item in albums) _NameEntry(item, item.name)]);
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
      artists: List.of(library.artistCollection.values),
      albums: List.of(library.albumCollection.values),
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

    if (AudioLibrary.searchRevision == revision) {
      _commit(
        revision: revision,
        audios: entries,
        artists: artists,
        albums: albums,
      );
    }
  }

  List<Audio> searchAudios(String query, {int limit = 200}) =>
      _search(_audioEntries, query, limit).map((entry) => entry.audio).toList();

  List<Artist> searchArtists(String query, {int limit = 50}) =>
      _search(_artistEntries, query, limit)
          .map((entry) => entry.value)
          .toList();

  List<Album> searchAlbums(String query, {int limit = 50}) =>
      _search(_albumEntries, query, limit).map((entry) => entry.value).toList();

  static List<T> _search<T extends _Scorable>(
    List<T> entries,
    String query,
    int limit,
  ) {
    final rawQuery = query.trim().toLowerCase();
    if (rawQuery.isEmpty) return [];
    final compactQuery = rawQuery.replaceAll(RegExp(r"\s+"), "");
    final scored = <(int, T)>[];

    for (final entry in entries) {
      final score = entry.score(rawQuery, compactQuery);
      if (score > 0) scored.add((score, entry));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      return byScore != 0 ? byScore : a.$2.sortText.compareTo(b.$2.sortText);
    });
    return [for (final item in scored.take(limit)) item.$2];
  }
}

abstract class _Scorable {
  int score(String rawQuery, String compactQuery);

  String get sortText;
}

class _AudioEntry extends _Scorable {
  _AudioEntry(this.audio)
      : _display = _SearchKeys.of(audio.displayTitle),
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

  @override
  String get sortText => audio.displayTitle;
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
  static final LinkedHashMap<String, _SearchKeys> _cache = LinkedHashMap();
  static final RegExp _nonAlphanumeric = RegExp(r"[^a-z0-9]");

  factory _SearchKeys.of(String text) {
    final cached = _cache.remove(text);
    if (cached != null) {
      _cache[text] = cached;
      return cached;
    }

    final created = _SearchKeys._fromText(text);
    _cache[text] = created;
    if (_cache.length > cacheLimit) _cache.remove(_cache.keys.first);
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

  static void clearCache() => _cache.clear();

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
