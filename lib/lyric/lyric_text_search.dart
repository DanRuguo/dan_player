import 'lyric.dart';
import 'plain_lyric.dart';

/// A reading destination in the original document, never a playback time.
class LyricReadingTarget {
  const LyricReadingTarget(this.lyric, this.index, this.line,
      {this.textOffset});
  final Lyric lyric;
  final int index;
  final LyricLine line;
  final int? textOffset;

  bool belongsTo(Lyric document) =>
      identical(lyric, document) &&
      index >= 0 &&
      index < document.lines.length &&
      identical(line, document.lines[index]);
}

class LyricSearchRow {
  LyricSearchRow(this.target, this.text) : searchable = text.toLowerCase();
  final LyricReadingTarget target;
  final String text, searchable;
  int get index => target.index;
  LyricLine get line => target.line;

  /// Keep matching tracks visible in a compact result, including translations
  /// whose original text would otherwise push them past the preview's end.
  String preview(String query) {
    final terms = _searchTerms(query);
    if (terms.isEmpty) return text;
    final matching = text.split('\n').where((part) {
      final folded = part.toLowerCase();
      return terms.any(folded.contains);
    });
    return matching.map((part) {
      RegExpMatch? hit;
      for (final term in terms) {
        hit = RegExp(RegExp.escape(term), caseSensitive: false, unicode: true)
            .firstMatch(part);
        if (hit != null) break;
      }
      if (hit == null || part.length <= 160) return part;
      var from = (hit.start - 40).clamp(0, part.length);
      var to = (from + 160).clamp(hit.end, part.length);
      if (from > 0 &&
          part.codeUnitAt(from) >= 0xdc00 &&
          part.codeUnitAt(from) <= 0xdfff) {
        from--;
      }
      if (to < part.length &&
          part.codeUnitAt(to - 1) >= 0xd800 &&
          part.codeUnitAt(to - 1) <= 0xdbff) {
        to++;
      }
      return '${from > 0 ? '…' : ''}${part.substring(from, to)}${to < part.length ? '…' : ''}';
    }).join('\n');
  }
}

List<String> _searchTerms(String query) => query
    .trim()
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((word) => word.isNotEmpty)
    .toList(growable: false);

/// Built once when a reader opens. Filtering never observes the media clock.
List<LyricSearchRow> lyricSearchRows(Lyric lyric,
    {required String Function(LyricLine) project,
    bool Function(LyricLine)? includeLine}) {
  final rows = <LyricSearchRow>[];
  for (final (index, line) in lyric.lines.indexed) {
    if (includeLine != null && !includeLine(line)) continue;
    if (lyric is PlainLyric && line is UnsyncLyricLine) {
      // PlainLyric is one paragraph. Keep its model and UTF-16 offsets intact,
      // including blank lines, CRLF and surrogate pairs before each hit.
      final text = line.content.split('┃').first;
      var start = 0;
      for (final separator in RegExp(r'\r\n|\r|\n').allMatches(text)) {
        final value = text.substring(start, separator.start);
        if (value.trim().isNotEmpty) {
          rows.add(LyricSearchRow(
              LyricReadingTarget(lyric, index, line, textOffset: start),
              value));
        }
        start = separator.end;
      }
      final value = text.substring(start);
      if (value.trim().isNotEmpty) {
        rows.add(LyricSearchRow(
            LyricReadingTarget(lyric, index, line, textOffset: start), value));
      }
    } else {
      final text = project(line);
      if (text.trim().isNotEmpty) {
        rows.add(LyricSearchRow(LyricReadingTarget(lyric, index, line), text));
      }
    }
  }
  return List.unmodifiable(rows);
}

List<LyricSearchRow> filterLyricSearchRows(
    List<LyricSearchRow> rows, String query) {
  final terms = _searchTerms(query);
  return rows.where((row) => terms.every(row.searchable.contains)).map((row) {
    if (terms.isEmpty || row.target.textOffset == null) return row;
    final match =
        RegExp(RegExp.escape(terms.first), caseSensitive: false, unicode: true)
            .firstMatch(row.text);
    return LyricSearchRow(
        LyricReadingTarget(row.target.lyric, row.index, row.line,
            textOffset: row.target.textOffset! + (match?.start ?? 0)),
        row.text);
  }).toList(growable: false);
}
