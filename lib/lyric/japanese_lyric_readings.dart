import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_lyric_cache.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/lyric_primary_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show CharacterRange, StringCharacters;

enum JapaneseReadingResult {
  applied,
  unchanged,
  unavailable,
  dictionaryMissing,
  stale,
  tooLarge
}

@immutable
class JapaneseReadingProjection {
  const JapaneseReadingProjection(this.lyric, this.result);
  final Lyric lyric;
  final JapaneseReadingResult result;
}

@immutable
class JapaneseReadingChunk {
  const JapaneseReadingChunk(this.text, {this.analyzable = true});
  final String text;
  final bool analyzable;
}

/// No substring can divide a surrogate pair, combining sequence or emoji. A
/// pathological single cluster longer than Windows' limit is retained verbatim.
List<JapaneseReadingChunk> japaneseReadingChunks(String text) {
  final result = <JapaneseReadingChunk>[];
  var buffer = StringBuffer();
  var units = 0;
  void flush() {
    if (units == 0) return;
    result.add(JapaneseReadingChunk(buffer.toString()));
    buffer = StringBuffer();
    units = 0;
  }

  for (final cluster in text.characters) {
    if (cluster.length > 100) {
      flush();
      result.add(JapaneseReadingChunk(cluster, analyzable: false));
      continue;
    }
    if (units + cluster.length > 100) flush();
    buffer.write(cluster);
    units += cluster.length;
  }
  flush();
  return List.unmodifiable(result);
}

bool isJapaneseReadingLanguage(String? language) {
  if (language == null) return false;
  return language
      .toLowerCase()
      .replaceAll('_', '-')
      .split(RegExp(r'[;,/|]'))
      .map((part) => part.trim())
      .any((part) =>
          RegExp(r'^ja(?:-[a-z0-9]{1,8})*$').hasMatch(part) ||
          const {'ja', 'ja-jp', 'jpn', 'japanese', '日本語', '日语', '日文', '일본어'}
              .contains(part));
}

bool _hasKana(String text) => text.runes.any((rune) =>
    (rune >= 0x3041 && rune <= 0x3096) ||
    (rune >= 0x309d && rune <= 0x309f) ||
    (rune >= 0x30a1 && rune <= 0x30fa) ||
    (rune >= 0x30fd && rune <= 0x30ff) ||
    (rune >= 0x31f0 && rune <= 0x31ff) ||
    (rune >= 0xff66 && rune <= 0xff9d));

bool _hasHan(String text) => text.runes.any((rune) =>
    rune == 0x3005 || // Ideographic iteration marks belong to the Han reading.
    rune == 0x303b ||
    (rune >= 0x3400 && rune <= 0x9fff) ||
    (rune >= 0xf900 && rune <= 0xfaff) ||
    (rune >= 0x20000 && rune <= 0x323af));

String _content(LyricLine line) => switch (line) {
      UnsyncLyricLine() => line.content,
      SyncLyricLine() => line.content,
      _ => '',
    };

bool _sameKanaReading(String? authored, String generated) {
  if (authored == null || !_hasKana(authored)) return false;
  String comparable(String text) => String.fromCharCodes(text.runes.map(
        (rune) => rune >= 0x30a1 && rune <= 0x30f6 ? rune - 0x60 : rune,
      )).replaceAll(RegExp(r'\s'), '');
  return comparable(authored) == comparable(generated);
}

String _hiragana(String text) => String.fromCharCodes(text.runes.map(
      (rune) => rune >= 0x30a1 && rune <= 0x30f6 ? rune - 0x60 : rune,
    ));

