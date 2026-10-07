import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'lyric_follow_words.dart';

/// TextPainter's advance width can be smaller than antialiased glyph ink.
/// Keep that ink inside the same paragraph canvas used by the row filter.
const double lyricVerticalInkGuard = 4;

/// The same horizontal anchor is used by the widget alignment, line painter,
/// font handoff, and geometry probes. Keep intermediate alignments continuous.
double lyricAlignmentFraction(double alignmentX) =>
    ((alignmentX + 1) / 2).clamp(0.0, 1.0);

double lyricAlignedOffset(
        double availableWidth, double contentWidth, double alignmentX) =>
    (availableWidth - contentWidth) * lyricAlignmentFraction(alignmentX);

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
  // A spread-based accept/reject threshold can turn on at a *wider* window
  // and move a word back to the following line. That produces a visible
  // rewrap even while the window is dragged steadily in one direction.
  // Instead, both the preferred width and the minimum feasible width must
  // move monotonically with the available width.
  var lower = 0.0;
  final intactPhrases = <TextSelection>[];
  for (final phrase in _phrases.allMatches(text)) {
    final selection =
        TextSelection(baseOffset: phrase.start, extentOffset: phrase.end);
    final boxes = painter.getBoxesForSelection(selection);
    if (boxes.length == 1) {
      intactPhrases.add(selection);
      lower = math.max(lower, boxes.single.right - boxes.single.left);
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
    if (painter.computeLineMetrics().length <= original.length &&
        intactPhrases.every(
            (phrase) => painter.getBoxesForSelection(phrase).length == 1)) {
      upper = width;
    } else {
      lower = width;
    }
  }
  final preferred = math.max(upper, maxWidth * .72);
  painter.layout(maxWidth: preferred);
  if (painter.computeLineMetrics().length != original.length ||
      intactPhrases
          .any((phrase) => painter.getBoxesForSelection(phrase).length > 1)) {
    painter.layout(maxWidth: maxWidth);
    return maxWidth;
  }
  return preferred;
}

final _latinWords =
    RegExp(r"[A-Za-z\u00c0-\u024f0-9][A-Za-z\u00c0-\u024f0-9’'-]*");
final _phrases = RegExp(r'\S+');

/// Moves one already-shaped suffix from the old visual line to its position
/// in the new layout. A single block travels; no glyph gets its own clock.
/// The paragraph sets this during layout; its parent reads it during paint.
/// Only a real one-line/two-line transition may delay the endpoint handoff.
class LyricWrapFlightStatus {
  bool active = false;
}

@visibleForTesting
class LyricWrapFlight {
  const LyricWrapFlight({
    required this.suffixStart,
    required this.prefixClip,
    required this.suffixClip,
    required this.travel,
    required this.progress,
  });

  final int suffixStart;
  final Rect prefixClip;
  final Rect suffixClip;
  final Offset travel;
  final double progress;

  Offset get offset {
    final t = progress.clamp(0.0, 1.0);
    // The old suffix must reach the target's horizontal ink position before
    // the endpoint paragraph appears. Mid-flight overlap is preferable to
    // two readable copies at the handoff.
    final horizontal = t * (2 - t);
    return Offset(travel.dx * horizontal, travel.dy * t);
  }
}

