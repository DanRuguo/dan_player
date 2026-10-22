import 'dart:ui' as ui;

import 'package:dan_player/page/now_playing_page/component/lyric_follow_words.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

typedef LyricFollowPiece = ({int word, int wordBox, int slot, Rect bounds});

/// A layout-local UTF-16 index. Author timing and visual order do not determine
/// source order; return matches in their original order, including overlaps.
class LyricSourceRangeIndex {
  LyricSourceRangeIndex(List<({int start, int end})> ranges)
      : _ranges = [
          for (final (index, range) in ranges.indexed)
            (index: index, start: range.start, end: range.end),
        ] {
    _ranges.sort((a, b) => a.start.compareTo(b.start));
    var maximum = _ranges.isEmpty ? 0 : _ranges.first.end;
    for (final range in _ranges) {
      if (range.end > maximum) maximum = range.end;
      _maximumEnds.add(maximum);
    }
  }

  final List<({int index, int start, int end})> _ranges;
  final _maximumEnds = <int>[];

  List<int> overlapping(
    int start,
    int end, {
    @visibleForTesting void Function()? onCandidate,
  }) {
    var low = 0, high = _maximumEnds.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_maximumEnds[middle] <= start) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final result = <int>[];
    for (var i = low; i < _ranges.length; i++) {
      final range = _ranges[i];
      if (range.start >= end) break;
      onCandidate?.call();
      if (range.end > start) result.add(range.index);
    }
    return result..sort();
  }
}

/// Tight glyph boxes can cross native line boundaries or overhang neighbouring
/// source ranges. Query their actual rectangles, rather than assuming one row
/// or a matching UTF-16 range. Deduplication preserves one phase per follow slot.
class LyricFollowBoxIndex {
  LyricFollowBoxIndex(List<LyricFollowWordSlot> slots)
      : _boxes = [
          for (final (index, slot) in slots.indexed)
            for (final box in slot.boxes) (slot: index, bounds: box.toRect()),
        ] {
    _finite = _boxes.every((box) => box.bounds.isFinite);
    if (!_finite) return;
    _boxes.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
    var maximum = double.negativeInfinity;
    for (final box in _boxes) {
      if (box.bounds.bottom > maximum) maximum = box.bounds.bottom;
      _maximumBottoms.add(maximum);
    }
  }

  final List<({int slot, Rect bounds})> _boxes;
  final _maximumBottoms = <double>[];
  late final bool _finite;

  List<int> overlapping(
    Rect bounds, {
    @visibleForTesting void Function()? onCandidate,
  }) {
    final indexed = _finite && bounds.isFinite;
    var low = 0, high = indexed ? _maximumBottoms.length : 0;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_maximumBottoms[middle] <= bounds.top) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final matches = <int>{};
    for (var i = low; i < _boxes.length; i++) {
      final box = _boxes[i];
      if (indexed && box.bounds.top >= bounds.bottom) break;
      if (matches.contains(box.slot)) continue;
      onCandidate?.call();
      if (box.bounds.overlaps(bounds)) matches.add(box.slot);
    }
    // This also keeps floating-point phase accumulation byte-for-byte stable.
    return matches.toList()..sort();
  }
}

/// Intersect the existing native selections without testing every word against
/// every follow slot. Row ownership uses the original nearest-baseline rule;
/// real horizontal bounds, not character positions or direction, prune pairs.
/// The original word/slot/box order and exact intersections are retained.
List<LyricFollowPiece> lyricFollowPieces(
  List<List<TextBox>> words,
  List<LyricFollowWordSlot> slots,
  List<ui.LineMetrics> lines, {
  @visibleForTesting void Function()? onCandidate,
}) {
  if (words.isEmpty || slots.isEmpty) return const [];
  final rows = <int, _SlotRow>{};
  for (var slot = 0; slot < slots.length; slot++) {
    final boxes = slots[slot].boxes;
    for (var box = 0; box < boxes.length; box++) {
      final bounds = boxes[box].toRect();
      (rows[lyricFollowLineIndex(bounds, lines)] ??= _SlotRow()).boxes.add(
        (slot: slot, box: box, bounds: bounds),
      );
    }
  }
  for (final row in rows.values) {
    row.prepare();
  }
  final result = <LyricFollowPiece>[];
  for (var word = 0; word < words.length; word++) {
    final matches = <({int wordBox, int slot, int slotBox, Rect bounds})>[];
    for (var wordBox = 0; wordBox < words[word].length; wordBox++) {
      final bounds = words[word][wordBox].toRect();
      final row = rows[lyricFollowLineIndex(bounds, lines)];
      if (row == null) continue;
      for (var i = row.firstPossible(bounds.left); i < row.boxes.length; i++) {
        final candidate = row.boxes[i];
        if (candidate.bounds.left >= bounds.right) break;
        onCandidate?.call();
        if (!bounds.overlaps(candidate.bounds)) continue;
        matches.add((
          wordBox: wordBox,
          slot: candidate.slot,
          slotBox: candidate.box,
          bounds: bounds.intersect(candidate.bounds),
        ));
      }
    }
    matches.sort((a, b) {
      final slotOrder = a.slot.compareTo(b.slot);
      if (slotOrder != 0) return slotOrder;
      final wordBoxOrder = a.wordBox.compareTo(b.wordBox);
      return wordBoxOrder != 0 ? wordBoxOrder : a.slotBox.compareTo(b.slotBox);
    });
    for (final match in matches) {
      result.add((
        word: word,
        wordBox: match.wordBox,
        slot: match.slot,
        bounds: match.bounds,
      ));
    }
  }
  return result;
}

class _SlotRow {
  final boxes = <({int slot, int box, Rect bounds})>[];
  final maximumRights = <double>[];

  void prepare() {
    boxes.sort((a, b) {
      final leftOrder = a.bounds.left.compareTo(b.bounds.left);
      if (leftOrder != 0) return leftOrder;
      final slotOrder = a.slot.compareTo(b.slot);
      return slotOrder != 0 ? slotOrder : a.box.compareTo(b.box);
    });
    var maximum = double.negativeInfinity;
    for (final box in boxes) {
      if (box.bounds.right > maximum) maximum = box.bounds.right;
      maximumRights.add(maximum);
    }
  }

  int firstPossible(double left) {
    var low = 0, high = maximumRights.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (maximumRights[middle] <= left) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}
