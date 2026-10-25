import 'dart:collection';
import 'dart:math';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/album_identity.dart';
import 'package:dan_player/search/audio_search_query.dart';
import 'package:dan_player/search/audio_search_snapshot.dart';
import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/statistics/playback_statistics.dart';
import 'package:dan_player/search/search_text_matcher.dart';

/// A revision-aware search index for raw text, full pinyin and initials.
class AudioSearchIndex {
  AudioSearchIndex._();

  static final AudioSearchIndex instance = AudioSearchIndex._();

  List<_AudioEntry> _audioEntries = const [];
  List<_NameEntry<Artist>> _artistEntries = const [];
  List<_NameEntry<Album>> _albumEntries = const [];

  int _builtRevision = -1;
  Future<void>? _building;
  Map<String, PersonalTrack>? _personalSnapshot;
  int _personalRevision = -1;
  Future<Map<String, PersonalTrack>>? _readingPersonal;

  Future<Map<String, PersonalTrack>> _readPersonal() async {
    while (true) {
      final revision = PersonalLibrary.changes.value;
      if (_personalRevision == revision && _personalSnapshot != null) {
        return _personalSnapshot!;
      }
      final active = _readingPersonal;
      if (active != null) {
        await active;
        continue;
      }
      final read = (() async => (await PersonalLibrary.instance).snapshot())();
      _readingPersonal = read;
      try {
        final snapshot = await read;
        if (revision == PersonalLibrary.changes.value) {
          _personalSnapshot = snapshot;
          _personalRevision = revision;
        }
      } finally {
        if (identical(_readingPersonal, read)) _readingPersonal = null;
      }
    }
  }

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
    SearchTextKeys.clearCache();
  }

  int get debugCachedSearchKeyCount => SearchTextKeys.cachedCount;

  int get debugSearchKeyCacheLimit => SearchTextKeys.cacheLimit;

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
          _NameEntry(album, '${album.name}\n${album.albumArtist ?? ''}')
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
    final albumEntries = await _buildNamesChunked(albums,
        (album) => '${album.name}\n${album.albumArtist ?? ''}', revision);
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
    PlaybackStatistics? statistics,
    Future<Map<String, PersonalTrack>> Function()? loadPersonal,
    DateTime? now,
  }) async {
    final parsed = AudioSearchQuery.parse(query, now: now);
    checkCancelled?.call();
    var historyRevision = 0;
    final recorder = statistics ?? PlaybackStatistics.instance;
    void historyChanged() => historyRevision++;
    if (parsed.usesPlaybackHistory) recorder.addListener(historyChanged);
    try {
      while (true) {
        await ensureBuilt();
        checkCancelled?.call();
        final personalRevision = PersonalLibrary.changes.value;
        final personal = parsed.usesPersonalData
            ? await (loadPersonal?.call() ?? _readPersonal())
            : const <String, PersonalTrack>{};
        checkCancelled?.call();
        if (parsed.usesPersonalData &&
            personalRevision != PersonalLibrary.changes.value) {
          continue;
        }
        final revision = _builtRevision;
        final durationRevision = AudioLibrary.revision;
        final capturedHistoryRevision = historyRevision;
        final snapshot = AudioSearchSnapshot.capture(parsed,
            personal: personal,
            statistics: recorder,
            audios: _audioEntries.map((entry) => entry.audio));
        final audios = _audioEntries;
        final artists = _artistEntries;
        final albums = _albumEntries;
        void checkCurrent() {
          checkCancelled?.call();
          if (revision != AudioLibrary.searchRevision ||
              (parsed.usesLiveMetadata &&
                  durationRevision != AudioLibrary.revision) ||
              (parsed.usesPersonalData &&
                  personalRevision != PersonalLibrary.changes.value) ||
              (parsed.usesPlaybackHistory &&
                  capturedHistoryRevision != historyRevision)) {
            throw const _SearchRevisionChanged();
          }
        }

        try {
          final foundAudios = await _searchChunked(
              audios, parsed, audioLimit, checkCurrent, snapshot);
          final foundArtists = await _searchChunked(
              artists, parsed, nameLimit, checkCurrent, snapshot);
          final foundAlbums = await _searchChunked(
              albums, parsed, nameLimit, checkCurrent, snapshot);
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
    } finally {
      if (parsed.usesPlaybackHistory) recorder.removeListener(historyChanged);
    }
  }

  static Future<List<T>> _searchChunked<T extends _Scorable>(
      List<T> entries,
      AudioSearchQuery query,
      int limit,
      void Function() checkCurrent,
      AudioSearchSnapshot snapshot) async {
    if (query.text.isEmpty || limit <= 0 || entries.isEmpty) return [];
    final plain = query.hasStructuredSyntax
        ? null
        : PlainSearchQuery.normalized(query.text);
    final best = _SearchCandidates<T>(min(limit, entries.length));
    // Even a warm index must return to the event loop before scoring starts.
    await Future<void>.delayed(Duration.zero);
    const batchSize = 256;
    for (var start = 0; start < entries.length; start += batchSize) {
      checkCurrent();
      final end = min(start + batchSize, entries.length);
      for (var i = start; i < end; i++) {
        final score = entries[i].scoreQuery(query, snapshot, plain);
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
    final parsed = AudioSearchQuery.parse(query);
    if (parsed.text.isEmpty || limit <= 0) return [];
    final plain = parsed.hasStructuredSyntax
        ? null
        : PlainSearchQuery.normalized(parsed.text);
    final scored = _SearchCandidates<T>(min(limit, entries.length));
    final snapshot = AudioSearchSnapshot.capture(parsed,
        audios: entries.whereType<_AudioEntry>().map((entry) => entry.audio));

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final score = entry.scoreQuery(parsed, snapshot, plain);
      if (score > 0) scored.add(score, entry, i);
    }
    return scored.sorted();
  }
}

/// A queue-owned text snapshot. Rebuild on queue or searchable metadata changes;
/// each lookup normalizes its query once and preserves occurrence positions.
class QueueSearchIndex {
  QueueSearchIndex(Iterable<Audio> audios) {
    final shared = HashMap<Audio, List<SearchTextKeys>>.identity();
    _entries = [
      for (final audio in audios) _keysFor(audio, shared),
    ];
    SearchTextKeys.clearCache();
  }

  QueueSearchIndex._(this._entries);

  static List<SearchTextKeys> _keysFor(
          Audio audio, Map<Audio, List<SearchTextKeys>> shared) =>
      shared.putIfAbsent(
          audio,
          () => [
                SearchTextKeys.of(audio.displayTitle),
                if (audio.title != audio.displayTitle)
                  SearchTextKeys.of(audio.title),
                SearchTextKeys.of(audio.artist),
                SearchTextKeys.of(audio.album),
              ]);

  /// The owner checks its queue/metadata generation through shouldCancel. No
  /// obsolete partial snapshot is published, and expensive pinyin work yields
  /// before the first batch and between every 128 occurrences.
  static Future<QueueSearchIndex?> build(Iterable<Audio> audios,
      {bool Function()? shouldCancel}) async {
    await Future<void>.delayed(Duration.zero);
    if (shouldCancel?.call() ?? false) return null;
    final snapshot = List<Audio>.of(audios);
    final shared = HashMap<Audio, List<SearchTextKeys>>.identity();
    final entries = <List<SearchTextKeys>>[];
    try {
      for (var start = 0; start < snapshot.length; start += 128) {
        if (shouldCancel?.call() ?? false) return null;
        final end = min(start + 128, snapshot.length);
        for (var i = start; i < end; i++) {
          entries.add(_keysFor(snapshot[i], shared));
        }
        if (end < snapshot.length) await Future<void>.delayed(Duration.zero);
      }
      return (shouldCancel?.call() ?? false)
          ? null
          : QueueSearchIndex._(entries);
    } finally {
      SearchTextKeys.clearCache();
    }
  }

  late final List<List<SearchTextKeys>> _entries;

  bool _matches(int index, PlainSearchQuery query) =>
      query.text.isEmpty ||
      _entries[index]
          .any((keys) => keys.score(query.text, query.compact) > 0) ||
      query.scoreWords(_entries[index]) > 0;

  List<int> matchingIndices(String query) {
    final prepared = PlainSearchQuery(query);
    if (prepared.text.isEmpty) {
      return List<int>.generate(_entries.length, (index) => index);
    }
    return [
      for (var index = 0; index < _entries.length; index++)
        if (_matches(index, prepared)) index,
    ];
  }

  Future<List<int>?> matchingIndicesAsync(String query,
      {bool Function()? shouldCancel}) async {
    await Future<void>.delayed(Duration.zero);
    if (shouldCancel?.call() ?? false) return null;
    final prepared = PlainSearchQuery(query);
    final matches = <int>[];
    for (var start = 0; start < _entries.length; start += 128) {
      if (shouldCancel?.call() ?? false) return null;
      final end = min(start + 128, _entries.length);
      for (var index = start; index < end; index++) {
        if (_matches(index, prepared)) matches.add(index);
      }
      if (end < _entries.length) await Future<void>.delayed(Duration.zero);
    }
    return (shouldCancel?.call() ?? false) ? null : matches;
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

  int scorePlain(PlainSearchQuery query);

  int? scoreTerm(AudioSearchTerm term, AudioSearchSnapshot snapshot);

  int scoreQuery(AudioSearchQuery query, AudioSearchSnapshot snapshot,
      PlainSearchQuery? plain) {
    if (!query.hasStructuredSyntax) {
      return scorePlain(plain!);
    }
    return query.expression!.evaluate((term) => scoreTerm(term, snapshot)) ?? 0;
  }

  String get sortText;
}

class _AudioEntry extends _Scorable {
  _AudioEntry(this.audio)
      : sortText = audio.displayTitle,
        _display = SearchTextKeys.of(audio.displayTitle),
        _tagTitle =
            audio.title.toLowerCase() == audio.displayTitle.toLowerCase()
                ? null
                : SearchTextKeys.of(audio.title),
        _artist = SearchTextKeys.of(audio.artist),
        _album = SearchTextKeys.of(audio.album),
        _composer = _knownKeys(audio.composer),
        _albumArtist = _knownKeys(audio.albumArtist),
        _language = _knownKeys(audio.language),
        _titleExists = _knownText(audio.title),
        _artistExists = _knownText(audio.artist),
        _albumExists = _knownText(audio.album),
        _filename = SearchTextKeys.of(
            audio.localFilePath.replaceAll('\\', '/').split('/').last),
        _pendingMetadata = audio.metadataReadPending,
        _classificationRead = audio.classificationTagsRead,
        _path = normalizeSearchText(audio.localFilePath).replaceAll('\\', '/') {
    _plainKeys = [_display, if (_tagTitle != null) _tagTitle!, _artist, _album];
  }

  final Audio audio;
  final SearchTextKeys _display;
  final SearchTextKeys? _tagTitle;
  final SearchTextKeys _artist;
  final SearchTextKeys _album;
  final String _path;
  final SearchTextKeys? _composer, _albumArtist, _language;
  final SearchTextKeys _filename;
  final bool _titleExists, _artistExists, _albumExists;
  final bool _pendingMetadata, _classificationRead;
  late final List<SearchTextKeys> _plainKeys;
  static bool _knownText(String? value) => normalizedMusicTag(value) != null;
  static SearchTextKeys? _knownKeys(String? value) =>
      _knownText(value) ? SearchTextKeys.of(value!) : null;

  @override
  int? scoreTerm(AudioSearchTerm term, AudioSearchSnapshot snapshot) {
    int yes(bool value) => value ? 30 : 0;
    final metadata = snapshot.metadata[audio];
    switch (term.field) {
      case 'title':
        return max(_display.scoreTerm(term), _tagTitle?.scoreTerm(term) ?? 0) *
            3;
      case 'artist':
        return _artist.scoreTerm(term) * 2;
      case 'album':
        return _album.scoreTerm(term);
      case 'filename':
        return audio.isLocal ? _filename.scoreTerm(term) : null;
      case 'composer':
        return _pendingMetadata || !_classificationRead
            ? null
            : _composer?.scoreTerm(term);
      case 'albumartist':
        return _pendingMetadata || !_classificationRead
            ? null
            : _albumArtist?.scoreTerm(term);
      case 'language':
        return _pendingMetadata || _language == null
            ? null
            : yes(_language!.raw == term.value);
      case 'folder':
      case 'path':
        if (audio.isOnline) return null;
        final end = _path.lastIndexOf('/');
        final value = term.field == 'folder'
            ? (end < 0 ? '' : _path.substring(0, end))
            : _path;
        var pathQuery = term.value.replaceAll('\\', '/');
        if (term.field == 'folder' && pathQuery.length > 1) {
          pathQuery = pathQuery.replaceFirst(RegExp(r'/+$'), '');
        }
        return value.contains(pathQuery) ? 30 : 0;
      case 'format':
        if (audio.isOnline) return null;
        final file = _path.split('/').last;
        final dot = file.lastIndexOf('.');
        return dot >= 0 && term.formats!.contains(file.substring(dot + 1))
            ? 30
            : 0;
      case 'duration':
        return metadata == null || metadata.duration <= 0
            ? null
            : yes(term.duration!.matches(metadata.duration));
      case 'track':
      case 'bitrate':
      case 'samplerate':
      case 'filesize':
        if (_pendingMetadata && term.field != 'filesize') return null;
        final value = switch (term.field) {
          'track' => metadata?.track,
          'bitrate' => metadata?.bitrate,
          'samplerate' => metadata?.sampleRate,
          _ => audio.isLocal ? metadata?.fileSize : null,
        };
        return value == null || value <= 0
            ? null
            : yes(term.number!.matches(value));
      case 'rating':
        final rating = snapshot.personal[audio.stableTrackId]?.rating;
        if (term.value == 'unrated') return yes(rating == null);
        return rating == null ? null : yes(term.number!.matches(rating));
      case 'tag':
        final tags =
            snapshot.personal[audio.stableTrackId]?.tags ?? const <String>[];
        return yes(tags.any((tag) => normalizeSearchText(tag) == term.value));
      case 'added':
        final added = snapshot.personal[audio.stableTrackId]?.firstAddedAtUtc;
        return added == null
            ? null
            : yes(term.date!.matches(added.millisecondsSinceEpoch));
      case 'playcount':
      case 'completed':
      case 'skipped':
      case 'listened':
      case 'lastplayed':
        final playback = snapshot.playbackOf(audio);
        if (playback == null) return null;
        if (term.field == 'lastplayed') {
          if (term.value == 'never') {
            return playback.last == 0 && playback.count > 0
                ? null
                : yes(playback.last == 0);
          }
          return playback.last <= 0
              ? null
              : yes(term.date!.matches(playback.last));
        }
        final count = switch (term.field) {
          'playcount' => playback.count,
          'completed' => playback.completed,
          'skipped' => playback.skipped,
          _ => playback.listened
        };
        if (count < 0) return null;
        return term.field == 'listened'
            ? yes(term.duration!.matches(count / 1000))
            : yes(term.number!.matches(count));
      case 'has':
        if (_pendingMetadata &&
            const {
              'title',
              'artist',
              'album',
              'composer',
              'albumartist',
              'language',
              'track',
              'duration',
              'bitrate',
              'samplerate'
            }.contains(term.value)) {
          return null;
        }
        if (!_classificationRead &&
            const {'composer', 'albumartist'}.contains(term.value)) {
          return null;
        }
        final exists = switch (term.value) {
          'title' => _titleExists,
          'artist' => _artistExists,
          'album' => _albumExists,
          'composer' => _composer != null,
          'albumartist' => _albumArtist != null,
          'language' => _language != null,
          'track' => (metadata?.track ?? 0) > 0,
          'duration' => (metadata?.duration ?? 0) > 0,
          'bitrate' => (metadata?.bitrate ?? 0) > 0,
          'samplerate' => (metadata?.sampleRate ?? 0) > 0,
          'filesize' => audio.isLocal && (metadata?.fileSize ?? 0) > 0,
          'rating' => snapshot.personal[audio.stableTrackId]?.rating != null,
          'tag' =>
            snapshot.personal[audio.stableTrackId]?.tags.isNotEmpty ?? false,
          'added' =>
            snapshot.personal[audio.stableTrackId]?.firstAddedAtUtc != null,
          'history' => snapshot.playbackOf(audio) == null
              ? null
              : snapshot.history.containsKey(audio.isOnline
                  ? 'online:${audio.onlineProvider}:${audio.onlineId}'
                  : audio.stableTrackId),
          _ => false,
        };
        return exists == null ? null : yes(exists);
      default:
        if (!term.literal) return score(term.value, term.compact);
        return max(_display.scoreTerm(term), _tagTitle?.scoreTerm(term) ?? 0) *
                3 +
            _artist.scoreTerm(term) * 2 +
            _album.scoreTerm(term);
    }
  }

  @override
  int scorePlain(PlainSearchQuery query) {
    final exact = score(query.text, query.compact);
    return exact > 0 ? exact : query.scoreWords(_plainKeys);
  }

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
  _NameEntry(this.value, this.name) : _keys = SearchTextKeys.of(name);

  final T value;
  final String name;
  final SearchTextKeys _keys;

  @override
  int? scoreTerm(AudioSearchTerm term, AudioSearchSnapshot snapshot) =>
      term.field.isNotEmpty &&
              term.field != (value is Artist ? 'artist' : 'album')
          ? null
          : _keys.scoreTerm(term);

  @override
  int score(String rawQuery, String compactQuery) =>
      _keys.score(rawQuery, compactQuery);

  @override
  int scorePlain(PlainSearchQuery query) {
    final exact = score(query.text, query.compact);
    return exact > 0 ? exact : query.scoreWords([_keys]);
  }

  @override
  String get sortText => name;
}