({int suffixStart, Rect prefixClip, Rect suffixClip, Offset travel})?
    _wrapFlightGeometry(
        String text,
        TextPainter source,
        TextPainter target,
        double sourceGuard,
        double targetGuard,
        double sourceFontSize,
        double targetFontSize) {
  if (text.length > 256 || text.contains('\n')) return null;
  final sourceLines = source.computeLineMetrics();
  final targetLines = target.computeLineMetrics();
  if (!((sourceLines.length == 1 && targetLines.length == 2) ||
      (sourceLines.length == 2 && targetLines.length == 1))) {
    return null;
  }
  final wrapped = sourceLines.length == 2 ? source : target;
  final rows = wrapped.computeLineMetrics();
  final boundaryY = (rows.first.baseline + rows.last.baseline) / 2;
  var offset = 0;
  int? suffixStart;
  for (final grapheme in text.characters) {
    final end = offset + grapheme.length;
    final boxes = wrapped.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end));
    if (boxes.any((box) => box.toRect().center.dy > boundaryY)) {
      suffixStart = offset;
      break;
    }
    offset = end;
  }
  if (suffixStart == null || suffixStart == 0) return null;
  final selection =
      TextSelection(baseOffset: suffixStart, extentOffset: text.length);
  final sourceBoxes = source.getBoxesForSelection(selection);
  final targetBoxes = target.getBoxesForSelection(selection);
  if (sourceBoxes.length != 1 || targetBoxes.length != 1) return null;
  final oldSuffix = sourceBoxes.single.toRect();
  final newSuffix = targetBoxes.single.toRect();
  final split = sourceLines.length == 1
      ? oldSuffix.left
      : (sourceLines.first.baseline + oldSuffix.top) / 2;
  final prefixClip = sourceLines.length == 1
      ? Rect.fromLTRB(-100, -100, split, source.height + 100)
      : Rect.fromLTRB(-100, -100, source.width + 100, split);
  final suffixClip = sourceLines.length == 1
      ? Rect.fromLTRB(split, -100, source.width + 100, source.height + 100)
      : Rect.fromLTRB(-100, split, source.width + 100, source.height + 100);
  final targetRatio = sourceFontSize / targetFontSize;
  final travel = Offset(
    (newSuffix.left + targetGuard) * targetRatio -
        (oldSuffix.left + sourceGuard),
    (newSuffix.top + lyricVerticalInkGuard) * targetRatio -
        (oldSuffix.top + lyricVerticalInkGuard),
  );
  return (
    suffixStart: suffixStart,
    prefixClip: prefixClip,
    suffixClip: suffixClip,
    travel: travel,
  );
}

/// The measurement key omits paint colour so focus/hover never rewrap a line.
class BalancedLyricText extends StatefulWidget {
  const BalancedLyricText(this.text,
      {super.key,
      required this.style,
      required this.textAlign,
      this.wordFollow = false,
      this.alignmentX,
      this.wrapTargetFontSize,
      this.wrapProgress = 0,
      this.wrapStatus});
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final bool wordFollow;
  final double? alignmentX;
  final double? wrapTargetFontSize;
  final double wrapProgress;
  final LyricWrapFlightStatus? wrapStatus;

  @override
  State<BalancedLyricText> createState() => _BalancedLyricTextState();
}

/// Read an already-shaped glyph location only when revealing a text search.
/// No layout, keys or observers are added to ordinary lyric rendering.
abstract interface class LyricTextReadingGeometry {
  String get readingText;
  double? readingGlobalY(int offset);
  double? readingLayoutY(int offset, RenderBox ancestor);
}

/// Map cached glyph geometry before paint without reading Transform sizes.
double? lyricReadingLayoutY(RenderBox box, Offset point, RenderBox ancestor) {
  // The viewport needs layout coordinates before paint. Walking layout
  // offsets avoids reading an ancestor Transform's size while a more
  // distant parent is laying out; paint-only emphasis stays separate.
  RenderObject? current = box;
  var local = point;
  while (current != null && !identical(current, ancestor)) {
    final data = current.parentData;
    if (data is BoxParentData) local += data.offset;
    current = current.parent;
  }
  return identical(current, ancestor) ? local.dy : null;
}