/// Preserve contextual dictionary words. Resolve Kana anchors against the
/// *complete* reading: a repeated anchor can still have one valid alignment
/// once later anchors and the word end are considered. Ambiguous alignments
/// never become guessed per-character pronunciations.
List<JapaneseLyricReadingSpan> japaneseReadingWordSpans(
    String text, String reading,
    {int offset = 0}) {
  if (text.length > 512 ||
      reading.length > 8192 ||
      !_hasHan(text) ||
      text == reading) {
    return const [];
  }
  final groups = <({int start, int end, bool han})>[];
  var position = 0;
  for (final cluster in text.characters) {
    final han = _hasHan(cluster);
    if (groups.isNotEmpty && groups.last.han == han) {
      final last = groups.removeLast();
      groups.add((start: last.start, end: position + cluster.length, han: han));
    } else {
      groups.add((start: position, end: position + cluster.length, han: han));
    }
    position += cluster.length;
  }
  final normalized = _hiragana(reading);
  final boundaries = <int>{0};
  var readingOffset = 0;
  for (final cluster in reading.characters) {
    readingOffset += cluster.length;
    boundaries.add(readingOffset);
  }
  final memo = <(int, int), List<List<JapaneseLyricReadingSpan>>>{};
  var exhausted = false;
  List<List<JapaneseLyricReadingSpan>> align(int index, int cursor) {
    if (index == groups.length) {
      return cursor == reading.length ? [const []] : const [];
    }
    final key = (index, cursor);
    if (memo.containsKey(key)) return memo[key]!;
    // Bound even a pathological externally supplied pronunciation. Production
    // chunks are at most 100 UTF-16 units and results at most 2,000 units.
    if (memo.length >= 16384) {
      exhausted = true;
      return const [];
    }
    final group = groups[index];
    if (!group.han) {
      final anchor = _hiragana(text.substring(group.start, group.end));
      return memo[key] = normalized.startsWith(anchor, cursor)
          ? align(index + 1, cursor + anchor.length)
          : const [];
    }
    if (cursor >= reading.length) return memo[key] = const [];
    final ends = <int>[];
    if (index + 1 == groups.length) {
      ends.add(reading.length);
    } else {
      final next = groups[index + 1];
      final anchor = _hiragana(text.substring(next.start, next.end));
      var end = normalized.indexOf(anchor, cursor + 1);
      while (end >= 0) {
        if (boundaries.contains(end)) ends.add(end);
        end = normalized.indexOf(anchor, end + 1);
      }
    }
    final paths = <List<JapaneseLyricReadingSpan>>[];
    for (final end in ends) {
      if (end <= cursor) continue;
      final yomi = reading.substring(cursor, end);
      if (!_hasKana(yomi) || _hasHan(yomi)) continue;
      for (final suffix in align(index + 1, end)) {
        paths.add([
          JapaneseLyricReadingSpan(
              start: offset + group.start, end: offset + group.end, text: yomi),
          ...suffix,
        ]);
        if (paths.length == 2) return memo[key] = paths;
      }
    }
    return memo[key] = paths;
  }

  final paths = align(0, 0);
  return !exhausted && paths.length == 1
      ? List.unmodifiable(paths.single)
      : const [];
}

bool _validSaved(String source, JapaneseCachedReading value) {
  final boundaries = <int>{0};
  var offset = 0;
  for (final cluster in source.characters) {
    offset += cluster.length;
    boundaries.add(offset);
  }
  var previousEnd = 0;
  for (final span in value.spans) {
    if (span.start < previousEnd ||
        span.end > source.length ||
        !boundaries.contains(span.start) ||
        !boundaries.contains(span.end) ||
        !_hasHan(source.substring(span.start, span.end)) ||
        !_hasKana(span.text) ||
        _hasHan(span.text)) {
      return false;
    }
    previousEnd = span.end;
  }
  return true;
}

bool _validSavedRows(Lyric source, Map<int, JapaneseCachedReading> saved) =>
    saved.entries.every((entry) =>
        entry.key >= 0 &&
        entry.key < source.lines.length &&
        _validSaved(_content(source.lines[entry.key]), entry.value));

List<JapaneseLyricReadingSpan> _primarySpans(
        String primary, List<JapaneseLyricReadingSpan> spans) =>
    spans.every((span) => span.end <= primary.length)
        ? spans
        : List.unmodifiable(spans.where((span) => span.end <= primary.length));

