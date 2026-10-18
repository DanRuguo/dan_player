import 'dart:collection';

import 'package:dan_player/search/audio_search_query.dart';
import 'package:pinyin/pinyin.dart';

/// A prepared ordinary-text query. Syntax filters are deliberately evaluated by
/// AudioSearchQuery instead; this matcher never loosens a structured condition.
class PlainSearchQuery {
  factory PlainSearchQuery(String text) =>
      PlainSearchQuery.normalized(normalizeSearchText(text.trim()));

  PlainSearchQuery.normalized(this.text)
      : compact = text.replaceAll(_spaces, ''),
        _words = text.length <= 4096
            ? text
                .split(_spaces)
                .where((word) => word.isNotEmpty)
                .take(65)
                .toList()
            : const [];

  final String text;
  final String compact;
  final List<String> _words;
  static final _spaces = RegExp(r'\s+');
  static final _fuzzyWord = RegExp(r'^[a-z0-9]{4,64}$');

  /// Exact words can occur in different fields. Typo matches always rank below
  /// even the weakest existing exact/pinyin match (18). Long input remains
  /// eligible for whole-text exact matching, but never multiplies fuzzy work.
  int scoreWords(Iterable<SearchTextKeys> fields) {
    if (_words.isEmpty || _words.length > 64) return 0;
    final allowFuzzy = _words.length <= 8 && text.length <= 256;
    var fuzzyCount = 0;
    for (final word in _words) {
      if (fields.any((keys) => keys.score(word, word) > 0)) continue;
      if (!allowFuzzy ||
          !_fuzzyWord.hasMatch(word) ||
          !fields.any((keys) => keys.matchesTypo(word))) {
        return 0;
      }
      fuzzyCount++;
    }
    return fuzzyCount == 0 ? 18 : 9 - fuzzyCount;
  }
}

/// Shared immutable projections, interned only while indexes are assembled.
class SearchTextKeys {
  const SearchTextKeys._(
    this.raw,
    this.rawCompact,
    this.fullPinyin,
    this.initials,
    this._typoWords,
  );

  final String raw;
  final String rawCompact;
  final String fullPinyin;
  final String initials;
  final List<String> _typoWords;

  static const int cacheLimit = 8192;
  static final HashMap<String, _SearchKeyCacheEntry> _cache = HashMap();
  static final LinkedList<_SearchKeyCacheEntry> _recency = LinkedList();
  static final RegExp _nonAlphanumeric = RegExp(r"[^a-z0-9]");
  static final RegExp _word = RegExp(r'[a-z0-9]+');

  factory SearchTextKeys.of(String text) {
    final cached = _cache[text];
    if (cached != null) {
      cached.unlink();
      _recency.add(cached);
      return cached.value;
    }

    final created = SearchTextKeys._fromText(text);
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

  factory SearchTextKeys._fromText(String text) {
    final raw = normalizeSearchText(text);
    final compact = raw.replaceAll(RegExp(r"\s+"), "");
    final pinyin = _toFullPinyin(raw, compact);
    // Only word-sized candidates are compared. Never allocate a distance matrix
    // or scan an unbounded metadata field for each keystroke.
    final prefix = raw.length > 512 ? raw.substring(0, 512) : raw;
    final words = <String>{};
    for (final match in _word.allMatches(prefix).take(32)) {
      final length = match.end - match.start;
      if (length < 3 || length > 65) continue;
      // A truncated long token must not masquerade as a complete shorter word.
      if (match.end == 512 && raw.length > 512 && _word.hasMatch(raw[512])) {
        continue;
      }
      words.add(match.group(0)!);
    }
    if (pinyin.length >= 3 && pinyin.length <= 65) words.add(pinyin);
    return SearchTextKeys._(
      raw,
      compact,
      pinyin,
      _toInitials(raw),
      List.unmodifiable(words),
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
    if (rawQuery.isEmpty || compactQuery.isEmpty) return 0;
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

  bool matchesTypo(String word) =>
      _typoWords.any((candidate) => _oneEditApart(word, candidate));

  int scoreTerm(AudioSearchTerm term) => term.literal
      ? (raw == term.value
          ? 100
          : raw.contains(term.value)
              ? 30
              : 0)
      : score(term.value, term.compact);
}

/// At most one insertion, deletion, substitution or adjacent transposition.
/// ASCII candidates are bounded to 65 code units, so this is O(length) time and
/// O(1) auxiliary space, including rejection at the second differing position.
bool _oneEditApart(String query, String candidate) {
  if ((query.length - candidate.length).abs() > 1) return false;
  var position = 0;
  final shorterLength =
      query.length < candidate.length ? query.length : candidate.length;
  while (position < shorterLength && query[position] == candidate[position]) {
    position++;
  }
  if (position == shorterLength) return true;
  var left = position, right = position;
  if (query.length == candidate.length) {
    if (position + 1 < query.length &&
        query[position] == candidate[position + 1] &&
        query[position + 1] == candidate[position]) {
      left += 2;
      right += 2;
    } else {
      left++;
      right++;
    }
  } else if (query.length > candidate.length) {
    left++;
  } else {
    right++;
  }
  while (left < query.length && right < candidate.length) {
    if (query[left++] != candidate[right++]) return false;
  }
  return left == query.length && right == candidate.length;
}

final class _SearchKeyCacheEntry extends LinkedListEntry<_SearchKeyCacheEntry> {
  _SearchKeyCacheEntry(this.key, this.value);
  final String key;
  final SearchTextKeys value;
}