class _BalancedLyricTextState extends State<BalancedLyricText>
    implements LyricTextReadingGeometry {
  @override
  String get readingText => widget.text;

  @override
  double? readingGlobalY(int offset) =>
      _readingY(offset, (box, point) => box.localToGlobal(point).dy);

  @override
  double? readingLayoutY(int offset, RenderBox ancestor) => _readingY(
      offset, (box, point) => lyricReadingLayoutY(box, point, ancestor));

  double? _readingY(
      int offset, double? Function(RenderBox box, Offset point) map) {
    if (offset < 0 || offset >= widget.text.length) return null;
    double? result;
    final end = offset +
        (widget.text.codeUnitAt(offset) >= 0xd800 &&
                widget.text.codeUnitAt(offset) <= 0xdbff
            ? 2
            : 1);
    final selection = TextSelection(
        baseOffset: offset, extentOffset: end.clamp(0, widget.text.length));
    void visit(RenderObject object) {
      if (result != null || !object.attached) return;
      if (object is RenderParagraph && object.hasSize) {
        final boxes = object.getBoxesForSelection(selection);
        if (boxes.isNotEmpty) {
          result = map(object, Offset(0, boxes.first.top));
        }
      } else if (object is RenderCustomPaint &&
          object.hasSize &&
          object.painter is PlainLyricWordFollowPainter) {
        final painter = object.painter! as PlainLyricWordFollowPainter;
        if (identical(painter.text, _painter)) {
          final boxes = painter.text.getBoxesForSelection(selection);
          if (boxes.isNotEmpty) {
            result =
                map(object, Offset(0, boxes.first.top + painter.inkOffset.dy));
          }
        }
      }
      if (result == null) object.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);
    return result;
  }

  Object? _identity;
  Object? _shapeIdentity;
  double? _width;
  TextPainter? _painter;
  List<LyricFollowWordSlot> _slots = const [];
  bool? _slotsFollow;
  Color? _color;
  Object? _wrapIdentity;
  ({
    int suffixStart,
    Rect prefixClip,
    Rect suffixClip,
    Offset travel
  })? _wrapGeometry;
  @override
  Widget build(BuildContext context) {
    final follow = widget.wordFollow ? LyricWordFollowScope.of(context) : null;
    return LayoutBuilder(builder: (context, constraints) {
      final direction = Directionality.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final locale = Localizations.maybeLocaleOf(context);
      final textHeightBehavior =
          DefaultTextStyle.of(context).textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context);
      final style = widget.style.copyWith(color: Colors.white);
      final horizontalGuard =
          lyricHorizontalInkGuard(widget.style, scaler, constraints.maxWidth);
      final textMaxWidth = constraints.maxWidth.isFinite
          ? math.max(1.0, constraints.maxWidth - horizontalGuard * 2)
          : constraints.maxWidth;
      final paintAlign =
          widget.alignmentX == null ? widget.textAlign : TextAlign.left;
      final needsPainter = widget.wordFollow || widget.alignmentX != null;
      final shapeIdentity = (
        widget.text,
        style,
        paintAlign,
        direction,
        scaler,
        locale,
        textHeightBehavior
      );
      final identity = (shapeIdentity, textMaxWidth);
      if (_identity != identity || (needsPainter && _painter == null)) {
        // Window resizing changes wrapping, not the glyph run. Keep the
        // native paragraph so its shaping cache survives the width sweep.
        if (_painter == null || _shapeIdentity != shapeIdentity) {
          _painter?.dispose();
          _painter = TextPainter(
              text: TextSpan(text: widget.text, style: widget.style),
              textAlign: paintAlign,
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
              textHeightBehavior: textHeightBehavior);
          _shapeIdentity = shapeIdentity;
        }
        final painter = _painter!;
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
        _slotsFollow = widget.wordFollow;
        _color = widget.style.color;
        _identity = identity;
      } else if (_slotsFollow != widget.wordFollow) {
        // Promoting a context row to the current line changes word-follow
        // metadata, not its glyph layout. Retain the same shaped paragraph.
        _slots = widget.wordFollow
            ? lyricFollowWordSlots(_painter!, widget.text)
            : const [];
        _slotsFollow = widget.wordFollow;
      }
      if (_painter != null && _color != widget.style.color) {
        _painter!
          ..text = TextSpan(text: widget.text, style: widget.style)
          ..layout(minWidth: _width!.isFinite ? _width! : 0, maxWidth: _width!);
        _color = widget.style.color;
      }
      final targetFontSize = widget.wrapTargetFontSize;
      final sourceFontSize = widget.style.fontSize ?? 14;
      final canMoveSuffix = targetFontSize != null &&
          needsPainter &&
          direction == TextDirection.ltr &&
          widget.alignmentX != null &&
          widget.alignmentX! <= -0.999 &&
          // The enclosing Transform uses the raw ratio. A nonlinear scaler
          // needs a separate geometry solution; retain the ordinary morph.
          ((scaler.scale(sourceFontSize) / scaler.scale(targetFontSize)) -
                      sourceFontSize / targetFontSize)
                  .abs() <
              .0001;
      if (canMoveSuffix) {
        final wrapIdentity = (identity, targetFontSize);
        if (_wrapIdentity != wrapIdentity) {
          final targetStyle = widget.style.copyWith(fontSize: targetFontSize);
          final targetGuard = lyricHorizontalInkGuard(
              targetStyle, scaler, constraints.maxWidth);
          final targetMaxWidth = constraints.maxWidth.isFinite
              ? math.max(1.0, constraints.maxWidth - targetGuard * 2)
              : constraints.maxWidth;
          final target = TextPainter(
              text: TextSpan(text: widget.text, style: targetStyle),
              textAlign: paintAlign,
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
              textHeightBehavior: textHeightBehavior);
          try {
            final balancedWidth = layoutBalancedLyric(target, targetMaxWidth);
            if (balancedWidth.isFinite) {
              target.layout(minWidth: balancedWidth, maxWidth: balancedWidth);
            }
            _wrapGeometry = _wrapFlightGeometry(
                widget.text,
                _painter!,
                target,
                horizontalGuard,
                targetGuard,
                scaler.scale(sourceFontSize),
                scaler.scale(targetFontSize));
          } finally {
            target.dispose();
          }
          _wrapIdentity = wrapIdentity;
        }
      } else {
        _wrapGeometry = null;
        _wrapIdentity = null;
      }
      final wrapFlight = _wrapGeometry == null
          ? null
          : LyricWrapFlight(
              suffixStart: _wrapGeometry!.suffixStart,
              prefixClip: _wrapGeometry!.prefixClip,
              suffixClip: _wrapGeometry!.suffixClip,
              travel: _wrapGeometry!.travel,
              progress: widget.wrapProgress.clamp(0.0, 1.0),
            );
      widget.wrapStatus?.active = wrapFlight != null;
      final alignment = widget.alignmentX != null
          ? Alignment(widget.alignmentX!, 0)
          : switch (widget.textAlign) {
              TextAlign.center => Alignment.center,
              TextAlign.right => Alignment.centerRight,
              TextAlign.end when direction == TextDirection.ltr =>
                Alignment.centerRight,
              TextAlign.start when direction == TextDirection.rtl =>
                Alignment.centerRight,
              _ => Alignment.centerLeft,
            };
      if (!needsPainter) {
        _painter?.dispose();
        _painter = null;
        _slots = const [];
        _slotsFollow = null;
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
                    inkOffset: Offset(horizontalGuard, lyricVerticalInkGuard),
                    alignmentX: widget.alignmentX,
                    wrapFlight: wrapFlight,
                    layoutIdentity: identity),
                isComplex: true,
                // LyricFollowEffects detaches the clock at the end of its
                // finite animation. Only moving words bypass the raster cache;
                // settled phonetics can reuse stable glyph sampling while the
                // timed primary paragraph continues to repaint.
                willChange: follow != null,
                child: Semantics(
                  label: widget.text,
                  textDirection: direction,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: horizontalGuard,
                        vertical: lyricVerticalInkGuard),
                    child: SizedBox(
                        width: _painter!.width, height: _painter!.height),
                  ),
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
      {this.inkOffset = Offset.zero,
      this.alignmentX,
      this.wrapFlight,
      this.layoutIdentity})
      : super(repaint: follow?.clock);
  final TextPainter text;
  final List<LyricFollowWordSlot> slots;
  final LyricWordFollow? follow;
  final Color? color;
  final Offset inkOffset;
  final double? alignmentX;
  final LyricWrapFlight? wrapFlight;
  // Capture geometry independently of the mutable retained TextPainter.
  final Object? layoutIdentity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(inkOffset.dx, inkOffset.dy);
    final flight = wrapFlight;
    if (flight == null) {
      paintLyricAlignment(canvas, text, alignmentX, () => _paintInk(canvas));
    } else {
      canvas.save();
      canvas.clipRect(flight.prefixClip, doAntiAlias: false);
      _paintInk(canvas);
      canvas.restore();
      canvas.save();
      canvas.translate(flight.offset.dx, flight.offset.dy);
      canvas.clipRect(flight.suffixClip, doAntiAlias: false);
      _paintInk(canvas);
      canvas.restore();
    }
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
      layoutIdentity != oldDelegate.layoutIdentity ||
      !identical(slots, oldDelegate.slots) ||
      follow?.clock != oldDelegate.follow?.clock ||
      follow?.curve != oldDelegate.follow?.curve ||
      follow?.distance != oldDelegate.follow?.distance ||
      inkOffset != oldDelegate.inkOffset ||
      color != oldDelegate.color ||
      alignmentX != oldDelegate.alignmentX ||
      wrapFlight != oldDelegate.wrapFlight;
}