/// Verify source coverage and display offsets, without generating any reading.
/// The layout consumes these same grapheme ranges; whole contextual readings
/// remain valid without inventing a pronunciation for each individual Han.
bool hasCompleteJapaneseReadings(Lyric? lyric) {
  if (lyric == null) return false;
  var hasCandidate = false;
  for (final line in lyric.lines) {
    final source = lyricPrimaryText(line);
    if (!_hasHan(source)) continue;
    hasCandidate = true;
    final spans = line.japaneseReadingSpans.isNotEmpty
        ? _primarySpans(source, line.japaneseReadingSpans)
        : japaneseReadingWordSpans(source, line.romanization ?? '');
    final saved = JapaneseCachedReading(line.japaneseReading ?? '', spans);
    if (!_validSaved(source, saved)) return false;
    var offset = 0, index = 0;
    for (final cluster in source.characters) {
      while (index < spans.length && spans[index].end <= offset) {
        index++;
      }
      if (_hasHan(cluster) &&
          (index == spans.length ||
              spans[index].start > offset ||
              spans[index].end < offset + cluster.length)) {
        return false;
      }
      offset += cluster.length;
    }
  }
  return hasCandidate;
}

/// Source/cache/document objects are untouched. Work runs only on a source or
/// presentation change; a completed projection is reused by every lyric view.
class JapaneseReadingProjector {
  JapaneseReadingProjector({
    JapaneseChunkAnalyzer? analyze,
    VoidCallback? cancel,
    JapaneseLyricReadingCache? cache,
    JapaneseReadingAnalyzerPolicy? policy,
    this.waitForCacheWrites = false,
    List<String> Function()? cacheNamespaces,
    this.maximumEntries = 256,
    this.maximumCacheBytes = 128 * 1024,
    this.maximumInputUnits = 32768,
  })  : _policy = policy ??
            (analyze == null ? JapaneseReadingAnalyzerPolicy.shared : null),
        _analyze =
            analyze ?? (policy ?? JapaneseReadingAnalyzerPolicy.shared).analyze,
        _cancel = cancel ??
            (analyze == null
                ? (policy ?? JapaneseReadingAnalyzerPolicy.shared).cancel
                : null),
        _persistentCache = cache ??
            (analyze == null ? JapaneseLyricReadingCache.instance : null),
        _cacheNamespaces = cacheNamespaces ??
            (analyze == null
                ? () => (policy ?? JapaneseReadingAnalyzerPolicy.shared)
                    .cacheNamespaces
                : () => const ['offline']);

  factory JapaneseReadingProjector.background() => JapaneseReadingProjector(
        policy: JapaneseReadingAnalyzerPolicy.background,
        cache: JapaneseLyricReadingCache.instance,
        waitForCacheWrites: true,
        cacheNamespaces: () =>
            JapaneseReadingAnalyzerPolicy.background.cacheNamespaces,
      );

  final JapaneseChunkAnalyzer _analyze;
  final JapaneseReadingAnalyzerPolicy? _policy;
  final VoidCallback? _cancel;
  final JapaneseLyricReadingCache? _persistentCache;
  final List<String> Function() _cacheNamespaces;
  final int maximumEntries, maximumCacheBytes, maximumInputUnits;
  final bool waitForCacheWrites;
  final Map<String, List<JapanesePhoneticWord>> _cache = {};
  var _cacheBytes = 0;
  var _generation = 0;
  var _nativePending = false;
  ({
    Lyric source,
    int generation,
    List<String> namespaces,
    bool Function() owner
  })? _displayCacheMiss;

  @visibleForTesting
  int get cachedEntries => _cache.length;
  @visibleForTesting
  int get cachedBytes => _cacheBytes;

  Future<void> flushPersistentCache() =>
      _persistentCache?.flush() ?? Future.value();

  void cancel() {
    _generation++;
    _displayCacheMiss = null;
    if (_nativePending) _cancel?.call();
    _nativePending = false;
  }

  void dispose() {
    cancel();
    _cache.clear();
    _cacheBytes = 0;
  }

