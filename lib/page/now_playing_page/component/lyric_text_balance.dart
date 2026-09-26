import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'lyric_follow_words.dart';

/// TextPainter's advance width can be smaller than antialiased glyph ink.
/// Keep that ink inside the same paragraph canvas used by the row filter.
const double lyricVerticalInkGuard = 4;

double lyricHorizontalInkGuard(
    TextStyle style, TextScaler scaler, double availableWidth) {
  // Keep the source origin on an integral logical pixel. Fractional inset
  // changes antialias thresholds when a context row deblurs on hover.
  final desired =
      math.max(4.0, scaler.scale(style.fontSize ?? 14) * .2).ceilToDouble();
  return availableWidth.isFinite
      ? math.min(desired, math.max(0.0, (availableWidth - 1) / 2))
      : desired;
}

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
      {super.key,
      required this.style,
      required this.textAlign,
      this.wordFollow = false});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final bool wordFollow;

  @override
  State<BalancedLyricText> createState() => _BalancedLyricTextState();
}

class _BalancedLyricTextState extends State<BalancedLyricText> {
  Object? _identity;
  double? _width;
  TextPainter? _painter;
  List<LyricFollowWordSlot> _slots = const [];
  Color? _color;
  @override
  Widget build(BuildContext context) {
    final follow = widget.wordFollow ? LyricWordFollowScope.of(context) : null;
    return LayoutBuilder(builder: (context, constraints) {
      final direction = Directionality.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final locale = Localizations.maybeLocaleOf(context);
      final style = widget.style.copyWith(color: Colors.white);
      final horizontalGuard =
          lyricHorizontalInkGuard(widget.style, scaler, constraints.maxWidth);
      final textMaxWidth = constraints.maxWidth.isFinite
          ? math.max(1.0, constraints.maxWidth - horizontalGuard * 2)
          : constraints.maxWidth;
      final identity = (
        widget.text,
        style,
        widget.textAlign,
        direction,
        scaler,
        locale,
        textMaxWidth
      );
      if (_identity != identity || (widget.wordFollow && _painter == null)) {
        _painter?.dispose();
        final painter = _painter = TextPainter(
            text: TextSpan(text: widget.text, style: widget.style),
            textAlign: widget.textAlign,
            textDirection: direction,
            textScaler: scaler,
            locale: locale);
        _width = layoutBalancedLyric(painter, textMaxWidth);
        // The retained painter and its transparent Text child must use the
        // same paragraph width, otherwise short centered/right-aligned ink
        // paints at the paragraph's leading edge while the child is aligned.
        if (_width!.isFinite) {
          painter.layout(minWidth: _width!, maxWidth: _width!);
        }
        _slots = widget.wordFollow
            ? lyricFollowWordSlots(painter, widget.text)
            : const [];
        _color = widget.style.color;
        _identity = identity;
      }
      if (_painter != null && _color != widget.style.color) {
        _painter!
          ..text = TextSpan(text: widget.text, style: widget.style)
          ..layout(minWidth: _width!.isFinite ? _width! : 0, maxWidth: _width!);
        _color = widget.style.color;
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
      if (!widget.wordFollow) {
        _painter?.dispose();
        _painter = null;
        _slots = const [];
        return Align(
            alignment: alignment,
            child: SizedBox(
                width: _width!.isFinite ? _width! + horizontalGuard * 2 : null,
                child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontalGuard,
                        vertical: lyricVerticalInkGuard),
                    child: Text(widget.text,
                        textAlign: widget.textAlign, style: widget.style))));
      }
      return Align(
          alignment: alignment,
          child: SizedBox(
              width: _width!.isFinite ? _width! + horizontalGuard * 2 : null,
              child: CustomPaint(
                painter: PlainLyricWordFollowPainter(
                    _painter!, _slots, follow, _color,
                    inkOffset: Offset(horizontalGuard, lyricVerticalInkGuard)),
                isComplex: true,
                // LyricFollowEffects detaches the clock at the end of its
                // finite animation. Only moving words bypass the raster cache;
                // settled phonetics can reuse stable glyph sampling while the
                // timed primary paragraph continues to repaint.
                willChange: follow != null,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalGuard,
                      vertical: lyricVerticalInkGuard),
                  child: Opacity(
                      opacity: 0,
                      alwaysIncludeSemantics: true,
                      child: Text(widget.text,
                          textAlign: widget.textAlign, style: widget.style)),
                ),
              )));
    });
  }

  @override
  void dispose() {
    _painter?.dispose();
    super.dispose();
  }
}

class PlainLyricWordFollowPainter extends CustomPainter {
  PlainLyricWordFollowPainter(this.text, this.slots, this.follow, this.color,
      {this.inkOffset = Offset.zero})
      : super(repaint: follow?.clock);
  final TextPainter text;
  final List<LyricFollowWordSlot> slots;
  final LyricWordFollow? follow;
  final Color? color;
  final Offset inkOffset;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(inkOffset.dx, inkOffset.dy);
    _paintInk(canvas);
    canvas.restore();
  }

  void _paintInk(Canvas canvas) {
    final motion = follow;
    if (motion == null ||
        slots.isEmpty ||
        motion.clock.value <= 0 ||
        motion.clock.value >= 1) {
      text.paint(canvas, Offset.zero);
      return;
    }
    final fontSize = text.textScaler.scale(text.text?.style?.fontSize ?? 14);
    for (final slot in slots) {
      canvas.save();
      canvas.translate(0, motion.offset(slot.phase, fontSize));
      if (slot.paintBoxes.length == 1) {
        canvas.clipRect(slot.paintBoxes.single, doAntiAlias: false);
      } else {
        canvas.clipPath(slot.paintPath, doAntiAlias: false);
      }
      text.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PlainLyricWordFollowPainter oldDelegate) =>
      !identical(text, oldDelegate.text) ||
      !identical(slots, oldDelegate.slots) ||
      follow?.clock != oldDelegate.follow?.clock ||
      follow?.curve != oldDelegate.follow?.curve ||
      follow?.distance != oldDelegate.follow?.distance ||
      inkOffset != oldDelegate.inkOffset ||
      color != oldDelegate.color;
}
