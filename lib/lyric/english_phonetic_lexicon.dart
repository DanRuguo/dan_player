import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data' show Endian;

import 'package:dan_player/lyric/english_phonetic_preferences.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:flutter/services.dart';

/// Compact offline General American IPA lexicon backed by the bundled
/// `DANENG01` blocked prefix-compressed binary asset (derived from CMUDict).
///
/// The decompressed lexicon stays in a single ~2.2 MB byte buffer and performs
/// binary search over 32-word prefix-compressed blocks with zero Dart Map heap
/// overhead. Non-English Latin words are never guessed via blind G2P.
class EnglishPhoneticLexicon {
  EnglishPhoneticLexicon._(
    this._data,
    this.entryCount,
    this._blockSize,
    this._blockCount,
  ) : _payloadStart = 16 + _blockCount * 4;

  static const assetPath = 'assets/dictionaries/cmudict_ipa.bin.gz';
  static const engineVersion = 'daneng-v1-cmudict-ga-ipa';
  static const _magic = <int>[0x44, 0x41, 0x4E, 0x45, 0x4E, 0x47, 0x30, 0x31];

  static Future<EnglishPhoneticLexicon?>? _sharedLoad;
  static EnglishPhoneticLexicon? _sharedInstance;

  final Uint8List _data;
  final int entryCount;
  final int _blockSize;
  final int _blockCount;
  final int _payloadStart;

  /// Lazily loads and caches the bundled offline lexicon on first use.
  static Future<EnglishPhoneticLexicon?> loadBundled({
    Future<Uint8List> Function()? loadCompressed,
  }) {
    if (loadCompressed == null && _sharedInstance != null) {
      return Future.value(_sharedInstance);
    }
    if (loadCompressed == null && _sharedLoad != null) {
      return _sharedLoad!;
    }
    final pending = _loadInternal(loadCompressed);
    if (loadCompressed == null) {
      _sharedLoad = pending.then((lexicon) {
        _sharedInstance = lexicon;
        if (lexicon == null) _sharedLoad = null;
        return lexicon;
      }, onError: (Object _, StackTrace __) {
        _sharedLoad = null;
        return null;
      });
      return _sharedLoad!;
    }
    return pending;
  }

  static Future<EnglishPhoneticLexicon?> _loadInternal(
    Future<Uint8List> Function()? loadCompressed,
  ) async {
    try {
      final compressed = loadCompressed != null
          ? await loadCompressed()
          : (await rootBundle.load(assetPath)).buffer.asUint8List();
      if (compressed.isEmpty) return null;
      final raw = await Isolate.run(
        () => Uint8List.fromList(gzip.decode(compressed)),
      );
      return EnglishPhoneticLexicon.fromBytes(raw);
    } catch (_) {
      return null;
    }
  }

  /// Parses an uncompressed `DANENG01` buffer. Returns `null` if invalid.
  static EnglishPhoneticLexicon? fromBytes(Uint8List data) {
    if (data.length < 16) return null;
    for (var i = 0; i < 8; i++) {
      if (data[i] != _magic[i]) return null;
    }
    final view = ByteData.sublistView(data);
    final entryCount = view.getUint32(8, Endian.little);
    final blockSize = view.getUint16(12, Endian.little);
    final blockCount = view.getUint16(14, Endian.little);
    final payloadStart = 16 + blockCount * 4;
    if (blockSize == 0 ||
        blockCount == 0 ||
        entryCount == 0 ||
        payloadStart > data.length) {
      return null;
    }
    return EnglishPhoneticLexicon._(data, entryCount, blockSize, blockCount);
  }

  int _blockOffset(int blockIndex) {
    final pos = 16 + blockIndex * 4;
    return _data[pos] |
        (_data[pos + 1] << 8) |
        (_data[pos + 2] << 16) |
        (_data[pos + 3] << 24);
  }

  static int _compareBytes(
    Uint8List a,
    int aOffset,
    int aLen,
    Uint8List b,
    int bLen,
  ) {
    final limit = aLen < bLen ? aLen : bLen;
    for (var i = 0; i < limit; i++) {
      final diff = a[aOffset + i] - b[i];
      if (diff != 0) return diff;
    }
    return aLen - bLen;
  }