/// Move each shaped line within its unchanged paragraph as alignment changes.
/// The caller uses left-aligned layout and animates the paragraph's own Align.
void paintLyricAlignment(
    Canvas canvas, TextPainter text, double? alignmentX, VoidCallback paint) {
  if (alignmentX == null || alignmentX <= -1) {
    paint();
    return;
  }
  final lines = text.computeLineMetrics();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final top = index == 0 ? -100.0 : line.baseline - line.ascent;
    final bottom = index == lines.length - 1
        ? text.height + 100
        : lines[index + 1].baseline - lines[index + 1].ascent;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-100, top, text.width + 100, bottom),
        doAntiAlias: false);
    canvas.translate(lyricAlignedOffset(text.width, line.width, alignmentX), 0);
    paint();
    canvas.restore();
  }
}

/// Keeps both endpoint paragraphs at fixed font sizes during a size change.
/// Their glyph layout never changes mid-frame, while the occupied height moves
/// continuously even if a word changes from one visual line to two. The caller
/// fades and scales the two children; this render object only interpolates the
/// space reserved for them.
class LyricFontMorph extends MultiChildRenderObjectWidget {
  const LyricFontMorph({
    super.key,
    required this.progress,
    required this.alignmentX,
    this.wrapStatus,
    required super.children,
  }) : assert(progress >= 0 && progress <= 1);

