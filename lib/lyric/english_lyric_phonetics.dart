import 'package:dan_player/lyric/english_phonetic_cache.dart';
import 'package:dan_player/lyric/english_phonetic_lexicon.dart';
import 'package:dan_player/lyric/english_phonetic_preferences.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_document.dart';
import 'package:dan_player/lyric/lyric_primary_text.dart';
import 'package:dan_player/lyric/plain_lyric.dart';

enum EnglishPhoneticResult {
  applied,
  unchanged,
  unavailable,
  tooLarge,
  stale,
}

class EnglishPhoneticProjection {
  const EnglishPhoneticProjection(this.lyric, this.result);
  final Lyric lyric;
  final EnglishPhoneticResult result;
}

bool hasEnglishPhonetics(Lyric? lyric) =>
    lyric?.lines.any((line) {
      final content = lyricPrimaryText(line);
      return line.englishPhoneticSpans.any((span) =>
          span.start >= 0 &&
          span.end > span.start &&
          span.end <= content.length &&
          span.text.trim().isNotEmpty);
    }) ==
    true;

/// Projects offline English word IPA phonetics onto a display copy of [Lyric],
/// preserving any existing Japanese readings and never mutating authored files.
class EnglishPhoneticProjector {
  EnglishPhoneticProjector({
    Future<EnglishPhoneticLexicon?> Function()? loadLexicon,
    EnglishLyricPhoneticCache? persistentCache,
    this.maximumCachedLines = 512,
    this.maximumLines = 600,
    this.maximumCharacters = 64000,
    this.waitForCacheWrites = false,
  })  : _loadLexicon = loadLexicon ?? EnglishPhoneticLexicon.loadBundled,
        _persistentCache = persistentCache ??
            (loadLexicon == null ? EnglishLyricPhoneticCache.instance : null);

  factory EnglishPhoneticProjector.background({
    Future<EnglishPhoneticLexicon?> Function()? loadLexicon,
    EnglishLyricPhoneticCache? persistentCache,
  }) =>
      EnglishPhoneticProjector(
        loadLexicon: loadLexicon,
        persistentCache: persistentCache,
        maximumCachedLines: 256,
        waitForCacheWrites: true,
      );

  final Future<EnglishPhoneticLexicon?> Function() _loadLexicon;
  final EnglishLyricPhoneticCache? _persistentCache;
  final int maximumCachedLines;
  final int maximumLines;
  final int maximumCharacters;
  final bool waitForCacheWrites;

  final _lineCache = <String, EnglishCachedPhonetic?>{};
  int _generation = 0;
  bool _disposed = false;

  void cancel() {
    _generation++;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _lineCache.clear();
  }

  Future<EnglishPhoneticProjection> projectCached(
    Lyric source, {
    EnglishPhoneticStyle style = EnglishPhoneticStyle.plain,
    bool Function()? stillCurrent,
  }) async {
    final token = _generation;
    bool current() =>
        !_disposed && token == _generation && (stillCurrent?.call() ?? true);
    if (!current()) {
      return EnglishPhoneticProjection(source, EnglishPhoneticResult.stale);
    }
    final cache = _persistentCache;
    if (cache == null || !lyricHasEnglishCandidates(source)) {
      return EnglishPhoneticProjection(source, EnglishPhoneticResult.unchanged);
    }
    final fingerprint = cache.fingerprint(source);
    final saved = await cache.read(fingerprint, stillCurrent: current);
    if (!current()) {
      return EnglishPhoneticProjection(source, EnglishPhoneticResult.stale);
    }
    if (saved == null || saved.isEmpty) {
      return EnglishPhoneticProjection(source, EnglishPhoneticResult.unchanged);
    }
    return EnglishPhoneticProjection(
      _displayCopy(source, saved, style: style),
      EnglishPhoneticResult.applied,
    );
  }

