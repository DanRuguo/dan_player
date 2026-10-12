import 'package:dan_player/lyric/japanese_phonetic_channel.dart';
import 'package:dan_player/lyric/japanese_lyric_cache.dart';
import 'package:dan_player/lyric/japanese_reading_analyzer.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

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

/// Preserve contextual dictionary words. Kana anchors divide Han groups only
/// when their reading alignment is unique; ambiguous words keep a safe whole
/// line reading without inventing per-character pronunciations.
List<JapaneseLyricReadingSpan> japaneseReadingWordSpans(
    String text, String reading,
    {int offset = 0}) {
  if (!_hasHan(text) || text == reading) return const [];
  final groups = <({int start, int end, String text, bool han})>[];
  var position = 0;
  for (final cluster in text.characters) {
    final han = _hasHan(cluster);
    if (groups.isNotEmpty && groups.last.han == han) {
      final last = groups.removeLast();
      groups.add((
        start: last.start,
        end: position + cluster.length,
        text: last.text + cluster,
        han: han
      ));
    } else {
      groups.add((
        start: position,
        end: position + cluster.length,
        text: cluster,
        han: han
      ));
    }
    position += cluster.length;
  }
  final normalized = _hiragana(reading);
  final result = <JapaneseLyricReadingSpan>[];
  var cursor = 0;
  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    if (!group.han) {
      final anchor = _hiragana(group.text);
      if (!normalized.startsWith(anchor, cursor)) return const [];
      cursor += anchor.length;
      continue;
    }
    var end = reading.length;
    if (index + 1 < groups.length) {
      final anchor = _hiragana(groups[index + 1].text);
      if (index + 2 == groups.length && normalized.endsWith(anchor)) {
        end = normalized.length - anchor.length;
      } else {
        end = normalized.indexOf(anchor, cursor);
        if (end < 0 || normalized.indexOf(anchor, end + 1) >= 0) {
          return const [];
        }
      }
    }
    if (end <= cursor) return const [];
    final yomi = reading.substring(cursor, end);
    if (!_hasKana(yomi) || _hasHan(yomi)) return const [];
    result.add(JapaneseLyricReadingSpan(
        start: offset + group.start, end: offset + group.end, text: yomi));
    cursor = end;
  }
  return cursor == reading.length ? List.unmodifiable(result) : const [];
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
        !_hasHan(source.substring(span.start, span.end))) {
      return false;
    }
    previousEnd = span.end;
  }
  return true;
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

  Future<JapaneseReadingProjection> project(Lyric source,
          {String? language,
          required bool enabled,
          bool force = false,
          JapaneseReadingRequestMode requestMode =
              JapaneseReadingRequestMode.automatic,
          required bool Function() stillCurrent}) =>
      _project(source,
          language: language,
          enabled: enabled,
          force: force,
          requestMode: requestMode,
          stillCurrent: stillCurrent);

  /// Restore a previously authorized, valid display without analysis or writes.
  /// An exact cached source may contain only Han text: restoring that fingerprint
  /// does not need to guess its language or authorize another generation.
  Future<JapaneseReadingProjection> projectCached(Lyric source,
          {String? language, required bool Function() stillCurrent}) =>
      _project(source,
          language: language,
          enabled: true,
          force: true,
          cachedOnly: true,
          stillCurrent: stillCurrent);

  Future<JapaneseReadingProjection> _project(Lyric source,
      {String? language,
      required bool enabled,
      bool force = false,
      bool cachedOnly = false,
      JapaneseReadingRequestMode requestMode =
          JapaneseReadingRequestMode.automatic,
      required bool Function() stillCurrent}) async {
    final priorGeneration = _generation;
    final displayCacheMiss = _displayCacheMiss;
    final cacheOwnerCurrent = displayCacheMiss?.owner() == true;
    cancel();
    final generation = _generation;
    bool current() => generation == _generation && stillCurrent();
    JapaneseReadingProjection result(JapaneseReadingResult reason) =>
        JapaneseReadingProjection(source, reason);
    if (!current()) return result(JapaneseReadingResult.stale);
    if (!enabled && !force) return result(JapaneseReadingResult.unchanged);
    var totalUnits = 0;
    for (final line in source.lines) {
      totalUnits += _content(line).length;
      if (totalUnits > maximumInputUnits) {
        return result(JapaneseReadingResult.tooLarge);
      }
    }
    if (!force &&
        !isJapaneseReadingLanguage(language) &&
        !source.lines.any((line) => _hasKana(_content(line)))) {
      return result(JapaneseReadingResult.unchanged);
    }

    final plans = <int, List<JapaneseReadingChunk>>{};
    var inputUnits = 0;
    for (var index = 0; index < source.lines.length; index++) {
      final line = source.lines[index];
      final text = _content(line);
      if (!_hasHan(text)) continue;
      inputUnits += text.length;
      if (inputUnits > maximumInputUnits) {
        return result(JapaneseReadingResult.tooLarge);
      }
      plans[index] = japaneseReadingChunks(text);
    }
    if (plans.isEmpty) return result(JapaneseReadingResult.unchanged);
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
      final saved =
          await _persistentCache!.read(fingerprint, stillCurrent: current);
      if (!current()) return result(JapaneseReadingResult.stale);
      if (saved != null &&
          saved.entries.every((entry) =>
              plans.containsKey(entry.key) &&
              _validSaved(_content(source.lines[entry.key]), entry.value))) {
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
    var lookupNamespace = namespaces.first;
    final canAnalyze = !cachedOnly && _policy?.canAnalyze(requestMode) != false;
    if (requestMode != JapaneseReadingRequestMode.online || !canAnalyze) {
      String? completeNamespace;
      for (final namespace in namespaces) {
        if (plans.values.every((chunks) => chunks.every((chunk) =>
            !chunk.analyzable ||
            _cache.containsKey('$namespace\u0000${chunk.text}')))) {
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
              !_cache.containsKey('$lookupNamespace\u0000${chunk.text}'))
            chunk.text,
    }.toList();
    // Keep this request's results independent of eviction in the finite cache.
    final readings = <String, List<JapanesePhoneticWord>?>{
      for (final chunks in plans.values)
        for (final chunk in chunks)
          if (_cache.containsKey('$lookupNamespace\u0000${chunk.text}'))
            chunk.text: _cache['$lookupNamespace\u0000${chunk.text}'],
    };
    var storageNamespace = lookupNamespace;
    var unavailableChunk = false;
    var dictionaryMissing = false;
    for (var offset = 0; offset < missing.length; offset += 16) {
      if (!current()) return result(JapaneseReadingResult.stale);
      final chunks =
          missing.sublist(offset, (offset + 16).clamp(0, missing.length));
      JapanesePhoneticBatch batch;
      _nativePending = true;
      try {
        batch = await (_policy?.analyzeWithMode(
                List.unmodifiable(chunks), requestMode) ??
            _analyze(List.unmodifiable(chunks)));
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
        final reading = words != null &&
                words.every((word) => word.text.isNotEmpty) &&
                words.map((word) => word.text).join() == chunks[index]
            ? words
            : null;
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
      if (reading != _content(source.lines[entry.key]) &&
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
      copy.lines[entry.key].japaneseReading = entry.value.text;
      copy.lines[entry.key].japaneseReadingSpans = entry.value.spans;
    }
    return copy;
  }
}
