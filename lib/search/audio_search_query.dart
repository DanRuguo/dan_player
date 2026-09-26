/// Parsed local-library filters. Plain words retain legacy whole-query scoring.
class AudioSearchQuery {
  AudioSearchQuery._(
      this.text, this.terms, this.hasStructuredSyntax, this.expression)
      : compact = text.replaceAll(RegExp(r'\s+'), '');

  final String text;
  final String compact;
  final List<AudioSearchTerm> terms;
  final bool hasStructuredSyntax;
  final AudioSearchExpression? expression;
  bool get filtersDuration => terms.any((term) => term.field == 'duration');
  bool get usesPersonalData => terms.any((term) =>
      const {'rating', 'tag', 'added'}.contains(term.field) ||
      (term.field == 'has' &&
          const {'rating', 'tag', 'added'}.contains(term.value)));
  bool get usesPlaybackHistory => terms.any((term) =>
      const {'playcount', 'completed', 'skipped', 'listened', 'lastplayed'}
          .contains(term.field) ||
      (term.field == 'has' && term.value == 'history'));
  bool get usesLiveMetadata =>
      filtersDuration ||
      terms.any((term) =>
          const {'bitrate', 'samplerate', 'filesize', 'track'}
              .contains(term.field) ||
          (term.field == 'has' &&
              const {'duration', 'bitrate', 'samplerate', 'filesize', 'track'}
                  .contains(term.value)));

  factory AudioSearchQuery.parse(String query) {
    final source = _searchWidth(query.trim());
    final text = normalizeSearchText(source);
    final tokens = <_QueryToken>[];
    final terms = <AudioSearchTerm>[];
    final token = StringBuffer();
    var quoted = false;
    var hadQuote = false;
    var leadingQuote = false;
    var structured = false;
    void flush() {
      if (token.isEmpty && !hadQuote) return;
      final value = token.toString();
      if (!hadQuote && (value == 'OR' || value == 'AND')) {
        tokens.add(_QueryToken(value));
        structured = true;
      } else {
        final term = _parseSearchTerm(
            normalizeSearchText(value), hadQuote, leadingQuote);
        terms.add(term);
        tokens.add(_QueryToken('term', term));
        structured |= term.field.isNotEmpty || term.negative || term.literal;
      }
      token.clear();
      hadQuote = false;
      leadingQuote = false;
    }

    for (var i = 0; i < source.length; i++) {
      final character = source[i];
      if (character == r'\' &&
          i + 1 < source.length &&
          source[i + 1] == '"' &&
          !RegExp(r'^-?(folder|path):', caseSensitive: false)
              .hasMatch(token.toString())) {
        token.write('"');
        i++;
      } else if (character == '"') {
        if (!quoted && token.isEmpty) leadingQuote = true;
        quoted = !quoted;
        hadQuote = true;
      } else if (!quoted && const {'(', ')', '|'}.contains(character)) {
        if (character == '(' && token.toString() == '-' && !hadQuote) {
          token.clear();
          tokens.add(const _QueryToken('NOT'));
          structured = true;
        }
        flush();
        tokens.add(_QueryToken(character == '|' ? 'OR' : character));
        structured |= character == '|';
      } else if (!quoted && RegExp(r'\s').hasMatch(character)) {
        flush();
      } else {
        token.write(character);
      }
    }
    if (quoted) {
      throw const AudioSearchQueryException('搜索引号未闭合。');
    }
    flush();
    if (terms.length > 64) throw const AudioSearchQueryException('搜索条件过多。');
    final expression = structured ? _ExpressionParser(tokens).parse() : null;
    return AudioSearchQuery._(
        text, List.unmodifiable(terms), structured, expression);
  }

  static const fields = {
    'title',
    'artist',
    'album',
    'folder',
    'path',
    'format',
    'duration',
    'filename',
    'composer',
    'albumartist',
    'language',
    'track',
    'bitrate',
    'samplerate',
    'filesize',
    'rating',
    'tag',
    'added',
    'playcount',
    'completed',
    'skipped',
    'listened',
    'lastplayed',
    'has',
  };
}