  Future<EnglishPhoneticProjection> project(
    Lyric source, {
    required bool enabled,
    EnglishPhoneticStyle style = EnglishPhoneticStyle.plain,
    bool force = false,
    bool Function()? stillCurrent,
  }) async {
    final token = ++_generation;
    bool current() =>
        !_disposed && token == _generation && (stillCurrent?.call() ?? true);
    EnglishPhoneticProjection result(EnglishPhoneticResult reason) =>
        EnglishPhoneticProjection(source, reason);

    if (!current()) return result(EnglishPhoneticResult.stale);
    if (!enabled && !force) return result(EnglishPhoneticResult.unchanged);
    if (!lyricHasEnglishCandidates(source)) {
      return result(EnglishPhoneticResult.unchanged);
    }
    if (source.lines.length > maximumLines) {
      return result(EnglishPhoneticResult.tooLarge);
    }
    var totalChars = 0;
    for (final line in source.lines) {
      totalChars += lyricPrimaryText(line).length;
      if (totalChars > maximumCharacters) {
        return result(EnglishPhoneticResult.tooLarge);
      }
    }

    final cache = _persistentCache;
    final fingerprint = cache?.fingerprint(source);
    if (cache != null && fingerprint != null) {
      final saved = await cache.read(fingerprint, stillCurrent: current);
      if (!current()) return result(EnglishPhoneticResult.stale);
      if (saved != null && saved.isNotEmpty) {
        return EnglishPhoneticProjection(
          _displayCopy(source, saved, style: style),
          EnglishPhoneticResult.applied,
        );
      }
    }

    final lexicon = await _loadLexicon();
    if (!current()) return result(EnglishPhoneticResult.stale);
    if (lexicon == null) return result(EnglishPhoneticResult.unavailable);

    // Intra-song memoization avoids re-annotating repeated choruses (including
    // lines > 512 chars that bypass the cross-song LRU cache).
    final songMemo = <String, EnglishCachedPhonetic?>{};

    EnglishCachedPhonetic? annotateSingleLine(String lineText) {
      if (lineText.trim().isEmpty) return null;
      if (songMemo.containsKey(lineText)) {
        return songMemo[lineText];
      }
      if (_lineCache.containsKey(lineText)) {
        final cached = _lineCache.remove(lineText);
        _lineCache[lineText] = cached;
        songMemo[lineText] = cached;
        return cached;
      }
      final annotated = lexicon.annotateLine(
        lineText,
        style: EnglishPhoneticStyle.plain,
      );
      final entry = annotated.spans.isEmpty
          ? null
          : EnglishCachedPhonetic(annotated.fullText, annotated.spans);
      songMemo[lineText] = entry;
      if (lineText.length <= 512) {
        _lineCache[lineText] = entry;
        while (_lineCache.length > maximumCachedLines) {
          _lineCache.remove(_lineCache.keys.first);
        }
      }
      return entry;
    }

    final generated = <int, EnglishCachedPhonetic>{};
    for (var i = 0; i < source.lines.length; i++) {
      if (!current()) return result(EnglishPhoneticResult.stale);
      final primary = lyricPrimaryText(source.lines[i]);
      if (primary.trim().isEmpty) continue;
      EnglishCachedPhonetic? entry;
      if (primary.contains('\n')) {
        // Multi-line PlainLyric (e.g. embedded USLT / .txt) is evaluated per
        // subline while preserving exact UTF-16 span offsets into the full
        // paragraph, enabling bilingual English + CJK plain-text IPA display
        // and per-line chorus caching.
        final combinedSpans = <EnglishLyricPhoneticSpan>[];
        var offset = 0;
        var sublineIndex = 0;
        while (offset <= primary.length) {
          final nl = primary.indexOf('\n', offset);
          final end = nl < 0 ? primary.length : nl;
          var sublineEnd = end;
          if (sublineEnd > offset &&
              primary.codeUnitAt(sublineEnd - 1) == 0x0D) {
            sublineEnd--;
          }
          if (sublineEnd > offset) {
            final subline = primary.substring(offset, sublineEnd);
            final subEntry = annotateSingleLine(subline);
            if (subEntry != null) {
              for (final span in subEntry.spans) {
                combinedSpans.add(EnglishLyricPhoneticSpan(
                  start: offset + span.start,
                  end: offset + span.end,
                  text: span.text,
                ));
              }
            }
          }
          sublineIndex++;
          if (sublineIndex % 64 == 0) {
            await Future<void>.delayed(Duration.zero);
            if (!current()) return result(EnglishPhoneticResult.stale);
          }
          if (nl < 0) break;
          offset = nl + 1;
        }
        if (combinedSpans.isNotEmpty) {
          entry = EnglishCachedPhonetic(
            combinedSpans.map((s) => s.text).join(' '),
            List<EnglishLyricPhoneticSpan>.unmodifiable(combinedSpans),
          );
        }
      } else {
        entry = annotateSingleLine(primary);
      }
      if (entry != null && entry.spans.isNotEmpty) {
        generated[i] = entry;
      }
      if (i > 0 && i % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (!current()) return result(EnglishPhoneticResult.stale);
    if (generated.isEmpty) {
      return result(EnglishPhoneticResult.unchanged);
    }

    if (cache != null && fingerprint != null) {
      final writing = cache.write(
        fingerprint,
        generated,
        stillCurrent: current,
      );
      if (waitForCacheWrites) {
        await writing;
        if (!current()) return result(EnglishPhoneticResult.stale);
      } else {
        writing.ignore();
      }
    }

    return EnglishPhoneticProjection(
      _displayCopy(source, generated, style: style),
      EnglishPhoneticResult.applied,
    );
  }

  Lyric _displayCopy(
    Lyric source,
    Map<int, EnglishCachedPhonetic> generated, {
    required EnglishPhoneticStyle style,
  }) {
    final copy = source is PlainLyric
        ? (PlainLyric(source.text)
          ..lines.single.romanization = source.lines.single.romanization)
        : LyricSnapshot.capture(source).toLyric();

    // Preserve any existing Japanese reading spans on bilingual songs.
    final count = source.lines.length < copy.lines.length
        ? source.lines.length
        : copy.lines.length;
    for (var i = 0; i < count; i++) {
      copy.lines[i].japaneseReading = source.lines[i].japaneseReading;
      copy.lines[i].japaneseReadingSpans = source.lines[i].japaneseReadingSpans;
    }

    for (final entry in generated.entries) {
      if (entry.key < 0 || entry.key >= copy.lines.length) continue;
      final line = copy.lines[entry.key];
      final primary = lyricPrimaryText(line);
      final styledSpans = <EnglishLyricPhoneticSpan>[];
      for (final span in entry.value.spans) {
        if (span.start < 0 ||
            span.end <= span.start ||
            span.end > primary.length ||
            span.text.isEmpty) {
          continue;
        }
        styledSpans.add(EnglishLyricPhoneticSpan(
          start: span.start,
          end: span.end,
          text: style.format(span.text),
        ));
      }
      if (styledSpans.isNotEmpty) {
        line.englishPhoneticSpans = List.unmodifiable(styledSpans);
        line.englishPhonetic = styledSpans.map((s) => s.text).join(' ');
      }
    }
    return copy;
  }
}
