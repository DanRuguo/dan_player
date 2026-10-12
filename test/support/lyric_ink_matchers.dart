import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reading keeps every pixel at the same location. The user permits tiny RGB
/// quantization differences from antialiasing/composition, with exact alpha.
/// Observed two-unit rounding is bounded to 2/255 (under 0.8% of a channel).
Matcher matchesReadingLyricRgba(List<int> reference) =>
    _ReadingLyricRgbaMatcher(reference);

class _ReadingLyricRgbaMatcher extends Matcher {
  _ReadingLyricRgbaMatcher(this.reference);

  final List<int> reference;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! List<int> ||
        item.length != reference.length ||
        item.length % 4 != 0) {
      matchState['difference'] = 'RGBA buffer type or length differs';
      return false;
    }
    for (var index = 0; index < reference.length; index++) {
      final limit = index % 4 == 3 ? 0 : 2;
      if ((item[index] - reference[index]).abs() > limit) {
        matchState['difference'] = 'pixel ${index ~/ 4}, '
            '${['R', 'G', 'B', 'A'][index % 4]} channel: '
            '${item[index]} instead of ${reference[index]} '
            '(allowed difference $limit)';
        return false;
      }
    }
    return true;
  }

  @override
  Description describe(Description description) => description.add(
      'the same RGBA pixels with RGB differences at most 2 and exact alpha');

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
          Map matchState, bool verbose) =>
      mismatchDescription.add(matchState['difference'] as String);
}

void reportReadingLyricRgbaDifference(
    List<int> actual, List<int> reference, String label) {
  expect(actual.length, reference.length, reason: '$label RGBA buffer length');
  expect(actual.length % 4, 0, reason: '$label complete RGBA pixels');
  var changedPixels = 0;
  var maxRgbDifference = 0;
  var maxAlphaDifference = 0;
  for (var pixel = 0; pixel < actual.length; pixel += 4) {
    var changed = false;
    for (var channel = 0; channel < 4; channel++) {
      final difference =
          (actual[pixel + channel] - reference[pixel + channel]).abs();
      if (difference != 0) changed = true;
      if (channel == 3) {
        if (difference > maxAlphaDifference) maxAlphaDifference = difference;
      } else if (difference > maxRgbDifference) {
        maxRgbDifference = difference;
      }
    }
    if (changed) changedPixels++;
  }
  debugPrint('READING_RGBA_DIFF $label pixels=${actual.length ~/ 4} '
      'changed=$changedPixels maxRgb=$maxRgbDifference '
      'maxAlpha=$maxAlphaDifference');
}

typedef ReadingLyricGraphemeBounds = ({String grapheme, List<Rect> boxes});

/// Observe the actual mounted paragraph, independently of its reading anchor.
/// Every grapheme retains all selection boxes, including wrapped/RTL fragments.
List<ReadingLyricGraphemeBounds> readingLyricGraphemeBounds(
  RenderBox paintBox,
  TextPainter paragraph, {
  required Offset inkOffset,
}) {
  final transform = paintBox.getTransformTo(null);
  var offset = 0;
  return [
    for (final grapheme in paragraph.text!.toPlainText().characters)
      (
        grapheme: grapheme,
        boxes: [
          for (final box in paragraph.getBoxesForSelection(TextSelection(
              baseOffset: offset, extentOffset: offset += grapheme.length)))
            MatrixUtils.transformRect(transform, box.toRect().shift(inkOffset)),
        ],
      ),
  ];
}

void expectReadingLyricGraphemeBounds(
  List<ReadingLyricGraphemeBounds> actual,
  List<ReadingLyricGraphemeBounds> reference, {
  required String reason,
}) {
  expect(reference, isNotEmpty,
      reason: 'Observe the complete primary paragraph');
  expect(
      reference
          .where((glyph) => glyph.grapheme.trim().isNotEmpty)
          .every((glyph) => glyph.boxes.isNotEmpty),
      isTrue,
      reason: 'Every visible primary grapheme has actual selection geometry');
  expect(actual.length, reference.length, reason: reason);
  for (var index = 0; index < reference.length; index++) {
    final before = reference[index];
    final after = actual[index];
    final glyphReason = '$reason, grapheme $index (${before.grapheme})';
    expect(after.grapheme, before.grapheme, reason: glyphReason);
    expect(after.boxes.length, before.boxes.length, reason: glyphReason);
    for (var fragment = 0; fragment < before.boxes.length; fragment++) {
      final expected = before.boxes[fragment];
      final observed = after.boxes[fragment];
      expect(observed.left, closeTo(expected.left, .05), reason: glyphReason);
      expect(observed.top, closeTo(expected.top, .05), reason: glyphReason);
      expect(observed.right, closeTo(expected.right, .05), reason: glyphReason);
      expect(observed.bottom, closeTo(expected.bottom, .05),
          reason: glyphReason);
    }
  }
}