  int _readingBytes(List<JapanesePhoneticWord>? reading) =>
      reading?.fold<int>(0,
          (sum, word) => sum + (word.text.length + word.reading.length) * 2) ??
      0;

  void _remember(
      String text, List<JapanesePhoneticWord> reading, String namespace) {
    text = '$namespace\u0000$text';
    final bytes = text.length * 2 + _readingBytes(reading);
    if (maximumEntries <= 0 || bytes > maximumCacheBytes) return;
    if (_cache.containsKey(text)) {
      final previous = _cache.remove(text);
      _cacheBytes -= text.length * 2 + _readingBytes(previous);
    }
    while (_cache.isNotEmpty &&
        (_cache.length >= maximumEntries ||
            _cacheBytes + bytes > maximumCacheBytes)) {
      final key = _cache.keys.first;
      final previous = _cache.remove(key);
      _cacheBytes -= key.length * 2 + _readingBytes(previous);
    }
    _cache[text] = List.unmodifiable(reading);
    _cacheBytes += bytes;
  }

  /// Earlier combined rows used a whole source chunk as their word-cache key.
  /// A shortened last primary chunk may reuse it only when the exact full word
  /// sequence is present. A crossing word requires the existing unique kana
  /// alignment; its Han reading is never split or inferred across that endpoint.
  /// This is a read projection: no new alias or cache write.
  List<JapanesePhoneticWord>? _cachedPrimaryPrefix(
      String namespace, String primary, Iterable<String> wholeChunks) {
    final direct = _cache['$namespace\u0000$primary'];
    if (direct != null) return direct;
    for (final whole in wholeChunks) {
      final words = _cache['$namespace\u0000$whole'];
      if (words == null || words.map((word) => word.text).join() != whole) {
        continue;
      }
      var offset = 0;
      final prefix = <JapanesePhoneticWord>[];
      for (final word in words) {
        final end = offset + word.text.length;
        if (end > primary.length) {
          final length = primary.length - offset;
          final spans = japaneseReadingWordSpans(word.text, word.reading);
          if (length <= 0 ||
              spans.any((span) => span.start < length && span.end > length)) {
            break;
          }
          final text = word.text.substring(0, length);
          final reading = StringBuffer();
          var cursor = 0;
          for (final span in spans.where((span) => span.end <= length)) {
            reading
              ..write(text.substring(cursor, span.start))
              ..write(span.text);
            cursor = span.end;
          }
          reading.write(text.substring(cursor));
          prefix.add(JapanesePhoneticWord(text, reading.toString()));
          return List.unmodifiable(prefix);
        }
        prefix.add(word);
        offset = end;
        if (offset == primary.length) return List.unmodifiable(prefix);
      }
    }
    return null;
  }

  String? _wholeSourceChunkAt(String source, int start) {
    final characters = CharacterRange.at(source, start);
    final buffer = StringBuffer();
    var units = 0;
    while (characters.moveNext()) {
      final text = characters.current;
      if (units + text.length > 100) break;
      buffer.write(text);
      units += text.length;
    }
    return units == 0 ? null : buffer.toString();
  }

  Future<JapaneseReadingProjection> project(Lyric source,
          {String? language,
          required bool enabled,
          bool force = false,
          bool verifyCoverage = false,
          JapaneseReadingRequestMode requestMode =
              JapaneseReadingRequestMode.automatic,
          required bool Function() stillCurrent}) =>
      _project(source,
          language: language,
          enabled: enabled,
          force: force,
          verifyCoverage: verifyCoverage,
          requestMode: requestMode,
          stillCurrent: stillCurrent);

  /// Restore a previously authorized, valid display without analysis or writes.
  /// An exact cached source may contain only Han text: restoring that fingerprint
  /// does not need to guess its language or authorize another generation.
  Future<JapaneseReadingProjection> projectCached(Lyric source,
          {String? language,
          bool allowLegacy = true,
          required bool Function() stillCurrent}) =>
      _project(source,
          language: language,
          enabled: true,
          force: true,
          cachedOnly: true,
          allowLegacy: allowLegacy,
          stillCurrent: stillCurrent);