  final double progress;
  final double alignmentX;
  final LyricWrapFlightStatus? wrapStatus;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricFontMorph(progress, alignmentX, wrapStatus);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLyricFontMorph)
      ..progress = progress
      ..alignmentX = alignmentX
      ..wrapStatus = wrapStatus;
  }
}

class _LyricFontMorphParentData extends ContainerBoxParentData<RenderBox> {}

/// A changed line count needs a brief handoff: linear crossfading leaves the
/// same words legible in two places for much of the size tween. Equal-height
/// layouts keep the ordinary gradual blend of their nearby font sizes.
@visibleForTesting
({double outgoing, double incoming}) lyricFontBlendOpacities(
    double progress, double oldHeight, double newHeight,
    {bool lateHandoff = false}) {
  final t = progress.clamp(0.0, 1.0);
  final heightChange = (oldHeight - newHeight).abs();
  final lineHeightChanged =
      heightChange > math.max(12.0, math.min(oldHeight, newHeight) * .28);
  if (lineHeightChanged && lateHandoff) {
    final fraction = ((t - .985) / .015).clamp(0.0, 1.0);
    final handoff = fraction * fraction * (3 - 2 * fraction);
    return (outgoing: 1 - handoff, incoming: handoff);
  }
  if (!lineHeightChanged) {
    // Both endpoint fonts are shaped at different sizes. Blending them for the
    // entire tween makes their differently hinted stems trade dominance on
    // every frame even though each paragraph has a stable TextPainter. Let one
    // paragraph carry the visible scale, then hand its ink to the settled
    // endpoint over a short, eased interval.
    final fraction = ((t - .72) / .26).clamp(0.0, 1.0);
    final handoff = fraction * fraction * (3 - 2 * fraction);
    return (outgoing: 1 - handoff, incoming: handoff);
  }
  // A growing second line is revealed only after nearly all its height is
  // available. A disappearing second line fades before its space is reclaimed.
  // The 7/2 px margins account for the paragraphs' 4 px bottom ink guard.
  final (start, end) = newHeight > oldHeight
      ? (
          math.max(.82, 1 - 7 / heightChange),
          math.min(.985, 1 - 2 / heightChange),
        )
      : (0.0, math.min(.20, 7 / heightChange));
  final handoff = ((t - start) / (end - start)).clamp(0.0, 1.0);
  return (
    outgoing: (1 - handoff) * (1 - handoff),
    incoming: handoff * handoff,
  );
}

