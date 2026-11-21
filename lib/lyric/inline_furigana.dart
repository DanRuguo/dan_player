import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_primary_text.dart';
import 'package:flutter/foundation.dart';

final RegExp _inlineFuriganaPattern = RegExp(
  r'([\p{Script=Han}々〆〻]+)(?:'
  r'\(([\u3041-\u3096\u3099-\u309E\u30A1-\u30FA\u30FC-\u30FE\uFF66-\uFF9F\s]+)\)|'
  r'（([\u3041-\u3096\u3099-\u309E\u30A1-\u30FA\u30FC-\u30FE\uFF66-\uFF9F\s]+)）|'
  r'《([\u3041-\u3096\u3099-\u309E\u30A1-\u30FA\u30FC-\u30FE\uFF66-\uFF9F\s]+)》)',
  unicode: true,
);
final RegExp _inlineWhitespace = RegExp(r'\s+');

/// Author-provided inline furigana extracted from a single lyric line's primary
/// text (for example `夜空(よぞら)`, `音（おと）`, or `宇宙《そら》`).
///
/// Ordinary parenthetical text such as `声(live)` or `歌(2)` is left untouched.
@immutable
class InlineFuriganaLine {
  const InlineFuriganaLine({
    required this.cleanedPrimary,
    required this.fullReading,
    required this.spans,
    required this.removals,
  });

  final String cleanedPrimary;
  final String fullReading;
  final List<JapaneseLyricReadingSpan> spans;

  /// Half-open UTF-16 ranges in the original primary text corresponding to the
  /// stripped parenthetical reading tokens.
  final List<(int start, int end)> removals;
}

/// Extracts validated author-provided inline furigana from [primaryText].
/// Returns null when the line contains no valid Han+(kana) annotations.
InlineFuriganaLine? extractInlineFurigana(String primaryText) {
  if (primaryText.isEmpty || primaryText.length > 4096) return null;
  final matches = _inlineFuriganaPattern.allMatches(primaryText).toList();
  if (matches.isEmpty) return null;

  final cleaned = StringBuffer();
  final reading = StringBuffer();
  final spans = <JapaneseLyricReadingSpan>[];
  final removals = <(int, int)>[];
  var sourceCursor = 0;
  var cleanedCursor = 0;

  for (final match in matches) {
    final base = match[1]!;
    final rawReading = (match[2] ?? match[3] ?? match[4] ?? '')
        .replaceAll(_inlineWhitespace, '');
    if (rawReading.isEmpty) continue;

    if (match.start > sourceCursor) {
      final prefix = primaryText.substring(sourceCursor, match.start);
      cleaned.write(prefix);
      reading.write(prefix);
      cleanedCursor += prefix.length;
    }

    final spanStart = cleanedCursor;
    cleaned.write(base);
    cleanedCursor += base.length;
    reading.write(rawReading);
    spans.add(JapaneseLyricReadingSpan(
      start: spanStart,
      end: cleanedCursor,
      text: rawReading,
    ));

    final removalStart = match.start + base.length;
    removals.add((removalStart, match.end));
    sourceCursor = match.end;
  }

  if (spans.isEmpty) return null;

  if (sourceCursor < primaryText.length) {
    final suffix = primaryText.substring(sourceCursor);
    cleaned.write(suffix);
    reading.write(suffix);
  }

  return InlineFuriganaLine(
    cleanedPrimary: cleaned.toString(),
    fullReading: reading.toString(),
    spans: List.unmodifiable(spans),
    removals: List.unmodifiable(removals),
  );
}

/// Applies [inline] to a display-copy [line], stripping only the validated
/// inline annotation brackets/kana while preserving timing and auxiliary text.
void applyInlineFuriganaToLine(LyricLine line, InlineFuriganaLine inline) {
  if (line is SyncLyricLine) {
    final retained = <SyncLyricWord>[];
    var offset = 0;
    var removalIndex = 0;
    final removals = inline.removals;

    for (final word in line.words) {
      final text = word.content;
      final end = offset + text.length;
      final buffer = StringBuffer();
      var cursor = offset;

      while (removalIndex < removals.length &&
          removals[removalIndex].$2 <= offset) {
        removalIndex++;
      }
      var index = removalIndex;
      while (index < removals.length && removals[index].$1 < end) {
        final (left, right) = removals[index];
        if (left > cursor) {
          buffer.write(text.substring(cursor - offset, left - offset));
        }
        cursor = right.clamp(cursor, end);
        if (right > end) break;
        index++;
      }
      if (cursor < end) {
        buffer.write(text.substring(cursor - offset));
      }

      final nextText = buffer.toString();
      word.content = nextText;
      if (text.isNotEmpty && nextText.isEmpty) {
        // Fold stripped annotation duration into the preceding base word so
        // karaoke highlight timing stays continuous across hidden parens.
        if (retained.isNotEmpty) {
          final previous = retained.last;
          final extended = (word.start + word.length) - previous.start;
          if (extended > previous.length) {
            previous.length = extended;
          }
        }
      } else {
        retained.add(word);
      }
      offset = end;
    }

    line.words
      ..clear()
      ..addAll(retained);
    final rebuilt = StringBuffer();
    for (final word in retained) {
      rebuilt.write(word.content);
    }
    line.content = rebuilt.toString();
  } else if (line is UnsyncLyricLine) {
    final primaryLength = lyricPrimaryText(line).length;
    final suffix = line.content.substring(primaryLength);
    line.content = '${inline.cleanedPrimary}$suffix';
  }

  line.japaneseReading = inline.fullReading;
  line.japaneseReadingSpans = inline.spans;
}