AudioSearchTerm _parseSearchTerm(
    String input, bool literal, bool leadingQuote) {
  var value = input;
  final negative = !leadingQuote && value.startsWith('-') && value.length > 1;
  if (negative) value = value.substring(1);
  var field = '';
  final colon = value.indexOf(':');
  if (!leadingQuote &&
      colon > 0 &&
      AudioSearchQuery.fields.contains(value.substring(0, colon))) {
    field = value.substring(0, colon);
    value = value.substring(colon + 1);
  }
  if (value.isEmpty) throw const AudioSearchQueryException('搜索条件缺少内容。');
  AudioSearchDuration? duration;
  AudioSearchNumber? number;
  AudioSearchDate? date;
  Set<String>? formats;
  if (field == 'duration' || field == 'listened') {
    duration = AudioSearchDuration.parse(value);
  } else if (field == 'format') {
    formats =
        value.split(',').map((s) => s.replaceFirst(RegExp(r'^\.'), '')).toSet();
    if (formats.any((s) => !RegExp(r'^[a-z0-9]+$').hasMatch(s))) {
      throw const AudioSearchQueryException('格式条件无效。');
    }
  } else if (const {
    'track',
    'bitrate',
    'samplerate',
    'filesize',
    'rating',
    'playcount',
    'completed',
    'skipped'
  }.contains(field)) {
    if (!(field == 'rating' && value == 'unrated')) {
      number = AudioSearchNumber.parse(value, field);
    }
  } else if (field == 'added' || field == 'lastplayed') {
    if (!(field == 'lastplayed' && value == 'never')) {
      date = AudioSearchDate.parse(value);
    }
  } else if (field == 'has' &&
      !const {
        'title',
        'artist',
        'album',
        'composer',
        'albumartist',
        'language',
        'track',
        'duration',
        'bitrate',
        'samplerate',
        'filesize',
        'rating',
        'tag',
        'added',
        'history'
      }.contains(value)) {
    throw const AudioSearchQueryException('存在条件无效。');
  }
  return AudioSearchTerm(field, value, negative, literal,
      duration: duration, formats: formats, number: number, date: date);
}

class AudioSearchTerm {
  AudioSearchTerm(this.field, this.value, this.negative, this.literal,
      {this.duration, this.formats, this.number, this.date})
      : compact = value.replaceAll(RegExp(r'\s+'), '');
  final String field;
  final String value;
  final bool negative;
  final bool literal;
  final AudioSearchDuration? duration;
  final Set<String>? formats;
  final AudioSearchNumber? number;
  final AudioSearchDate? date;
  final String compact;
}

sealed class AudioSearchExpression {
  const AudioSearchExpression();
  int? evaluate(int? Function(AudioSearchTerm) score);
}

class _SearchClause extends AudioSearchExpression {
  const _SearchClause(this.term);
  final AudioSearchTerm term;
  @override
  int? evaluate(int? Function(AudioSearchTerm) score) {
    final result = score(term);
    if (result == null) return null;
    return term.negative ? (result > 0 ? 0 : 1) : result;
  }
}

class _SearchGroup extends AudioSearchExpression {
  const _SearchGroup(this.children, {this.any = false});
  final List<AudioSearchExpression> children;
  final bool any;
  @override
  int? evaluate(int? Function(AudioSearchTerm) score) {
    var unknown = false;
    var total = 1;
    var best = 0;
    for (final child in children) {
      final result = child.evaluate(score);
      if (result == null) {
        unknown = true;
        continue;
      }
      if (!any && result == 0) return 0;
      if (any) {
        if (result > best) best = result;
      } else {
        total += result;
      }
    }
    if (any && best > 0) return best;
    return unknown
        ? null
        : any
            ? 0
            : total;
  }
}

class _SearchNot extends AudioSearchExpression {
  const _SearchNot(this.child);
  final AudioSearchExpression child;
  @override
  int? evaluate(int? Function(AudioSearchTerm) score) {
    final result = child.evaluate(score);
    return result == null
        ? null
        : result > 0
            ? 0
            : 1;
  }
}

class _QueryToken {
  const _QueryToken(this.kind, [this.term]);
  final String kind;
  final AudioSearchTerm? term;
}

class _ExpressionParser {
  _ExpressionParser(this.tokens);
  final List<_QueryToken> tokens;
  var position = 0;
  String? get current =>
      position < tokens.length ? tokens[position].kind : null;
  Never invalid() => throw const AudioSearchQueryException('搜索分组无效。');
  AudioSearchExpression parse() {
    final expression = _or(0);
    if (position != tokens.length) invalid();
    return expression;
  }

  AudioSearchExpression _or(int depth) {
    final children = [_and(depth)];
    while (current == 'OR') {
      position++;
      children.add(_and(depth));
    }
    return children.length == 1
        ? children.single
        : _SearchGroup(children, any: true);
  }