class _RenderLyricFontMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _LyricFontMorphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _LyricFontMorphParentData> {
  _RenderLyricFontMorph(this._progress, this._alignmentX, this._wrapStatus);

  double _progress;
  double _alignmentX;
  LyricWrapFlightStatus? _wrapStatus;
  double? _retargetHeight;
  set progress(double value) {
    if (_progress == value) return;
    if (value < _progress && hasSize) {
      // A rapid reversal begins at the height currently on screen. Its newly
      // shaped source may already be across a line-break threshold.
      _retargetHeight = size.height;
    }
    if (value >= 1) _retargetHeight = null;
    _progress = value;
    markNeedsLayout();
  }

  set alignmentX(double value) {
    if (_alignmentX == value) return;
    _alignmentX = value;
    markNeedsLayout();
  }

  set wrapStatus(LyricWrapFlightStatus? value) {
    if (identical(_wrapStatus, value)) return;
    _wrapStatus = value;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _LyricFontMorphParentData) {
      child.parentData = _LyricFontMorphParentData();
    }
  }

  Size _interpolatedSize(Size first, Size last) => Size(
        math.max(first.width, last.width),
        (_retargetHeight ?? first.height) +
            (last.height - (_retargetHeight ?? first.height)) * _progress,
      );

  @override
  void performLayout() {
    assert(firstChild != null);
    final childConstraints = constraints.loosen();
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      child = childAfter(child);
    }
    size = constraints
        .constrain(_interpolatedSize(firstChild!.size, lastChild!.size));
    child = firstChild;
    while (child != null) {
      (child.parentData! as _LyricFontMorphParentData).offset = Offset(
          lyricAlignedOffset(size.width, child.size.width, _alignmentX), 0);
      child = childAfter(child);
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final childConstraints = constraints.loosen();
    final first = firstChild?.getDryLayout(childConstraints) ?? Size.zero;
    final last = lastChild?.getDryLayout(childConstraints) ?? first;
    return constraints.constrain(_interpolatedSize(first, last));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final first = firstChild;
    final last = lastChild;
    if (first == null) return;
    if (identical(first, last)) {
      context.paintChild(first, offset);
      return;
    }
    final opacity = lyricFontBlendOpacities(
        _progress, first.size.height, last!.size.height,
        lateHandoff: _wrapStatus?.active == true);
    void paintWithOpacity(PaintingContext context, Offset offset,
        RenderBox child, double opacity) {
      if (opacity <= 0) return;
      final childOffset =
          offset + (child.parentData! as _LyricFontMorphParentData).offset;
      if (opacity >= 1) {
        context.paintChild(child, childOffset);
      } else {
        context.pushOpacity(childOffset, (opacity * 255).round(),
            (context, offset) => context.paintChild(child, offset));
      }
    }

    void paintPair(PaintingContext context, Offset offset) {
      paintWithOpacity(context, offset, first, opacity.outgoing);
      paintWithOpacity(context, offset, last, opacity.incoming);
    }

    // The handoff timing above keeps newly wrapped ink inside the available
    // space without cutting a glyph through its middle with a clip rectangle.
    paintPair(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    // During a blend only the newest paragraph receives descendant hits.
    final child = lastChild;
    return child?.hitTest(result,
            position: position -
                (child.parentData! as _LyricFontMorphParentData).offset) ??
        false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = (child.parentData! as _LyricFontMorphParentData).offset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (lastChild != null) visitor(lastChild!);
  }
}
