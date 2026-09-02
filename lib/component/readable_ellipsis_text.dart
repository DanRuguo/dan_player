import 'package:flutter/widgets.dart';

typedef ReadableTextFits = bool Function(String candidate);

/// Shortens [text] without splitting an ASCII word/number or a Unicode
/// grapheme. Whitespace immediately before the ellipsis is removed.
///
/// CJK, Japanese, and Korean text naturally advances one grapheme at a time;
/// emoji and other composed symbols stay intact through [String.characters].
@visibleForTesting
String truncateReadableSingleLine(
  String text,
  ReadableTextFits fits, {
  String ellipsis = '…',
}) {
  if (fits(text)) return text;
  if (!fits(ellipsis)) return '';

  final graphemes = text.characters.toList(growable: false);
  final tokenEnds = <int>[];
  var index = 0;
  while (index < graphemes.length) {
    if (_isWhitespace(graphemes[index])) {
      index++;
      continue;
    }
    if (_isAsciiAlphanumeric(graphemes[index])) {
      index++;
      while (
          index < graphemes.length && _isAsciiAlphanumeric(graphemes[index])) {
        index++;
      }
    } else {
      // A Characters entry is already one complete user-visible grapheme, so
      // this also keeps emoji/combining marks and special symbols intact.
      index++;
    }
    tokenEnds.add(index);
  }

  String candidateAt(int tokenIndex) =>
      '${graphemes.take(tokenEnds[tokenIndex]).join().trimRight()}$ellipsis';

  var low = 0;
  var high = tokenEnds.length - 1;
  var best = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (fits(candidateAt(middle))) {
      best = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return best < 0 ? ellipsis : candidateAt(best);
}

bool _isAsciiAlphanumeric(String grapheme) {
  if (grapheme.length != 1) return false;
  final code = grapheme.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a);
}

bool _isWhitespace(String grapheme) =>
    RegExp(r'^\s+$', unicode: true).hasMatch(grapheme);

/// A single-line menu label that paints its own boundary-aware ellipsis.
///
/// Extending [Text] keeps standard text/widget finders and menu semantics
/// compatible while replacing only the final constrained paint leaf.
class ReadableEllipsisText extends Text {
  const ReadableEllipsisText(
    super.data, {
    super.key,
    super.style,
  }) : super(
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        );

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = style;
    if (effectiveStyle == null || effectiveStyle.inherit) {
      effectiveStyle = defaults.style.merge(effectiveStyle);
    }
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    final fullText = data ?? '';
    return Semantics(
      label: fullText,
      excludeSemantics: true,
      child: _ReadableEllipsisLeaf(
        text: fullText,
        style: effectiveStyle,
        textAlign: textAlign ?? defaults.textAlign ?? TextAlign.start,
        textDirection: textDirection ?? Directionality.of(context),
        textScaler: textScaler ?? MediaQuery.textScalerOf(context),
        locale: locale ?? Localizations.maybeLocaleOf(context),
      ),
    );
  }

  @visibleForTesting
  static String debugDisplayedText(RenderObject root) {
    _RenderReadableEllipsisText? result;
    void find(RenderObject object) {
      if (object is _RenderReadableEllipsisText) {
        result = object;
        return;
      }
      object.visitChildren(find);
    }

    find(root);
    if (result == null) {
      throw ArgumentError.value(root, 'root', 'does not contain this text');
    }
    return result!.displayedText;
  }
}

class _ReadableEllipsisLeaf extends LeafRenderObjectWidget {
  const _ReadableEllipsisLeaf({
    required this.text,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.locale,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final Locale? locale;

  @override
  _RenderReadableEllipsisText createRenderObject(BuildContext context) =>
      _RenderReadableEllipsisText(
        text: text,
        style: style,
        textAlign: textAlign,
        textDirection: textDirection,
        textScaler: textScaler,
        locale: locale,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReadableEllipsisText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = style
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..locale = locale;
  }
}

class _RenderReadableEllipsisText extends RenderBox {
  _RenderReadableEllipsisText({
    required String text,
    required TextStyle style,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required Locale? locale,
  })  : _text = text,
        _style = style,
        _textAlign = textAlign,
        _textDirection = textDirection,
        _textScaler = textScaler,
        _locale = locale,
        _painter = TextPainter(
          textDirection: textDirection,
          textAlign: textAlign,
          textScaler: textScaler,
          locale: locale,
          maxLines: 1,
        );

  final TextPainter _painter;
  String _text;
  TextStyle _style;
  TextAlign _textAlign;
  TextDirection _textDirection;
  TextScaler _textScaler;
  Locale? _locale;
  String displayedText = '';

  set text(String value) {
    if (_text == value) return;
    _text = value;
    markNeedsLayout();
  }

  set style(TextStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsLayout();
  }

  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (_textScaler == value) return;
    _textScaler = value;
    markNeedsLayout();
  }

  set locale(Locale? value) {
    if (_locale == value) return;
    _locale = value;
    markNeedsLayout();
  }

  TextPainter _newPainter(String value) => TextPainter(
        text: TextSpan(text: value, style: _style, locale: _locale),
        textAlign: _textAlign,
        textDirection: _textDirection,
        textScaler: _textScaler,
        locale: _locale,
        maxLines: 1,
      );

  bool _fits(String candidate, double maxWidth) {
    final painter = _newPainter(candidate)..layout();
    final fits = !painter.didExceedMaxLines && painter.width <= maxWidth;
    painter.dispose();
    return fits;
  }

  String _displayFor(double maxWidth) {
    if (!maxWidth.isFinite) return _text;
    if (maxWidth <= 0) return '';
    return truncateReadableSingleLine(
      _text,
      (candidate) => _fits(candidate, maxWidth),
    );
  }

  Size _measure(BoxConstraints constraints) {
    final value = _displayFor(constraints.maxWidth);
    final painter = _newPainter(value)..layout();
    final measured = constraints.constrain(Size(painter.width, painter.height));
    painter.dispose();
    return measured;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  @override
  double computeMinIntrinsicWidth(double height) {
    final painter = _newPainter(_text)..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) =>
      computeMinIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _measure(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  void performLayout() {
    displayedText = _displayFor(constraints.maxWidth);
    _painter
      ..text = TextSpan(
        text: displayedText,
        style: _style,
        locale: _locale,
      )
      ..textAlign = _textAlign
      ..textDirection = _textDirection
      ..textScaler = _textScaler
      ..locale = _locale
      ..layout();
    size = constraints.constrain(Size(_painter.width, _painter.height));
    _painter.layout(minWidth: size.width, maxWidth: size.width);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _painter.computeDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    _painter.paint(context.canvas, offset);
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
