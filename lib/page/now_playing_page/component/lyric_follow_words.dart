import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Presentation timing shared with the existing finite row-follow clock.
/// This never changes a lyric provider's word timestamps or sung colors.
class LyricWordFollow {
  const LyricWordFollow(this.clock, this.curve, this.distance);
  final Animation<double> clock;
  final Curve curve;
  final double distance;

  double offset(double phase, double fontSize) {
    final t = clock.value.clamp(0.0, 1.0);
    if (t <= 0 || t >= 1 || phase >= 1 || fontSize <= 0) return 0;
    // The rightmost word keeps the original trajectory. Lead coefficients
    // are equally spaced toward the left, never delaying the last word. The warp
    // persists through the whole spring return, is monotonic, and preserves
    // both endpoints, so every word finishes on the original baseline.
    final advanced = t + .085 * (1 - phase) * 4 * t * (1 - t);
    final raw = distance * (curve.transform(t) - curve.transform(advanced));
    final maximum = math.min(10.0, fontSize * .22);
    return raw / math.sqrt(1 + raw * raw / (maximum * maximum));
  }
}

class LyricWordFollowScope extends InheritedWidget {
  const LyricWordFollowScope(
      {super.key, required this.follow, required super.child});
  final LyricWordFollow? follow;
  static LyricWordFollow? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LyricWordFollowScope>()
      ?.follow;
  @override
  bool updateShouldNotify(LyricWordFollowScope oldWidget) =>
      follow?.clock != oldWidget.follow?.clock ||
      follow?.curve != oldWidget.follow?.curve ||
      follow?.distance != oldWidget.follow?.distance;
}

/// UTF-16 ranges retain emoji/combining clusters, CJK graphemes, and whole
/// Western words. Spaces are kept outside the moving ink masks.
List<({int start, int end})> lyricFollowWordRanges(String text) {
  final result = <({int start, int end})>[];
  var offset = 0, westernStart = -1;
  void flush() {
    if (westernStart >= 0) {
      result.add((start: westernStart, end: offset));
      westernStart = -1;
    }
  }

  for (final grapheme in text.characters) {
    final rune = grapheme.runes.first;
    final cjk = (rune >= 0x2e80 && rune <= 0x9fff) ||
        (rune >= 0x1100 && rune <= 0x11ff) ||
        (rune >= 0xac00 && rune <= 0xd7af) ||
        (rune >= 0xf900 && rune <= 0xfaff) ||
        (rune >= 0x20000 && rune <= 0x323af);
    final blank = grapheme.trim().isEmpty;
    if (cjk || blank) flush();
    if (cjk) {
      result.add((start: offset, end: offset + grapheme.length));
    } else if (!blank && westernStart < 0) {
      westernStart = offset;
    }
    offset += grapheme.length;
  }
  flush();
  return result;
}

class LyricFollowWordSlot {
  LyricFollowWordSlot(this.start, this.end, this.boxes);
  final int start, end;
  final List<TextBox> boxes;
  final List<Rect> paintBoxes = [];
  late final Path paintPath = () {
    final path = Path();
    for (final box in paintBoxes) {
      path.addRect(box);
    }
    return path;
  }();
  double phase = 0;
}

/// Selection boxes describe advances, not all antialiased ink. Partition at
/// the middle of whitespace so overhanging letter edges are retained without
/// drawing a neighbouring word twice when their baselines differ.
int lyricFollowLineIndex(Rect box, List<ui.LineMetrics> lines) {
  var nearest = 0;
  var distance = double.infinity;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final center = line.baseline + (line.descent - line.ascent) / 2;
    final candidate = (box.center.dy - center).abs();
    if (candidate < distance) {
      nearest = i;
      distance = candidate;
    }
  }
  return nearest;
}

List<Rect> lyricFollowClipPartitions(
    List<Rect> boxes, Size paragraph, List<ui.LineMetrics> lines) {
  final result = boxes.toList();
  final rows = <int, List<int>>{};
  for (var i = 0; i < boxes.length; i++) {
    (rows[lyricFollowLineIndex(boxes[i], lines)] ??= []).add(i);
  }
  final lineIndices = rows.keys.toList()..sort();
  for (var r = 0; r < lineIndices.length; r++) {
    final lineIndex = lineIndices[r];
    final line = lines[lineIndex];
    final row = rows[lineIndex]!
      ..sort((a, b) => boxes[a].left.compareTo(boxes[b].left));
    final top = r == 0
        ? math.min(0.0, line.baseline - line.ascent) - 4
        : (lines[lineIndices[r - 1]].baseline +
                lines[lineIndices[r - 1]].descent +
                line.baseline -
                line.ascent) /
            2;
    final bottom = r == lineIndices.length - 1
        ? math.max(paragraph.height, line.baseline + line.descent) + 4
        : (line.baseline +
                line.descent +
                lines[lineIndices[r + 1]].baseline -
                lines[lineIndices[r + 1]].ascent) /
            2;
    for (var i = 0; i < row.length; i++) {
      final box = boxes[row[i]];
      final left = i == 0
          ? math.min(0.0, box.left) - 4
          : (boxes[row[i - 1]].right + box.left) / 2;
      final right = i == row.length - 1
          ? math.max(paragraph.width, box.right) + 4
          : (box.right + boxes[row[i + 1]].left) / 2;
      result[row[i]] = Rect.fromLTRB(left, top, right, bottom);
    }
  }
  return result;
}

/// Cache shaping/word bounds once. Long imported paragraphs keep ordinary
/// follow rather than allocating unbounded per-word presentation work.
List<LyricFollowWordSlot> lyricFollowWordSlots(
    TextPainter painter, String text) {
  final ranges = lyricFollowWordRanges(text);
  if (ranges.length > 256) return const [];
  final slots = <LyricFollowWordSlot>[];
  for (final range in ranges) {
    final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
        boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle);
    if (boxes.isNotEmpty) {
      slots.add(LyricFollowWordSlot(range.start, range.end, boxes));
    }
  }
  final lines = painter.computeLineMetrics();
  final rows = <int, List<LyricFollowWordSlot>>{};
  for (final slot in slots) {
    (rows[lyricFollowLineIndex(slot.boxes.first.toRect(), lines)] ??= [])
        .add(slot);
  }
  for (final row in rows.values) {
    row.sort((a, b) => a.boxes.first.left.compareTo(b.boxes.first.left));
    for (var i = 0; i < row.length; i++) {
      row[i].phase = row.length == 1 ? 1 : i / (row.length - 1);
    }
  }
  final partitions = lyricFollowClipPartitions([
    for (final slot in slots)
      for (final box in slot.boxes) box.toRect(),
  ], painter.size, lines);
  var index = 0;
  for (final slot in slots) {
    for (var box = 0; box < slot.boxes.length; box++) {
      slot.paintBoxes.add(partitions[index++]);
    }
  }
  return slots;
}