  Future<JapaneseReadingProjection> _project(Lyric source,
      {String? language,
      required bool enabled,
      bool force = false,
      bool verifyCoverage = false,
      bool cachedOnly = false,
      bool allowLegacy = false,
      JapaneseReadingRequestMode requestMode =
          JapaneseReadingRequestMode.automatic,
      required bool Function() stillCurrent}) async {
    final priorGeneration = _generation;
    final displayCacheMiss = _displayCacheMiss;
    final cacheOwnerCurrent = displayCacheMiss?.owner() == true;
    cancel();
    final generation = _generation;
    bool current() => generation == _generation && stillCurrent();
    Map<int, JapaneseCachedReading>? incompleteSaved;
    JapaneseReadingProjection result(JapaneseReadingResult reason) =>
        JapaneseReadingProjection(
            incompleteSaved != null &&
                    (reason == JapaneseReadingResult.unchanged ||
                        reason == JapaneseReadingResult.unavailable ||
                        reason == JapaneseReadingResult.dictionaryMissing)
                ? _displayCopy(source, incompleteSaved)
                : source,
            reason);
    if (!current()) return result(JapaneseReadingResult.stale);
    if (!enabled && !force) return result(JapaneseReadingResult.unchanged);
    var totalUnits = 0;
    for (final line in source.lines) {
      totalUnits += lyricPrimaryText(line).length;
      if (totalUnits > maximumInputUnits) {
        return result(JapaneseReadingResult.tooLarge);
      }
    }
    if (!force &&
        !isJapaneseReadingLanguage(language) &&
        !source.lines.any((line) => _hasKana(lyricPrimaryText(line)))) {
      return result(JapaneseReadingResult.unchanged);
    }

    final candidateTexts = <int, String>{};
    var inputUnits = 0;
    for (var index = 0; index < source.lines.length; index++) {
      final line = source.lines[index];
      final text = lyricPrimaryText(line);
      if (!_hasHan(text)) continue;
      inputUnits += text.length;
      if (inputUnits > maximumInputUnits) {
        return result(JapaneseReadingResult.tooLarge);
      }
      candidateTexts[index] = text;
    }
    if (candidateTexts.isEmpty) return result(JapaneseReadingResult.unchanged);
    List<String> allowedNamespaces() =>
        _policy?.cacheNamespacesFor(requestMode) ?? _cacheNamespaces();
    final namespaces = List<String>.of(allowedNamespaces());
    if (namespaces.isEmpty) return result(JapaneseReadingResult.unavailable);
    Map<int, JapaneseCachedReading>? offlineSaved;
    // A same-owner automatic generation follows the display preflight directly.
    // Consume its bounded miss once instead of reading the same files twice.
    // Cancellation, another source or new permission namespaces invalidate it.
    final alreadyRead = !cachedOnly &&
        !force &&
        requestMode != JapaneseReadingRequestMode.online &&
        displayCacheMiss != null &&
        cacheOwnerCurrent &&
        displayCacheMiss.generation == priorGeneration &&
        identical(displayCacheMiss.source, source) &&
        namespaces.every(displayCacheMiss.namespaces.contains);
    for (final namespace in alreadyRead ? const <String>[] : namespaces) {
      final fingerprint =
          _persistentCache?.fingerprint(source, namespace: namespace);
      if (fingerprint == null) break;
      var saved =
          await _persistentCache!.read(fingerprint, stillCurrent: current);
      if (!current()) return result(JapaneseReadingResult.stale);
      if (saved == null && (cachedOnly && allowLegacy || verifyCoverage)) {
        final legacy = await _persistentCache!
            .readLegacy(source, namespace: namespace, stillCurrent: current);
        if (!current()) return result(JapaneseReadingResult.stale);
        if (legacy != null && _validSavedRows(source, legacy)) {
          saved = _restoreLegacySpans(source, {
            for (final entry in legacy.entries)
              if (candidateTexts.containsKey(entry.key)) entry.key: entry.value,
          });
        }
      }
      if (saved != null && _validSavedRows(source, saved)) {
        // Old combined rows can have valid auxiliary-only entries. Validate
        // every original row and source offset before selecting primary rows;
        // discarding invalid extra entries would silently accept a bad cache.
        saved = {
          for (final entry in saved.entries)
            if (candidateTexts.containsKey(entry.key)) entry.key: entry.value,
        };
        if (saved.isEmpty) continue;
        if (verifyCoverage &&
            !hasCompleteJapaneseReadings(_displayCopy(source, saved))) {
          incompleteSaved ??= saved;
          continue;
        }
        // Showing automatic readings prefers a valid saved projection over
        // starting another analysis. Explicit online generation retains its
        // configured namespace preference and existing offline fallback.
        final allowed = allowedNamespaces();
        if (allowed.contains(namespace) &&
            (requestMode != JapaneseReadingRequestMode.online ||
                namespace == namespaces.first && allowed.first == namespace)) {
          return JapaneseReadingProjection(
              _displayCopy(source, saved), JapaneseReadingResult.applied);
        }
        if (namespace == 'offline') offlineSaved = saved;
      }
    }
    // A durable hit only validates its saved spans. Split source graphemes for
    // native/memory lookup after that fast display path has missed.
    final plans = <int, List<JapaneseReadingChunk>>{
      for (final entry in candidateTexts.entries)
        entry.key: japaneseReadingChunks(entry.value),
    };
    final wholeChunks = <String, Set<String>>{};
    if (_cache.isNotEmpty) {
      for (final entry in candidateTexts.entries) {
        final full = _content(source.lines[entry.key]);
        final chunks = plans[entry.key]!;
        if (full.length == entry.value.length || chunks.isEmpty) continue;
        final last = chunks.last;
        if (!last.analyzable) continue;
        final whole =
            _wholeSourceChunkAt(full, entry.value.length - last.text.length);
        if (whole != null &&
            whole != last.text &&
            whole.startsWith(last.text)) {
          (wholeChunks[last.text] ??= <String>{}).add(whole);
        }
      }
    }
    final cachedNamespaces =
        <String, Map<String, List<JapanesePhoneticWord>>>{};
    Map<String, List<JapanesePhoneticWord>> cachedChunks(String namespace) =>
        cachedNamespaces.putIfAbsent(namespace, () {
          final result = <String, List<JapanesePhoneticWord>>{};
          for (final chunks in plans.values) {
            for (final chunk in chunks) {
              if (!chunk.analyzable || result.containsKey(chunk.text)) continue;
              final reading = _cachedPrimaryPrefix(namespace, chunk.text,
                  wholeChunks[chunk.text] ?? const <String>[]);
              if (reading != null) result[chunk.text] = reading;
            }
          }
          return result;
        });
    // Some lyric providers use the Chinese simplified 别 in Japanese 別れ.
    // The installed dictionary contains 別れ, but treats 别 as an unknown word.
    // Normalize only qualified Japanese lines for analysis, never their source
    // or the source UTF-16 ranges used by ruby, documents and search.
    final analysisTexts = <String, String>{
      for (final entry in plans.entries)
        if (isJapaneseReadingLanguage(language) ||
            _hasKana(candidateTexts[entry.key]!))
          for (final chunk in entry.value)
            chunk.text: chunk.text.replaceAll('别', '別'),
    };
    var lookupNamespace = namespaces.first;
    final canAnalyze = !cachedOnly && _policy?.canAnalyze(requestMode) != false;
    final refreshChunks = verifyCoverage && canAnalyze;
    if (!refreshChunks &&
        (requestMode != JapaneseReadingRequestMode.online || !canAnalyze)) {
      String? completeNamespace;
      for (final namespace in namespaces) {
        if (plans.values.every((chunks) => chunks.every((chunk) =>
            !chunk.analyzable ||
            cachedChunks(namespace).containsKey(chunk.text)))) {
          completeNamespace = namespace;
          break;
        }
      }
      if (completeNamespace != null) {
        lookupNamespace = completeNamespace;
      } else if (!canAnalyze) {
        if (offlineSaved != null) {
          return JapaneseReadingProjection(_displayCopy(source, offlineSaved),
              JapaneseReadingResult.applied);
        }
        if (cachedOnly && listEquals(namespaces, allowedNamespaces())) {
          _displayCacheMiss = (
            source: source,
            generation: generation,
            namespaces: List.unmodifiable(namespaces),
            owner: stillCurrent,
          );
        }
        return result(JapaneseReadingResult.unchanged);
      }
    }
    final missing = <String>{
      for (final chunks in plans.values)
        for (final chunk in chunks)
          if (chunk.analyzable &&
              (refreshChunks ||
                  !cachedChunks(lookupNamespace).containsKey(chunk.text)))
            chunk.text,
    }.toList();
    // Keep this request's results independent of eviction in the finite cache.
    final readings = <String, List<JapanesePhoneticWord>?>{
      for (final chunks in plans.values)
        for (final chunk in chunks)
          if (!refreshChunks &&
              cachedChunks(lookupNamespace).containsKey(chunk.text))
            chunk.text: cachedChunks(lookupNamespace)[chunk.text],
    };
    var storageNamespace = lookupNamespace;
    var unavailableChunk = false;
    var dictionaryMissing = false;
    for (var offset = 0; offset < missing.length; offset += 16) {
      if (!current()) return result(JapaneseReadingResult.stale);
      final chunks =
          missing.sublist(offset, (offset + 16).clamp(0, missing.length));
      final analysisChunks = List<String>.unmodifiable(
          chunks.map((text) => analysisTexts[text] ?? text));
      JapanesePhoneticBatch batch;
      _nativePending = true;
      try {
        batch = await (_policy?.analyzeWithMode(analysisChunks, requestMode) ??
            _analyze(analysisChunks));
      } catch (_) {
        if (!current()) return result(JapaneseReadingResult.stale);
        return result(JapaneseReadingResult.unavailable);
      } finally {
        if (generation == _generation) _nativePending = false;
      }
      if (!current()) return result(JapaneseReadingResult.stale);
      if (!batch.available || batch.words.length != chunks.length) {
        if (offlineSaved != null && batch.cacheNamespace == 'offline') {
          return JapaneseReadingProjection(_displayCopy(source, offlineSaved),
              JapaneseReadingResult.applied);
        }
        return result(batch.dictionaryMissing
            ? JapaneseReadingResult.dictionaryMissing
            : JapaneseReadingResult.unavailable);
      }
      if (batch.cacheNamespace == 'offline' && offlineSaved != null) {
        return JapaneseReadingProjection(
            _displayCopy(source, offlineSaved), JapaneseReadingResult.applied);
      }
      if (offset == 0 && readings.isEmpty) {
        storageNamespace = batch.cacheNamespace;
      }
      if (batch.cacheNamespace.startsWith('online/')) {
        storageNamespace = batch.cacheNamespace;
      }
      dictionaryMissing |= batch.dictionaryMissing;
      for (var index = 0; index < chunks.length; index++) {
        final words = batch.words[index];
        List<JapanesePhoneticWord>? reading = words != null &&
                words.every((word) => word.text.isNotEmpty) &&
                words.map((word) => word.text).join() == analysisChunks[index]
            ? words
            : null;
        if (reading != null && analysisChunks[index] != chunks[index]) {
          var sourceOffset = 0;
          reading = List.unmodifiable(reading.map((word) {
            final original = chunks[index]
                .substring(sourceOffset, sourceOffset + word.text.length);
            sourceOffset += word.text.length;
            return JapanesePhoneticWord(
                original, word.reading == word.text ? original : word.reading);
          }));
        }
        readings[chunks[index]] = reading;
        if (reading == null) {
          unavailableChunk = true;
        } else {
          _remember(chunks[index], reading, batch.cacheNamespace);
        }
      }
    }
    if (!current()) return result(JapaneseReadingResult.stale);
    final generated = <int, JapaneseCachedReading>{};
    for (final entry in plans.entries) {
      final buffer = StringBuffer();
      final spans = <JapaneseLyricReadingSpan>[];
      var offset = 0;
      for (final chunk in entry.value) {
        final words = readings[chunk.text];
        if (words == null) {
          buffer.write(chunk.text);
          offset += chunk.text.length;
          continue;
        }
        for (final word in words) {
          final reading = !_hasHan(word.text) || word.reading.isEmpty
              ? word.text
              : word.reading;
          buffer.write(reading);
          spans.addAll(
              japaneseReadingWordSpans(word.text, reading, offset: offset));
          offset += word.text.length;
        }
      }
      final reading = buffer.toString();
      if (reading != candidateTexts[entry.key] &&
          !_sameKanaReading(source.lines[entry.key].romanization, reading)) {
        generated[entry.key] =
            JapaneseCachedReading(reading, List.unmodifiable(spans));
      }
    }
    if (generated.isEmpty) {
      if (dictionaryMissing && offlineSaved != null) {
        return JapaneseReadingProjection(
            _displayCopy(source, offlineSaved), JapaneseReadingResult.applied);
      }
      return result(unavailableChunk
          ? dictionaryMissing
              ? JapaneseReadingResult.dictionaryMissing
              : JapaneseReadingResult.unavailable
          : JapaneseReadingResult.unchanged);
    }
    final fingerprint =
        _persistentCache?.fingerprint(source, namespace: storageNamespace);
    if (fingerprint != null && !cachedOnly) {
      final writing = _persistentCache!.write(fingerprint, generated,
          stillCurrent: () =>
              current() && allowedNamespaces().contains(storageNamespace));
      if (waitForCacheWrites) {
        await writing;
        if (!current()) return result(JapaneseReadingResult.stale);
      } else {
        writing.ignore();
      }
    }
    return JapaneseReadingProjection(
        _displayCopy(source, generated), JapaneseReadingResult.applied);
  }