  AudioSearchExpression _and(int depth) {
    final children = [_primary(depth)];
    while (current != null && current != ')' && current != 'OR') {
      if (current == 'AND') position++;
      children.add(_primary(depth));
    }
    return children.length == 1 ? children.single : _SearchGroup(children);
  }

  AudioSearchExpression _primary(int depth) {
    if (depth > 8) throw const AudioSearchQueryException('搜索分组过深。');
    if (current == 'NOT') {
      position++;
      return _SearchNot(_primary(depth + 1));
    }
    if (current == '(') {
      position++;
      final child = _or(depth + 1);
      if (current != ')') invalid();
      position++;
      return child;
    }
    if (current != 'term') invalid();
    return _SearchClause(tokens[position++].term!);
  }
}

class AudioSearchNumber {
  const AudioSearchNumber._(
      this.minimum, this.maximum, this.includeMinimum, this.includeMaximum);
  final num? minimum, maximum;
  final bool includeMinimum, includeMaximum;
  factory AudioSearchNumber.parse(String value, String field) {
    Never invalid() => throw const AudioSearchQueryException('数值条件无效。');
    num number(String input) {
      final match = RegExp(r'^(\d+(?:\.\d+)?)([a-z]*)$').firstMatch(input);
      if (match == null) invalid();
      final scalar = num.tryParse(match.group(1)!);
      final unit = match.group(2)!;
      final multiplier = switch (field) {
        'filesize' => switch (unit) {
            '' || 'b' => 1,
            'kb' => 1000,
            'mb' => 1000000,
            'gb' => 1000000000,
            'kib' => 1024,
            'mib' => 1048576,
            'gib' => 1073741824,
            _ => null
          },
        'samplerate' => switch (unit) {
            '' || 'hz' => 1,
            'k' || 'khz' => 1000,
            _ => null
          },
        'bitrate' => switch (unit) { '' || 'kbps' => 1, _ => null },
        _ => unit.isEmpty ? 1 : null,
      };
      if (scalar == null || !scalar.isFinite || multiplier == null) invalid();
      final result = scalar * multiplier;
      final maximum = switch (field) {
        'rating' => 5,
        'bitrate' => 100000,
        'samplerate' => 10000000,
        'track' => 1000000,
        'filesize' => 9000000000000000,
        _ => 1000000000
      };
      if (!result.isFinite || result > maximum || result != result.round()) {
        invalid();
      }
      return result.round();
    }

    final range = value.split('..');
    if (range.length == 2) {
      final minimum = number(range[0]), maximum = number(range[1]);
      if (minimum > maximum) invalid();
      return AudioSearchNumber._(minimum, maximum, true, true);
    }
    if (range.length != 1) invalid();
    final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(value);
    if (match == null) invalid();
    final scalar = number(match.group(2)!);
    return switch (match.group(1) ?? '=') {
      '>' => AudioSearchNumber._(scalar, null, false, true),
      '>=' => AudioSearchNumber._(scalar, null, true, true),
      '<' => AudioSearchNumber._(null, scalar, true, false),
      '<=' => AudioSearchNumber._(null, scalar, true, true),
      _ => AudioSearchNumber._(scalar, scalar, true, true),
    };
  }
  bool matches(num value) =>
      (minimum == null ||
          (includeMinimum ? value >= minimum! : value > minimum!)) &&
      (maximum == null ||
          (includeMaximum ? value <= maximum! : value < maximum!));
}

class AudioSearchDate {
  const AudioSearchDate._(this.start, this.end);
  final int? start, end;
  factory AudioSearchDate.parse(String value) {
    Never invalid() =>
        throw const AudioSearchQueryException('日期条件无效，请使用 YYYY-MM-DD。');
    int day(String input) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) invalid();
      final parsed = DateTime.tryParse(input);
      if (parsed == null ||
          parsed.toIso8601String().substring(0, 10) != input ||
          parsed.year < 1970) {
        invalid();
      }
      return parsed.millisecondsSinceEpoch;
    }

    int nextDay(int milliseconds) {
      final value = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      return DateTime(value.year, value.month, value.day + 1)
          .millisecondsSinceEpoch;
    }

    final range = value.split('..');
    if (range.length == 2) {
      final start = day(range[0]), end = day(range[1]);
      if (start > end) invalid();
      return AudioSearchDate._(start, nextDay(end));
    }
    if (range.length != 1) invalid();
    final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(value);
    if (match == null) invalid();
    final start = day(match.group(2)!);
    return switch (match.group(1) ?? '=') {
      '>' => AudioSearchDate._(nextDay(start), null),
      '>=' => AudioSearchDate._(start, null),
      '<' => AudioSearchDate._(null, start),
      '<=' => AudioSearchDate._(null, nextDay(start)),
      _ => AudioSearchDate._(start, nextDay(start)),
    };
  }
  bool matches(int milliseconds) =>
      (start == null || milliseconds >= start!) &&
      (end == null || milliseconds < end!);
}