  /// Exact lookup for a normalized lowercase ASCII word (letters & apostrophe).
  String? lookupExact(String lowerWord) {
    final targetLen = lowerWord.length;
    if (targetLen == 0 || targetLen > 64) return null;
    final target = Uint8List(targetLen);
    for (var i = 0; i < targetLen; i++) {
      final unit = lowerWord.codeUnitAt(i);
      if (unit > 0x7f) return null;
      target[i] = unit;
    }

    var low = 0;
    var high = _blockCount - 1;
    var candidate = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final pos = _payloadStart + _blockOffset(mid);
      if (pos >= _data.length) return null;
      final firstLen = _data[pos];
      if (pos + 1 + firstLen > _data.length) return null;
      final cmp = _compareBytes(_data, pos + 1, firstLen, target, targetLen);
      if (cmp == 0) {
        final ipaPos = pos + 1 + firstLen;
        if (ipaPos >= _data.length) return null;
        final ipaLen = _data[ipaPos];
        if (ipaPos + 1 + ipaLen > _data.length) return null;
        return utf8.decode(_data.sublist(ipaPos + 1, ipaPos + 1 + ipaLen));
      }
      if (cmp < 0) {
        candidate = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (candidate < 0) return null;

    var pos = _payloadStart + _blockOffset(candidate);
    final blockEnd = candidate + 1 < _blockCount
        ? _payloadStart + _blockOffset(candidate + 1)
        : _data.length;
    if (blockEnd > _data.length) return null;

    final keyBuf = Uint8List(256);
    var keyLen = 0;
    for (var entry = 0; entry < _blockSize && pos < blockEnd; entry++) {
      if (entry == 0) {
        keyLen = _data[pos++];
        if (pos + keyLen > blockEnd) return null;
        keyBuf.setRange(0, keyLen, _data, pos);
        pos += keyLen;
      } else {
        if (pos + 2 > blockEnd) return null;
        final shared = _data[pos++];
        final suffixLen = _data[pos++];
        if (shared > keyLen ||
            shared + suffixLen > keyBuf.length ||
            pos + suffixLen > blockEnd) {
          return null;
        }
        keyBuf.setRange(shared, shared + suffixLen, _data, pos);
        pos += suffixLen;
        keyLen = shared + suffixLen;
      }
      if (pos >= blockEnd) return null;
      final ipaLen = _data[pos++];
      if (pos + ipaLen > blockEnd) return null;
      final cmp = _compareBytes(keyBuf, 0, keyLen, target, targetLen);
      if (cmp == 0) {
        return utf8.decode(_data.sublist(pos, pos + ipaLen));
      }
      if (cmp > 0) return null;
      pos += ipaLen;
    }
    return null;
  }

  static const _leadingApostropheMap = <String, String>{
    "'cause": 'kɔːz',
    "'til": 'tɪl',
    "'em": 'əm',
    "'round": 'raʊnd',
    "'bout": 'baʊt',
    "'neath": 'niːθ',
    "'tween": 'twiːn',
    "'twas": 'twʌz',
    "'tis": 'tɪz',
    "'n'": 'ən',
    "'n": 'ən',
  };

  static const _prefixes = <(String, String)>[
    ('un', 'ʌn'),
    ('re', 'riː'),
    ('non', 'nɑːn'),
    ('pre', 'priː'),
    ('over', 'ˌoʊvər'),
    ('under', 'ˌʌndər'),
    ('out', 'aʊt'),
    ('sub', 'sʌb'),
    ('mis', 'mɪs'),
    ('dis', 'dɪs'),
    ('anti', 'ˌænti'),
    ('super', 'ˌsuːpər'),
    ('semi', 'ˌsɛmi'),
    ('multi', 'ˌmʌlti'),
    ('hyper', 'ˌhaɪpər'),
    ('ultra', 'ˌʌltrə'),
    ('mini', 'ˌmɪni'),
    ('micro', 'ˌmaɪkroʊ'),
    ('mega', 'ˌmɛɡə'),
    ('self', 'sɛlf'),
  ];

  /// Resolves an English word token (Tier 1 dictionary + Tier 2 verified
  /// contractions, British aliases, and regular English morphology).
  /// Returns plain IPA without delimiters, or `null` if unknown.
  String? resolveWord(String rawToken) {
    if (rawToken.isEmpty || rawToken.length > 48) return null;
    final word = rawToken.toLowerCase().replaceAll('\u2019', "'");

    // Tier 1: leading-apostrophe lyric contractions & exact CMUDict lookup.
    final leading = _leadingApostropheMap[word];
    if (leading != null) return leading;
    final direct = lookupExact(word);
    if (direct != null) return direct;

    // Tier 2a: g-dropping `-in'` participles & plural possessives `-s'`.
    if (word.endsWith("in'") && word.length >= 4) {
      final withoutApos = word.substring(0, word.length - 1);
      final cur = lookupExact(withoutApos);
      if (cur != null) return cur;
      final ing = lookupExact('${withoutApos}g') ?? _resolveInflected('${withoutApos}g');
      if (ing != null && ing.endsWith('ŋ')) {
        return '${ing.substring(0, ing.length - 1)}n';
      }
    }
    if (word.endsWith("s'") && word.length >= 3) {
      final stripped = word.substring(0, word.length - 1);
      final res = lookupExact(stripped) ?? _resolveInflected(stripped);
      if (res != null) return res;
    }

    // Tier 2b: apostrophe contractions & possessives (`'s`, `'ll`, `'ve`, `'re`, `'d`, `'m`).
    final apos = word.lastIndexOf("'");
    if (apos > 0 && apos < word.length - 1) {
      final stem = word.substring(0, apos);
      final suffix = word.substring(apos + 1);
      final stemIpa =
          lookupExact(stem) ?? _resolveBritishAlias(stem) ?? _resolveInflected(stem);
      if (stemIpa != null) {
        switch (suffix) {
          case 's':
            return _appendS(stemIpa);
          case 'd':
            return _appendD(stemIpa);
          case 'll':
            return _endsWithVowelIpa(stemIpa) ? '${stemIpa}l' : '$stemIpaəl';
          case 've':
            return '${stemIpa}v';
          case 're':
            return '${stemIpa}r';
          case 'm':
            return '${stemIpa}m';
        }
      }
    }

    // Tier 2c: British -> American spelling aliases.
    final british = _resolveBritishAlias(word);
    if (british != null) return british;

    // Tier 2d: stem-verified regular inflections/derivations & prefixes.
    return _resolveInflected(word);
  }

  String? _resolveBritishAlias(String word) {
    if (word.length < 4 || word.contains("'")) return null;
    final candidates = <String>[];
    if (word.endsWith('our')) {
      candidates.add('${word.substring(0, word.length - 3)}or');
    } else if (word.endsWith('ours')) {
      candidates.add('${word.substring(0, word.length - 4)}ors');
    } else if (word.endsWith('oured')) {
      candidates.add('${word.substring(0, word.length - 5)}ored');
    } else if (word.endsWith('ouring')) {
      candidates.add('${word.substring(0, word.length - 6)}oring');
    } else if (word.endsWith('ise')) {
      candidates.add('${word.substring(0, word.length - 3)}ize');
    } else if (word.endsWith('ised')) {
      candidates.add('${word.substring(0, word.length - 4)}ized');
    } else if (word.endsWith('ising')) {
      candidates.add('${word.substring(0, word.length - 5)}izing');
    } else if (word.endsWith('ises')) {
      candidates.add('${word.substring(0, word.length - 4)}izes');
    } else if (word.endsWith('isation')) {
      candidates.add('${word.substring(0, word.length - 7)}ization');
    } else if (word.endsWith('re') && word.length >= 5) {
      candidates.add('${word.substring(0, word.length - 2)}er');
    } else if (word.endsWith('ence') && word.length >= 6) {
      candidates.add('${word.substring(0, word.length - 4)}ense');
    } else if (word.endsWith('lling') && word.length >= 7) {
      candidates.add('${word.substring(0, word.length - 5)}ling');
    } else if (word.endsWith('lled') && word.length >= 6) {
      candidates.add('${word.substring(0, word.length - 4)}led');
    } else if (word.endsWith('llous') && word.length >= 7) {
      candidates.add('${word.substring(0, word.length - 5)}lous');
    }
    for (final candidate in candidates) {
      final hit = lookupExact(candidate);
      if (hit != null) return hit;
    }
    return null;
  }

  String? _resolveInflected(String word) {
    if (word.length < 4 || word.contains("'")) return null;

    // -ies -> -y + s
    if (word.endsWith('ies') && word.length >= 5) {
      final stem = '${word.substring(0, word.length - 3)}y';
      final ipa = lookupExact(stem);
      if (ipa != null) return _appendS(ipa);
    }
    // -es / -s
    if (word.endsWith('es') && word.length >= 4) {
      final stem = word.substring(0, word.length - 2);
      final ipa = lookupExact(stem);
      if (ipa != null) return _appendS(ipa);
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length >= 4) {
      final stem = word.substring(0, word.length - 1);
      final ipa = lookupExact(stem);
      if (ipa != null) return _appendS(ipa);
    }
    // -ied -> -y + ed
    if (word.endsWith('ied') && word.length >= 5) {
      final stem = '${word.substring(0, word.length - 3)}y';
      final ipa = lookupExact(stem);
      if (ipa != null) return _appendEd(ipa);
    }
    // -ed / -d / doubled consonant + ed
    if (word.endsWith('ed') && word.length >= 5) {
      final withoutEd = word.substring(0, word.length - 2);
      final withoutD = word.substring(0, word.length - 1);
      final ipa = lookupExact(withoutEd) ??
          lookupExact(withoutD) ??
          (_hasDoubledTail(withoutEd)
              ? lookupExact(withoutEd.substring(0, withoutEd.length - 1))
              : null);
      if (ipa != null) return _appendEd(ipa);
    }
    // -ing / silent-e + ing / doubled consonant + ing
    if (word.endsWith('ing') && word.length >= 6) {
      final base = word.substring(0, word.length - 3);
      final ipa = lookupExact(base) ??
          lookupExact('${base}e') ??
          (_hasDoubledTail(base)
              ? lookupExact(base.substring(0, base.length - 1))
              : null);
      if (ipa != null) return '$ipaɪŋ';
    }
    // Transparent derivational suffixes
    if (word.endsWith('ness') && word.length >= 7) {
      final base = word.substring(0, word.length - 4);
      final ipa = lookupExact(base) ??
          (base.endsWith('i')
              ? lookupExact('${base.substring(0, base.length - 1)}y')
              : null);
      if (ipa != null) return '${ipa}nəs';
    }
    if (word.endsWith('less') && word.length >= 7) {
      final base = word.substring(0, word.length - 4);
      final ipa = lookupExact(base);
      if (ipa != null) return '${ipa}ləs';
    }
    if (word.endsWith('ful') && word.length >= 6) {
      final base = word.substring(0, word.length - 3);
      final ipa = lookupExact(base);
      if (ipa != null) return '${ipa}fəl';
    }
    if (word.endsWith('ly') && word.length >= 5) {
      final base = word.substring(0, word.length - 2);
      final ipa = lookupExact(base) ??
          (base.endsWith('i')
              ? lookupExact('${base.substring(0, base.length - 1)}y')
              : null);
      if (ipa != null) return '${ipa}li';
    }
    if (word.endsWith('est') && word.length >= 6) {
      final base = word.substring(0, word.length - 3);
      final ipa = lookupExact(base) ??
          lookupExact('${base}e') ??
          (base.endsWith('i')
              ? lookupExact('${base.substring(0, base.length - 1)}y')
              : null);
      if (ipa != null) return '$ipaɪst';
    }
    if (word.endsWith('er') && word.length >= 5) {
      final base = word.substring(0, word.length - 2);
      final ipa = lookupExact(base) ??
          lookupExact('${base}e') ??
          (base.endsWith('i')
              ? lookupExact('${base.substring(0, base.length - 1)}y')
              : null);
      if (ipa != null) return '$ipaər';
    }
    // Common transparent prefixes on verified stems >= 3 chars.
    for (final (prefix, prefixIpa) in _prefixes) {
      if (word.length >= prefix.length + 3 && word.startsWith(prefix)) {
        final stem = word.substring(prefix.length);
        final stemIpa = lookupExact(stem);
        if (stemIpa != null) {
          final markedStem =
              stemIpa.contains('ˈ') ? stemIpa : 'ˈ$stemIpa';
          return '$prefixIpa$markedStem';
        }
      }
    }
    return null;
  }

  static bool _hasDoubledTail(String text) =>
      text.length >= 3 &&
      text.codeUnitAt(text.length - 1) == text.codeUnitAt(text.length - 2);

  static bool _endsWithSibilant(String ipa) =>
      ipa.endsWith('s') ||
      ipa.endsWith('z') ||
      ipa.endsWith('ʃ') ||
      ipa.endsWith('ʒ');

  static bool _endsWithVoiceless(String ipa) =>
      ipa.endsWith('p') ||
      ipa.endsWith('t') ||
      ipa.endsWith('k') ||
      ipa.endsWith('f') ||
      ipa.endsWith('θ') ||
      ipa.endsWith('s') ||
      ipa.endsWith('ʃ');

  static bool _endsWithVowelIpa(String ipa) {
    if (ipa.isEmpty) return false;
    final last = ipa.codeUnitAt(ipa.length - 1);
    return last == 0x02D0 || // ː
        last == 0x0251 || // ɑ
        last == 0x00E6 || // æ
        last == 0x028C || // ʌ
        last == 0x0254 || // ɔ
        last == 0x0259 || // ə
        last == 0x025B || // ɛ
        last == 0x025C || // ɜ
        last == 0x026A || // ɪ
        last == 0x0069 || // i
        last == 0x028A || // ʊ
        last == 0x0075; // u
  }

  static String _appendS(String ipa) {
    if (_endsWithSibilant(ipa)) return '$ipaɪz';
    if (_endsWithVoiceless(ipa)) return '${ipa}s';
    return '${ipa}z';
  }

  static String _appendEd(String ipa) {
    if (ipa.endsWith('t') || ipa.endsWith('d')) return '$ipaɪd';
    if (_endsWithVoiceless(ipa)) return '${ipa}t';
    return '${ipa}d';
  }

  static String _appendD(String ipa) {
    if (ipa.endsWith('t') || ipa.endsWith('d')) return '$ipaəd';
    return '${ipa}d';
  }

  /// Extracts English IPA spans for one primary lyric line.
  ///
  /// Spans reference exact UTF-16 offsets in [primaryText]. Applies a
  /// line-level recognition ratio guard so romaji, pinyin, Spanish, French or
  /// German lines do not receive spurious IPA on 1–2 letter coincidences.
  ({String fullText, List<EnglishLyricPhoneticSpan> spans}) annotateLine(
    String primaryText, {
    EnglishPhoneticStyle style = EnglishPhoneticStyle.plain,
  }) {
    final tokens = tokenizeEnglishWords(primaryText);
    if (tokens.isEmpty) {
      return (fullText: '', spans: const []);
    }

    var totalWords = 0;
    var matchedWords = 0;
    var hasLongMatch = false;
    final rawSpans = <({int start, int end, String ipa})>[];

    for (final token in tokens) {
      totalWords++;
      final ipa = resolveWord(token.text);
      if (ipa != null && ipa.isNotEmpty) {
        matchedWords++;
        if (token.text.length >= 3) hasLongMatch = true;
        rawSpans.add((start: token.start, end: token.end, ipa: ipa));
      }
    }

    if (matchedWords == 0) {
      return (fullText: '', spans: const []);
    }
    // Guard against non-English Latin lines (romaji/Spanish/French/pinyin).
    if (totalWords >= 3 && matchedWords * 2 < totalWords) {
      return (fullText: '', spans: const []);
    }
    if (totalWords >= 2 && matchedWords < totalWords && !hasLongMatch) {
      return (fullText: '', spans: const []);
    }

    final spans = List<EnglishLyricPhoneticSpan>.unmodifiable([
      for (final entry in rawSpans)
        EnglishLyricPhoneticSpan(
          start: entry.start,
          end: entry.end,
          text: style.format(entry.ipa),
        ),
    ]);
    final fullText = spans.map((span) => span.text).join(' ');
    return (fullText: fullText, spans: spans);
  }
}

/// Tokenized ASCII Latin word with exact UTF-16 [start]..[end] bounds.
class EnglishWordToken {
  const EnglishWordToken(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

bool _isAsciiDigit(int unit) => unit >= 0x30 && unit <= 0x39;

bool _isApostrophe(int unit) => unit == 0x27 || unit == 0x2019;

final _urlOrEmailSpanPattern = RegExp(
  r'(?:https?|ftp)://\S+|www\.\S+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
  caseSensitive: false,
);

List<(int, int)> _findUrlOrEmailRanges(String text) {
  if (!text.contains('://') &&
      !text.contains('@') &&
      !text.contains('www.') &&
      !text.contains('WWW.')) {
    return const [];
  }
  return [
    for (final m in _urlOrEmailSpanPattern.allMatches(text)) (m.start, m.end),
  ];
}

bool _overlapsRange(List<(int, int)> ranges, int start, int end) {
  for (final (rStart, rEnd) in ranges) {
    if (start < rEnd && end > rStart) return true;
  }
  return false;
}

bool _isUrlOrEmailNeighbor(String text, int start, int end) {
  if (start > 0) {
    final prev = text.codeUnitAt(start - 1);
    if (_isAsciiDigit(prev) || prev == 0x40 || prev == 0x5F) return true; // digit, @, _
    if (prev == 0x2F && start >= 2 && text.codeUnitAt(start - 2) == 0x2F) {
      return true; // ://
    }
  }
  if (end < text.length) {
    final next = text.codeUnitAt(end);
    if (_isAsciiDigit(next) || next == 0x40 || next == 0x5F) return true;
    if (next == 0x3A &&
        end + 2 < text.length &&
        text.codeUnitAt(end + 1) == 0x2F &&
        text.codeUnitAt(end + 2) == 0x2F) {
      return true; // http://
    }
  }
  return false;
}

/// Tokenizes ASCII English word candidates from [text], splitting hyphenated
/// compounds into per-word sub-tokens so each word carries its own centered
/// ruby span and never breaks awkwardly across wrapped lines.
List<EnglishWordToken> tokenizeEnglishWords(String text) {
  if (text.isEmpty) return const [];
  final excludedRanges = _findUrlOrEmailRanges(text);
  final tokens = <EnglishWordToken>[];
  final length = text.length;
  var i = 0;

  while (i < length) {
    final unit = text.codeUnitAt(i);
    final startsLeadingApos = _isApostrophe(unit) &&
        i + 1 < length &&
        _isAsciiLetter(text.codeUnitAt(i + 1));
    if (!_isAsciiLetter(unit) && !startsLeadingApos) {
      i++;
      continue;
    }

    final start = i;
    i++;
    while (i < length) {
      final c = text.codeUnitAt(i);
      if (_isAsciiLetter(c)) {
        i++;
      } else if (_isApostrophe(c)) {
        // Internal apostrophe (`don't`, `o'clock`) or trailing g-drop / possessive.
        i++;
      } else {
        break;
      }
    }
    var tokenStart = start;
    var tokenEnd = i;

    // Strip non-contraction outer quote apostrophes (`'hello'` -> `hello`).
    final hasLeading = _isApostrophe(text.codeUnitAt(tokenStart));
    final hasTrailing =
        tokenEnd > tokenStart && _isApostrophe(text.codeUnitAt(tokenEnd - 1));
    if (hasLeading && hasTrailing) {
      final normalized =
          text.substring(tokenStart, tokenEnd).toLowerCase().replaceAll('\u2019', "'");
      if (normalized != "'n'") {
        tokenStart++;
        tokenEnd--;
      }
    } else if (hasLeading) {
      final normalized =
          text.substring(tokenStart, tokenEnd).toLowerCase().replaceAll('\u2019', "'");
      if (!EnglishPhoneticLexicon._leadingApostropheMap.containsKey(normalized)) {
        tokenStart++;
      }
    } else if (hasTrailing) {
      final normalized =
          text.substring(tokenStart, tokenEnd).toLowerCase().replaceAll('\u2019', "'");
      final keepTrailing =
          (normalized.endsWith("in'") && normalized.length >= 4) ||
              (normalized.endsWith("s'") && normalized.length >= 3);
      if (!keepTrailing) {
        tokenEnd--;
      }
    }

    if (tokenEnd <= tokenStart) continue;
    if (excludedRanges.isNotEmpty &&
        _overlapsRange(excludedRanges, tokenStart, tokenEnd)) {
      continue;
    }
    if (_isUrlOrEmailNeighbor(text, tokenStart, tokenEnd)) continue;

    // Skip tokens adjacent to non-ASCII Latin accented letters (French/German/Spanish).
    if (tokenStart > 0) {
      final prev = text.codeUnitAt(tokenStart - 1);
      if (prev >= 0x00C0 && prev <= 0x024F) continue;
    }
    if (tokenEnd < length) {
      final next = text.codeUnitAt(tokenEnd);
      if (next >= 0x00C0 && next <= 0x024F) continue;
    }

    final word = text.substring(tokenStart, tokenEnd);
    if (word.length == 1) {
      final lower = word.toLowerCase();
      if (lower != 'a' && lower != 'i') continue;
    }
    tokens.add(EnglishWordToken(word, tokenStart, tokenEnd));
  }

  return tokens;
}

/// Fast check for whether a lyric contains any ASCII English word candidates.
bool lyricHasEnglishCandidates(Lyric? lyric) {
  if (lyric == null) return false;
  for (final line in lyric.lines) {
    final text = switch (line) {
      SyncLyricLine() => line.content,
      UnsyncLyricLine() => line.content.split('┃').first,
      _ => '',
    };
    if (tokenizeEnglishWords(text).isNotEmpty) return true;
  }
  return false;
}