  Lyric _displayCopy(Lyric source, Map<int, JapaneseCachedReading> generated) {
    final copy = source is PlainLyric
        ? (PlainLyric(source.text)
          ..lines.single.romanization = source.lines.single.romanization)
        : LyricSnapshot.capture(source).toLyric();
    for (final entry in generated.entries) {
      final line = copy.lines[entry.key];
      final primary = lyricPrimaryText(line);
      line.japaneseReading = line is UnsyncLyricLine
          ? entry.value.text.split('┃').first
          : entry.value.text;
      // Old exact-source caches may also contain readings for translations.
      // Keep their persisted bytes, but expose only spans the primary paints.
      line.japaneseReadingSpans = _primarySpans(primary, entry.value.spans);
    }
    return copy;
  }

  Map<int, JapaneseCachedReading> _restoreLegacySpans(
      Lyric source, Map<int, JapaneseCachedReading> legacy) {
    return Map.unmodifiable({
      for (final entry in legacy.entries)
        entry.key: () {
          final saved = entry.value;
          // Reattach an already stored full reading using the new iteration /
          // global-anchor alignment; this does not invent or analyze any yomi.
          final aligned = japaneseReadingWordSpans(
              _content(source.lines[entry.key]), saved.text);
          if (aligned.isEmpty) return saved;
          final spans = <JapaneseLyricReadingSpan>[];
          for (final span in aligned) {
            final prior = saved.spans
                .where((old) => old.start >= span.start && old.end <= span.end)
                .toList();
            var cursor = span.start;
            for (final old in prior) {
              if (old.start != cursor) break;
              cursor = old.end;
            }
            // Keep existing contextual word boundaries when they already cover
            // a Han group. Newly complete groups repair missing iteration ruby.
            spans.addAll(cursor == span.end ? prior : [span]);
          }
          return JapaneseCachedReading(saved.text, List.unmodifiable(spans));
        }(),
    });
  }
}