String _searchWidth(String text) => String.fromCharCodes(
    text.runes.map((rune) => rune >= 0xff01 && rune <= 0xff5e
        ? rune - 0xfee0
        : rune == 0x3000
            ? 0x20
            : rune));

class AudioSearchDuration {
  const AudioSearchDuration._(
      this.minimum, this.maximum, this.includeMinimum, this.includeMaximum);
  final int? minimum;
  final int? maximum;
  final bool includeMinimum;
  final bool includeMaximum;

  factory AudioSearchDuration.parse(String value) {
    Never invalid() => throw const AudioSearchQueryException('时长条件无效。');
    int seconds(String input) {
      final parts = input.split(':');
      if (parts.length > 3 || parts.any((p) => !RegExp(r'^\d+$').hasMatch(p))) {
        invalid();
      }
      final values = parts.map(int.tryParse).toList();
      if (values.any((v) => v == null)) invalid();
      if (parts.length > 1 && values.skip(1).any((v) => v! >= 60)) invalid();
      return values.fold<int>(0, (total, next) {
        if (total > 0x7fffffff ~/ 60 || next! > 0x7fffffff - total * 60) {
          invalid();
        }
        return total * 60 + next;
      });
    }

    final range = value.split('..');
    if (range.length == 2) {
      final minimum = seconds(range[0]);
      final maximum = seconds(range[1]);
      if (minimum > maximum) invalid();
      return AudioSearchDuration._(minimum, maximum, true, true);
    }
    if (range.length != 1) invalid();
    final match = RegExp(r'^(>=|<=|>|<|=)?(.+)$').firstMatch(value);
    if (match == null) invalid();
    final number = seconds(match.group(2)!);
    return switch (match.group(1) ?? '=') {
      '>' => AudioSearchDuration._(number, null, false, true),
      '>=' => AudioSearchDuration._(number, null, true, true),
      '<' => AudioSearchDuration._(null, number, true, false),
      '<=' => AudioSearchDuration._(null, number, true, true),
      _ => AudioSearchDuration._(number, number, true, true),
    };
  }

  bool matches(num seconds) =>
      (minimum == null ||
          (includeMinimum ? seconds >= minimum! : seconds > minimum!)) &&
      (maximum == null ||
          (includeMaximum ? seconds <= maximum! : seconds < maximum!));
}

class AudioSearchQueryException extends FormatException {
  const AudioSearchQueryException(super.message);
}

/// Fold common Latin diacritics, combining accents and fullwidth ASCII without
/// depending on locale or changing CJK text/pinyin semantics.
final _latinSearchFolds = <String, String>{
  for (final group in const <String, String>{
    'àáâãäåāăą': 'a',
    'çćĉċč': 'c',
    'ďđ': 'd',
    'èéêëēĕėęě': 'e',
    'ĝğġģ': 'g',
    'ĥħ': 'h',
    'ìíîïĩīĭįı': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ĺļľŀł': 'l',
    'ñńņň': 'n',
    'òóôõöøōŏő': 'o',
    'ŕŗř': 'r',
    'śŝşš': 's',
    'ţťŧ': 't',
    'ùúûüũūŭůűų': 'u',
    'ŵ': 'w',
    'ýÿŷ': 'y',
    'źżž': 'z',
    'æ': 'ae',
    'œ': 'oe',
    'ß': 'ss',
  }.entries)
    for (final character in group.key.split('')) character: group.value,
};

String normalizeSearchText(String text) {
  final result = StringBuffer();
  for (var rune in text.runes) {
    if (rune >= 0xff01 && rune <= 0xff5e) rune -= 0xfee0;
    if (rune == 0x3000) rune = 0x20;
    if (rune >= 0x0300 && rune <= 0x036f) continue;
    final character = String.fromCharCode(rune).toLowerCase();
    result.write(_latinSearchFolds[character] ?? character);
  }
  return result.toString();
}
