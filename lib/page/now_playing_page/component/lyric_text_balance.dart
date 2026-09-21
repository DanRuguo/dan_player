import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Balance short lyric paragraphs without changing their text or timing offsets.
/// Use Flutter's own shaping/break rules; at most seven additional layouts, only
/// when the final row is short. Call when paragraph inputs change, never on ticks.
double layoutBalancedLyric(TextPainter painter, double maxWidth) {
  painter.layout(maxWidth: maxWidth);
  final text = painter.text?.toPlainText() ?? '';
  if (!maxWidth.isFinite ||
      maxWidth <= 0 ||
      text.length > 512 ||
      text.contains('\n') ||
      painter.textDirection == TextDirection.rtl) {
    return maxWidth;
  }
  final original = painter.computeLineMetrics();
  if (original.length < 2 || original.length > 6) return maxWidth;
  final widest = original.fold<double>(0, (v, row) => math.max(v, row.width));
  if (original.last.width >= widest * .65) return maxWidth;
  var lower =
      original.fold<double>(0, (v, row) => v + row.width) / original.length;
  final intactPhrases = <TextSelection>[];
  for (final phrase in _phrases.allMatches(text)) {
    final selection =
        TextSelection(baseOffset: phrase.start, extentOffset: phrase.end);
    if (painter.getBoxesForSelection(selection).length == 1) {
      intactPhrases.add(selection);
    }
  }
  // Never create a new split inside a Latin word that currently fits intact.
  for (final word in _latinWords.allMatches(text)) {
    final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: word.start, extentOffset: word.end));
    if (boxes.length > 1) return maxWidth;
    if (boxes.isNotEmpty) {
      lower = math.max(lower, boxes.single.right - boxes.single.left);
    }
  }
  var upper = maxWidth;
  for (var step = 0; step < 7 && upper - lower > .5; step++) {
    final width = (lower + upper) / 2;
    painter.layout(maxWidth: width);
    if (painter.computeLineMetrics().length <= original.length) {
      upper = width;
    } else {
      lower = width;
    }
  }
  painter.layout(maxWidth: upper);
  final balanced = painter.computeLineMetrics();
  double spread(List<LineMetrics> rows) {
    final widths = rows.map((row) => row.width);
    return widths.reduce(math.max) - widths.reduce(math.min);
  }

  if (balanced.length != original.length ||
      spread(balanced) >= spread(original) ||
      intactPhrases
          .any((phrase) => painter.getBoxesForSelection(phrase).length > 1)) {
    painter.layout(maxWidth: maxWidth);
    return maxWidth;
  }
  return upper;
}

final _latinWords =
    RegExp(r"[A-Za-z\u00c0-\u024f0-9][A-Za-z\u00c0-\u024f0-9’'-]*");
final _phrases = RegExp(r'\S+');

/// The measurement key omits paint colour so focus/hover never rewrap a line.
class BalancedLyricText extends StatefulWidget {
  const BalancedLyricText(this.text,
      {super.key, required this.style, required this.textAlign});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  State<BalancedLyricText> createState() => _BalancedLyricTextState();
}

class _BalancedLyricTextState extends State<BalancedLyricText> {
  Object? _identity;
  double? _width;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        final locale = Localizations.maybeLocaleOf(context);
        final style = widget.style.copyWith(color: Colors.white);
        final identity = (
          widget.text,
          style,
          widget.textAlign,
          direction,
          scaler,
          locale,
          constraints.maxWidth
        );
        if (_identity != identity) {
          final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              textAlign: widget.textAlign,
              textDirection: direction,
              textScaler: scaler,
              locale: locale);
          try {
            _width = layoutBalancedLyric(painter, constraints.maxWidth);
          } finally {
            painter.dispose();
          }
          _identity = identity;
        }
        final alignment = switch (widget.textAlign) {
          TextAlign.center => Alignment.center,
          TextAlign.right => Alignment.centerRight,
          TextAlign.end when direction == TextDirection.ltr =>
            Alignment.centerRight,
          TextAlign.start when direction == TextDirection.rtl =>
            Alignment.centerRight,
          _ => Alignment.centerLeft,
        };
        return Align(
            alignment: alignment,
            child: SizedBox(
                width: _width!.isFinite ? _width : null,
                child: Text(widget.text,
                    textAlign: widget.textAlign, style: widget.style)));
      });
}
