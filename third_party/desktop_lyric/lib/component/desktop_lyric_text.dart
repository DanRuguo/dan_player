import 'dart:math' as math;

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/font_policy.dart';
import 'package:desktop_lyric/lyric_ruby.dart';
import 'package:desktop_lyric/lyric_glyph_morph.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/material.dart';

/// A whole Unicode grapheme or a vertical display unit, never a partial UTF-16
/// code unit. Original string offsets let timed words and painted units share
/// one stable layout.
class DesktopLyricGlyph {
  const DesktopLyricGlyph(this.text, this.start, this.end,
      {this.horizontal = false});
  final String text;
  final int start;
  final int end;

  /// Foreign words stay upright on one row in a vertical lyric column. CJK
  /// graphemes and emoji keep the traditional top-to-bottom progression.
  final bool horizontal;
}

List<DesktopLyricGlyph> desktopLyricGlyphs(String text) {
  var offset = 0;
  return [
    for (final grapheme in text.characters)
      DesktopLyricGlyph(grapheme, offset, offset += grapheme.length)
  ];
}

bool _isVerticalCjk(int rune) =>
    (rune >= 0x1100 && rune <= 0x11ff) || // Hangul Jamo
    (rune >= 0x2e80 && rune <= 0x303f) || // CJK radicals/punctuation
    (rune >= 0x3040 && rune <= 0x30ff) || // Hiragana/Katakana
    (rune >= 0x3100 && rune <= 0x31bf) || // Bopomofo
    (rune >= 0x31f0 && rune <= 0x31ff) || // Katakana extensions
    (rune >= 0x3400 && rune <= 0x4dbf) || // CJK Extension A
    (rune >= 0x4e00 && rune <= 0x9fff) || // Unified ideographs
    (rune >= 0xa960 && rune <= 0xa97f) || // Hangul Jamo Extended-A
    (rune >= 0xac00 && rune <= 0xd7ff) || // Hangul syllables/Jamo B
    (rune >= 0xf900 && rune <= 0xfaff) || // Compatibility ideographs
    (rune >= 0xff66 && rune <= 0xff9d) || // Half-width Katakana
    (rune >= 0x20000 && rune <= 0x323af); // Supplementary CJK

bool _isStandalonePictograph(DesktopLyricGlyph glyph) {
  final rune = glyph.text.runes.first;
  return (rune >= 0x1f000 && rune <= 0x1faff) ||
      (rune >= 0x2600 && rune <= 0x27bf) ||
      glyph.text.contains('\u20e3');
}

bool _isVerticalSeparator(DesktopLyricGlyph glyph) => glyph.text.trim().isEmpty;

/// Segments a vertical lyric into readable rows.
///
/// CJK text and emoji retain one grapheme per row. Other space-delimited text
/// stays in one upright row, so `can't`, `mother-in-law`, abbreviations,
/// numbers and their adjacent punctuation are never split into letters.
List<DesktopLyricGlyph> desktopLyricVerticalUnits(String text) {
  final graphemes = desktopLyricGlyphs(text);
  final units = <DesktopLyricGlyph>[];
  var index = 0;
  while (index < graphemes.length) {
    final current = graphemes[index];
    if (_isVerticalSeparator(current)) {
      index += 1;
      continue;
    }
    if (_isVerticalCjk(current.text.runes.first) ||
        _isStandalonePictograph(current)) {
      units.add(current);
      index += 1;
      continue;
    }

    final first = index;
    index += 1;
    while (index < graphemes.length) {
      final next = graphemes[index];
      if (_isVerticalSeparator(next) ||
          _isVerticalCjk(next.text.runes.first) ||
          _isStandalonePictograph(next)) {
        break;
      }
      index += 1;
    }
    units.add(DesktopLyricGlyph(
      graphemes.sublist(first, index).map((glyph) => glyph.text).join(),
      graphemes[first].start,
      graphemes[index - 1].end,
      horizontal: true,
    ));
  }
  return units;
}

/// Cached horizontal paragraph or upright grapheme column. Clock ticks repaint
/// only; no word/glyph widget layout is performed at playback frequency.
class DesktopLyricText extends StatefulWidget {
  const DesktopLyricText(
      {super.key,
      required this.text,
      required this.clock,
      required this.style,
      required this.playedColor,
      required this.unplayedColor,
      this.strokeColor,
      this.words = const [],
      this.vertical = false,
      this.verticalLetterSpacing = 0,
      this.maxVerticalUnitWidth,
      this.maxHorizontalWidth,
      this.rubySpans = const [],
      this.rubyVisibility = 1,
      this.reducedMotion = false});

  final String text;
  final PlaybackClock clock;
  final TextStyle style;
  final Color playedColor;
  final Color unplayedColor;
  final Color? strokeColor;
  final List<DesktopLyricWord> words;
  final List<LyricRubySpan> rubySpans;
  final double rubyVisibility;
  final bool vertical;

  /// Additional gap between complete upright display units. Horizontal words
  /// retain their natural TextStyle tracking; the extra gap is applied once.
  final double verticalLetterSpacing;
  final double? maxVerticalUnitWidth;

  /// Bounded single-line mode shares the same timed-word painter. Flutter's
  /// paragraph ellipsis excludes hidden glyphs from the existing word boxes.
  final double? maxHorizontalWidth;
  final bool reducedMotion;

  @override
  State<DesktopLyricText> createState() => _DesktopLyricTextState();
}

class _DesktopLyricTextState extends State<DesktopLyricText>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Object? _identity;
  Object? _shapeIdentity;
  _DesktopLyricTextShaping? _shaping;
  _DesktopLyricTextLayout? _layout;
  _DesktopLyricTextShaping? _previousShaping;
  _DesktopLyricTextLayout? _previousLayout;
  Object? _spacingBaseIdentity;
  double? _lastSpacing;
  Size? _retargetSize;
  final _glyphMotions = <int, LyricGlyphMorph>{};
  final _strokeMotions = <int, LyricGlyphMorph>{};
  double _retargetProgress = 1;
  static const _spacingCurve = Cubic(.22, 0, .16, 1);
  bool _lifecycleHidden = false;
  late final AnimationController _spacingMotion =
      AnimationController(vsync: this, duration: AppMotion.lyricLine, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _releasePrevious();
        });
  bool _reduced = true;
  int _wordEndMilliseconds = 0;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _lifecycleHidden = lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached;
    WidgetsBinding.instance.addObserver(this);
    _attachClock();
  }

  void _releasePrevious() {
    for (final morph in [..._glyphMotions.values, ..._strokeMotions.values]) {
      morph.dispose();
    }
    _glyphMotions.clear();
    _strokeMotions.clear();
    _previousLayout?.ruby?.dispose();
    _previousShaping?.dispose();
    _previousShaping = null;
    _previousLayout = null;
    _retargetSize = null;
  }

  void _finishSpacing() {
    _spacingMotion.stop();
    _spacingMotion.value = 1;
    _releasePrevious();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleHidden = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (_lifecycleHidden) _finishSpacing();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  void _attachClock() {
    if (widget.words.isNotEmpty) {
      widget.clock.addListener(_syncSamplingDemand);
    }
  }

  @override
  void didUpdateWidget(DesktopLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock) ||
        !identical(oldWidget.words, widget.words)) {
      if (oldWidget.words.isNotEmpty) {
        oldWidget.clock.removeListener(_syncSamplingDemand);
      }
      oldWidget.clock.setVisualSamplingDemand(this, false);
      _attachClock();
    }
  }

  void _syncSamplingDemand() {
    widget.clock.setVisualSamplingDemand(
        this,
        !_reduced &&
            widget.words.isNotEmpty &&
            widget.clock.positionMilliseconds < _wordEndMilliseconds);
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final fontPolicy = AppFontScope.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final reducedMotion = widget.reducedMotion ||
        _lifecycleHidden ||
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations ||
        !AppMotion.enabled(context, MotionKind.lyrics) ||
        !TickerMode.valuesOf(context).enabled;
    _reduced = reducedMotion;
    // TextPainter does not inherit the app's font as Text does. Merge the real
    // desktop typography before caching so CJK/fallback fonts stay identical.
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final spacingBaseIdentity = (
      widget.text,
      widget.words,
      widget.rubySpans,
      widget.vertical,
      widget.maxHorizontalWidth != null && widget.maxHorizontalWidth!.isFinite,
      style.copyWith(
          letterSpacing:
              (style.letterSpacing ?? 0) - widget.verticalLetterSpacing),
      widget.playedColor,
      widget.unplayedColor,
      widget.strokeColor,
      direction,
      scaler,
      locale,
      fontPolicy,
    );
    final spacingAllowed = !reducedMotion &&
        !_lifecycleHidden &&
        AppMotion.enabled(context, MotionKind.layout) &&
        !WidgetsBinding
            .instance.platformDispatcher.accessibilityFeatures.reduceMotion;
    if (!spacingAllowed) _finishSpacing();
    _DesktopLyricTextShaping shape(double spacing) => _DesktopLyricTextShaping(
        text: widget.text,
        rubySpans: widget.rubySpans,
        words: widget.words,
        vertical: widget.vertical,
        verticalLetterSpacing: spacing,
        bounded: !widget.vertical &&
            widget.maxHorizontalWidth != null &&
            widget.maxHorizontalWidth!.isFinite,
        style: lyricRubyPrimaryStyle(
            spacing == widget.verticalLetterSpacing
                ? style
                : style.copyWith(
                    letterSpacing: (style.letterSpacing ?? 0) -
                        widget.verticalLetterSpacing +
                        spacing),
            widget.vertical ? const [] : widget.rubySpans),
        playedColor: widget.playedColor,
        unplayedColor: widget.unplayedColor,
        strokeColor: widget.strokeColor,
        direction: direction,
        scaler: scaler,
        locale: locale,
        fontPolicy: fontPolicy);
    _DesktopLyricTextLayout geometry(_DesktopLyricTextShaping shaping) =>
        _DesktopLyricTextLayout(
            shaping: shaping,
            maxVerticalUnitWidth: widget.maxVerticalUnitWidth,
            maxHorizontalWidth: widget.maxHorizontalWidth);
    final shapeIdentity = (
      widget.text,
      widget.words,
      widget.rubySpans,
      widget.vertical,
      widget.vertical ? widget.verticalLetterSpacing : 0,
      !widget.vertical &&
          widget.maxHorizontalWidth != null &&
          widget.maxHorizontalWidth!.isFinite,
      style,
      widget.playedColor,
      widget.unplayedColor,
      widget.strokeColor,
      direction,
      scaler,
      locale,
      fontPolicy
    );
    final identity = (
      shapeIdentity,
      widget.maxVerticalUnitWidth,
      widget.maxHorizontalWidth,
    );
    if (_identity != identity) {
      // A retained paragraph is relaid out in place when only its width
      // changes. Continue from the last presented geometry before mutating
      // that target, just as a second spacing edit does.
      if (_shapeIdentity == shapeIdentity && _previousLayout != null) {
        final progress = _spacingCurve.transform(_spacingMotion.value);
        final presentedSize = Size.lerp(
            _retargetSize ?? _previousLayout!.size, _layout!.size, progress)!;
        final presented = _DesktopLyricTextLayout.interpolate(
            _previousLayout!, _layout!, progress,
            sourceShaping: _previousShaping,
            horizontalMotion: _glyphMotions[0]);
        _previousLayout?.ruby?.dispose();
        _previousLayout = presented;
        _retargetSize = presentedSize;
        _retargetProgress = progress;
        _spacingMotion.forward(from: 0);
      }
      if (_shapeIdentity != shapeIdentity) {
        final spacingChanged = _lastSpacing != null &&
            _lastSpacing != widget.verticalLetterSpacing &&
            _spacingBaseIdentity == spacingBaseIdentity &&
            spacingAllowed;
        if (spacingChanged) {
          final progress = _spacingCurve.transform(_spacingMotion.value);
          final presentedSize = _previousLayout == null
              ? _layout!.size
              : Size.lerp(_retargetSize ?? _previousLayout!.size, _layout!.size,
                  progress)!;
          final wasMoving = _previousLayout != null;
          _spacingMotion.stop();
          if (wasMoving) {
            final presented = _DesktopLyricTextLayout.interpolate(
                _previousLayout!, _layout!, progress,
                sourceShaping: _previousShaping,
                horizontalMotion: _glyphMotions[0]);
            _previousLayout?.ruby?.dispose();
            _previousLayout = presented;
            _layout?.ruby?.dispose();
            _shaping?.dispose();
          } else {
            _previousShaping = _shaping;
            _previousLayout = _layout;
          }
          _retargetProgress = progress;
          _retargetSize = wasMoving ? presentedSize : null;
          _spacingMotion.forward(from: 0);
        } else {
          _finishSpacing();
          _layout?.ruby?.dispose();
          _shaping?.dispose();
        }
        _shaping = shape(widget.verticalLetterSpacing);
        _shapeIdentity = shapeIdentity;
      }
      if (identical(_layout?.shaping, _shaping)) _layout?.ruby?.dispose();
      _layout = geometry(_shaping!);
      if (_previousShaping != null) {
        final from = _previousLayout!;
        void cache(int key, TextPainter source, TextPainter target,
            Map<int, LyricGlyphMorph> motions,
            {bool centered = false}) {
          final existing = motions[key];
          final offset = centered
              ? Offset((source.width - target.width) / 2, 0)
              : Offset.zero;
          final next = existing == null
              ? LyricGlyphMorph(
                  from: source,
                  to: target,
                  targetOffset: offset,
                  pixelRatio: MediaQuery.devicePixelRatioOf(context))
              : LyricGlyphMorph.retarget(existing, target, _retargetProgress,
                  targetOffset: centered
                      ? Offset(
                          (existing.sourceSize.width - target.width) / 2, 0)
                      : Offset.zero);
          existing?.dispose();
          motions[key] = next;
        }

        if (!widget.vertical) {
          cache(0, from.highlight!, _layout!.highlight!, _glyphMotions,
              centered: true);
          if (from.stroke != null && _layout!.stroke != null) {
            cache(0, from.stroke!, _layout!.stroke!, _strokeMotions,
                centered: true);
          }
        } else {
          for (var index = 0; index < from.glyphs.length; index++) {
            if (!from.glyphs[index].glyph.horizontal) continue;
            cache(index, from.glyphs[index].highlight,
                _layout!.glyphs[index].highlight, _glyphMotions);
            if (from.glyphs[index].stroke != null &&
                _layout!.glyphs[index].stroke != null) {
              cache(index, from.glyphs[index].stroke!,
                  _layout!.glyphs[index].stroke!, _strokeMotions);
            }
          }
        }
      }
      _lastSpacing = widget.verticalLetterSpacing;
      _spacingBaseIdentity = spacingBaseIdentity;
      _identity = identity;
      // A bounded paragraph can omit trailing authored words entirely. Only
      // words with visible shaped boxes can keep its sampler alive. Recompute
      // after every width/font/direction/mode layout, including restored glyphs.
      _wordEndMilliseconds = 0;
      for (var index = 0; index < _layout!.words.length; index++) {
        if (_layout!.wordExtents[index] <= 0) continue;
        final word = _layout!.words[index];
        _wordEndMilliseconds = math.max(_wordEndMilliseconds,
            word.startMilliseconds + math.max(0, word.lengthMilliseconds));
      }
    }
    _syncSamplingDemand();
    return AnimatedBuilder(
      animation: _spacingMotion,
      builder: (context, _) {
        final progress = _spacingCurve.transform(_spacingMotion.value);
        final previous = _previousLayout;
        var size = previous == null
            ? _layout!.size
            : Size.lerp(
                _retargetSize ?? previous.size, _layout!.size, progress)!;
        final readingExtent = (_layout!.ruby?.extent ?? 0) +
            (widget.vertical ? 0 : (_layout!.ruby?.extraLeading ?? 0));
        size = widget.vertical
            ? Size(
                math.max(0,
                    size.width - readingExtent * (1 - widget.rubyVisibility)),
                size.height)
            : Size(
                size.width,
                math.max(0,
                    size.height - readingExtent * (1 - widget.rubyVisibility)));
        return SizedBox.fromSize(
          size: size,
          child: RepaintBoundary(
              child: CustomPaint(
            painter: DesktopLyricTextPainter._(
                layout: _layout!,
                previousLayout: previous,
                glyphMotions: _glyphMotions,
                strokeMotions: _strokeMotions,
                layoutProgress: progress,
                clock: widget.clock,
                rubyVisibility: widget.rubyVisibility,
                reducedMotion: reducedMotion),
            isComplex: true,
            willChange: widget.words.isNotEmpty && !reducedMotion,
          )),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.clock.setVisualSamplingDemand(this, false);
    WidgetsBinding.instance.removeObserver(this);
    if (widget.words.isNotEmpty) {
      widget.clock.removeListener(_syncSamplingDemand);
    }
    _shaping?.dispose();
    _layout?.ruby?.dispose();
    _spacingMotion.dispose();
    _releasePrevious();
    super.dispose();
  }
}

class _GlyphShaping {
  _GlyphShaping(this.glyph, this.base, this.highlight, this.stroke);
  final DesktopLyricGlyph glyph;
  final TextPainter base;
  final TextPainter highlight;
  final TextPainter? stroke;
}

/// Width changes relayout retained horizontal paragraphs or rescale already
/// shaped vertical units. Text, typography and paint changes own their lifetime.
class _DesktopLyricTextShaping {
  _DesktopLyricTextShaping(
      {required this.text,
      required this.rubySpans,
      required List<DesktopLyricWord> words,
      required this.vertical,
      required double verticalLetterSpacing,
      required bool bounded,
      required TextStyle style,
      required this.playedColor,
      required this.unplayedColor,
      required Color? strokeColor,
      required TextDirection direction,
      required TextScaler scaler,
      required Locale? locale,
      required this.fontPolicy})
      : words = _DesktopLyricTextLayout._shapedWords(text, words) {
    // Index the existing grapheme-merged timing words once. A spacing morph
    // queries these UTF-16 offsets for each word on every presentation frame.
    final starts = <int>[];
    var sourceOffset = 0;
    for (final word in this.words) {
      starts.add(sourceOffset);
      sourceOffset += word.content.length;
    }
    wordSourceStarts = List<int>.unmodifiable(starts);
    rubyStyle = style.copyWith(color: playedColor);
    rubyDirection = direction;
    rubyScaler = scaler;
    rubyLocale = locale;
    if (rubySpans.isNotEmpty) {
      rubyShaping = LyricRubyShaping(
          spans: rubySpans,
          style: rubyStyle,
          policy: fontPolicy,
          direction: direction,
          scaler: scaler,
          locale: locale,
          vertical: vertical);
    }
    fontSize = scaler.scale(style.fontSize ?? 22);
    letterSpacing = verticalLetterSpacing;
    TextPainter painter(String text, Color color,
            {UiLanguage? language, bool upright = false}) =>
        TextPainter(
          text: appFontSpan(text,
              style: style.copyWith(
                  color: color,
                  letterSpacing: upright
                      ? (style.letterSpacing ?? 0) - verticalLetterSpacing
                      : style.letterSpacing),
              policy: fontPolicy,
              language: language),
          textDirection: direction,
          textScaler: scaler,
          locale: locale,
          maxLines: 1,
          ellipsis: bounded ? '…' : null,
        );
    TextPainter? outline(String text,
            {UiLanguage? language, bool upright = false}) =>
        strokeColor == null
            ? null
            : (TextPainter(
                text: appFontSpan(text,
                    policy: fontPolicy,
                    language: language,
                    style: style.copyWith(
                      letterSpacing: upright
                          ? (style.letterSpacing ?? 0) - verticalLetterSpacing
                          : style.letterSpacing,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth =
                            ((style.fontSize ?? 22) * .06).clamp(1.2, 2.4)
                        ..strokeJoin = StrokeJoin.round
                        ..color = strokeColor,
                      shadows: const [],
                    )),
                textDirection: direction,
                textScaler: scaler,
                locale: locale,
                maxLines: 1,
                ellipsis: bounded ? '…' : null,
              ));
    if (!vertical) {
      base = painter(text, unplayedColor);
      highlight = painter(text, playedColor);
      stroke = outline(text);
      return;
    }
    // Resolve script context on the complete original line, then reuse it for
    // upright units. Isolated Han glyphs would otherwise lose adjacent Kana
    // or Hangul context. UTF-16 starts still belong to the authored text.
    final runs = fontPolicy.mixedScripts
        ? appFontRuns(text, fontPolicy.language)
        : const <AppFontRun>[];
    var runIndex = 0;
    var runEnd = runs.isEmpty ? text.length : runs.first.text.length;
    for (final glyph in desktopLyricVerticalUnits(text)) {
      while (runIndex + 1 < runs.length && glyph.start >= runEnd) {
        runIndex++;
        runEnd += runs[runIndex].text.length;
      }
      final language =
          runs.isEmpty ? fontPolicy.language : runs[runIndex].language;
      final display =
          glyph.text == '\n' || glyph.text == '\r\n' ? ' ' : glyph.text;
      final stroke = outline(display,
          language: language, upright: !glyph.horizontal && letterSpacing != 0);
      stroke?.layout();
      glyphs.add(_GlyphShaping(
          glyph,
          painter(display, unplayedColor,
              language: language,
              upright: !glyph.horizontal && letterSpacing != 0)
            ..layout(),
          painter(display, playedColor,
              language: language,
              upright: !glyph.horizontal && letterSpacing != 0)
            ..layout(),
          stroke));
    }
  }

  final String text;
  final List<LyricRubySpan> rubySpans;
  final AppFontPolicy fontPolicy;
  late final TextStyle rubyStyle;
  late final TextDirection rubyDirection;
  late final TextScaler rubyScaler;
  late final Locale? rubyLocale;
  LyricRubyShaping? rubyShaping;
  final List<DesktopLyricWord> words;
  late final List<int> wordSourceStarts;
  final bool vertical;
  final Color playedColor, unplayedColor;
  late final double fontSize;
  late final double letterSpacing;
  final List<_GlyphShaping> glyphs = [];
  TextPainter? base;
  TextPainter? highlight;
  TextPainter? stroke;

  void dispose() {
    rubyShaping?.dispose();
    base?.dispose();
    highlight?.dispose();
    stroke?.dispose();
    for (final glyph in glyphs) {
      glyph.base.dispose();
      glyph.highlight.dispose();
      glyph.stroke?.dispose();
    }
  }
}

class _GlyphPaint {
  _GlyphPaint(this.shaping,
      {required this.bounds, required this.paintOffset, required this.scale});
  final _GlyphShaping shaping;
  DesktopLyricGlyph get glyph => shaping.glyph;
  TextPainter get base => shaping.base;
  TextPainter get highlight => shaping.highlight;
  TextPainter? get stroke => shaping.stroke;
  final Rect bounds;
  final Offset paintOffset;
  final double scale;
}

/// Each width owns independent geometry, so replacing a layout never mutates
/// the old painter's boxes or makes shouldRepaint miss a retained paragraph.
class _DesktopLyricTextLayout {
  _DesktopLyricTextLayout.interpolate(
      _DesktopLyricTextLayout from, _DesktopLyricTextLayout to, double progress,
      {_DesktopLyricTextShaping? sourceShaping,
      LyricGlyphMorph? horizontalMotion})
      : shaping = sourceShaping ?? to.shaping {
    size = Size.lerp(from.size, to.size, progress)!;
    if (from.ruby != null && to.ruby != null) {
      ruby = LyricRubyLayout.interpolate(from.ruby!, to.ruby!, progress,
          retainSourcePainter: sourceShaping != null);
    }
    if (!vertical) {
      // Ellipsis can split or remove a selection box as spacing/width changes.
      // The actual presentation is indexed by authored glyph ranges, never by
      // a positional zip of the two endpoints' selection boxes.
      final motion = horizontalMotion;
      if (motion == null) {
        wordBoxes.addAll(to.wordBoxes);
      } else {
        final shift = Offset((size.width - motion.sourceSize.width) / 2, 0);
        for (var word = 0; word < words.length; word++) {
          final start = shaping.wordSourceStarts[word];
          wordBoxes.add([
            for (final box in motion.boxes(
                start, start + words[word].content.length, progress))
              (
                rect: box.shift(shift),
                rtl: to.wordBoxes[word].firstOrNull?.rtl ??
                    from.wordBoxes[word].firstOrNull?.rtl ??
                    false,
                horizontal: true,
              )
          ]);
        }
      }
      return;
    }
    for (var index = 0; index < to.glyphs.length; index++) {
      final previous = from.glyphs[index], target = to.glyphs[index];
      glyphs.add(_GlyphPaint(
          sourceShaping == null ? target.shaping : sourceShaping.glyphs[index],
          bounds: Rect.lerp(previous.bounds, target.bounds, progress)!,
          paintOffset:
              Offset.lerp(previous.paintOffset, target.paintOffset, progress)!,
          scale: previous.scale + (target.scale - previous.scale) * progress));
    }
    for (var word = 0; word < to.wordBoxes.length; word++) {
      wordBoxes.add([
        for (var box = 0; box < to.wordBoxes[word].length; box++)
          (
            rect: Rect.lerp(from.wordBoxes[word][box].rect,
                to.wordBoxes[word][box].rect, progress)!,
            rtl: to.wordBoxes[word][box].rtl,
            horizontal: to.wordBoxes[word][box].horizontal,
          )
      ]);
    }
  }

  _DesktopLyricTextLayout(
      {required this.shaping,
      required double? maxVerticalUnitWidth,
      required double? maxHorizontalWidth}) {
    if (!vertical) {
      final width = maxHorizontalWidth == null
          ? double.infinity
          : math.max(0.0, maxHorizontalWidth);
      base!.layout(maxWidth: width);
      final rubyWidth =
          layoutRubyWordSafe(base!, shaping.rubySpans, width, width);
      highlight!.layout(maxWidth: rubyWidth);
      stroke?.layout(maxWidth: rubyWidth);
      if (shaping.rubySpans.isNotEmpty) {
        ruby = LyricRubyLayout(
            primary: base,
            spans: shaping.rubySpans,
            style: shaping.rubyStyle,
            policy: shaping.fontPolicy,
            direction: shaping.rubyDirection,
            scaler: shaping.rubyScaler,
            locale: shaping.rubyLocale,
            shaping: shaping.rubyShaping,
            width: base!.width);
      }
      size = Size(base!.width,
          base!.height + (ruby?.extent ?? 0) + (ruby?.extraLeading ?? 0));
      var offset = 0;
      for (final word in words) {
        wordBoxes.add(base!
            .getBoxesForSelection(TextSelection(
              baseOffset: offset,
              extentOffset: offset += word.content.length,
            ))
            .map((box) => (
                  rect: box.toRect(),
                  rtl: box.direction == TextDirection.rtl,
                  horizontal: true,
                ))
            .toList(growable: false));
      }
      return;
    }
    final widthLimit = maxVerticalUnitWidth != null &&
            maxVerticalUnitWidth.isFinite &&
            maxVerticalUnitWidth > 0
        ? math.max(
            1.0,
            maxVerticalUnitWidth -
                (shaping.rubySpans.isEmpty ? 0 : fontSize * .51))
        : double.infinity;
    double scaleFor(_GlyphShaping glyph) =>
        glyph.base.width > widthLimit ? widthLimit / glyph.base.width : 1;
    final columnWidth = shaping.glyphs.fold<double>(
        0,
        (maxWidth, glyph) =>
            math.max(maxWidth, glyph.base.width * scaleFor(glyph)));
    var top = 0.0;
    for (final glyph in shaping.glyphs) {
      if (glyphs.isNotEmpty) top += shaping.letterSpacing;
      final scale = scaleFor(glyph);
      final height = math.max(glyph.base.height, fontSize * 1.15);
      glyphs.add(_GlyphPaint(glyph,
          bounds: Rect.fromLTWH(0, top, columnWidth, height),
          paintOffset: Offset((columnWidth - glyph.base.width * scale) / 2,
              top + (height - glyph.base.height * scale) / 2),
          scale: scale));
      top += height;
    }
    if (shaping.rubySpans.isNotEmpty) {
      ruby = LyricRubyLayout(
          spans: shaping.rubySpans,
          style: shaping.rubyStyle,
          policy: shaping.fontPolicy,
          direction: shaping.rubyDirection,
          scaler: shaping.rubyScaler,
          locale: shaping.rubyLocale,
          shaping: shaping.rubyShaping,
          width: columnWidth,
          vertical: true,
          verticalUnits: [
            for (final glyph in glyphs)
              (
                start: glyph.glyph.start,
                end: glyph.glyph.end,
                bounds: glyph.bounds
              )
          ]);
    }
    size = Size(columnWidth + (ruby?.extent ?? 0), top);
    var offset = 0;
    for (final word in words) {
      final start = offset.clamp(0, text.length);
      offset += word.content.length;
      final end = offset.clamp(0, text.length);
      final boxes = <({Rect rect, bool rtl, bool horizontal})>[];
      for (final glyph in glyphs) {
        if (glyph.glyph.horizontal) {
          final selectionStart = math.max(start, glyph.glyph.start);
          final selectionEnd = math.min(end, glyph.glyph.end);
          if (selectionStart >= selectionEnd) continue;
          for (final box in glyph.base.getBoxesForSelection(TextSelection(
            baseOffset: selectionStart - glyph.glyph.start,
            extentOffset: selectionEnd - glyph.glyph.start,
          ))) {
            boxes.add((
              rect: Rect.fromLTRB(
                glyph.paintOffset.dx + box.left * glyph.scale,
                glyph.paintOffset.dy + box.top * glyph.scale,
                glyph.paintOffset.dx + box.right * glyph.scale,
                glyph.paintOffset.dy + box.bottom * glyph.scale,
              ),
              rtl: box.direction == TextDirection.rtl,
              horizontal: true,
            ));
          }
        } else if (glyph.glyph.start >= start && glyph.glyph.start < end) {
          boxes.add((rect: glyph.bounds, rtl: false, horizontal: false));
        }
      }
      wordBoxes.add(boxes);
    }
  }

  final _DesktopLyricTextShaping shaping;
  String get text => shaping.text;
  List<DesktopLyricWord> get words => shaping.words;
  bool get vertical => shaping.vertical;
  final List<_GlyphPaint> glyphs = [];
  TextPainter? get base => shaping.base;
  TextPainter? get highlight => shaping.highlight;
  TextPainter? get stroke => shaping.stroke;
  late final Size size;
  double get fontSize => shaping.fontSize;
  final List<List<({Rect rect, bool rtl, bool horizontal})>> wordBoxes = [];
  LyricRubyLayout? ruby;
  late final List<double> wordExtents = [
    for (final boxes in wordBoxes)
      boxes.fold<double>(
          0,
          (total, box) =>
              total +
              (vertical && !box.horizontal ? box.rect.height : box.rect.width))
  ];
  late final List<double> wordSoftness = [
    for (final extent in wordExtents)
      LyricWordEffects.softEdgeWidth(fontSize: fontSize, extent: extent)
  ];

  /// The owning player's renderer also joins timing fragments that divide one
  /// Unicode grapheme. Keep one mask and the union of its actual timing here;
  /// partial selections have no horizontal boxes and would lose later timing
  /// in vertical mode. This runs only when shaping, never on clock samples.
  static List<DesktopLyricWord> _shapedWords(
      String text, List<DesktopLyricWord> authored) {
    if (authored.isEmpty) return authored;
    final boundaries = <int>{0};
    var endOffset = 0;
    for (final character in text.characters) {
      endOffset += character.length;
      boundaries.add(endOffset);
    }
    final result = <DesktopLyricWord>[];
    var offset = 0;
    for (var index = 0; index < authored.length; index++) {
      final word = authored[index];
      offset += word.content.length;
      int start = word.startMilliseconds;
      int end = start + math.max(0, word.lengthMilliseconds);
      StringBuffer? joined;
      while (offset < text.length &&
          !boundaries.contains(offset) &&
          index + 1 < authored.length) {
        final next = authored[++index];
        joined ??= StringBuffer(word.content);
        joined.write(next.content);
        start = math.min(start, next.startMilliseconds);
        end = math.max(
            end, next.startMilliseconds + math.max(0, next.lengthMilliseconds));
        offset += next.content.length;
      }
      result.add(joined == null
          ? word
          : DesktopLyricWord(start, end - start, joined.toString()));
    }
    return result;
  }

  // A separate cached pass under both fills. Word clipping never cuts an
  // outline in half and no paragraphs are laid out on playback clock ticks.
  void paintStroke(Canvas canvas) {
    if (!vertical) {
      stroke?.paint(canvas, Offset.zero);
      return;
    }
    for (final glyph in glyphs) {
      if (glyph.stroke == null) continue;
      canvas.save();
      canvas.translate(glyph.paintOffset.dx, glyph.paintOffset.dy);
      canvas.scale(glyph.scale, glyph.scale);
      glyph.stroke!.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  void paint(Canvas canvas, {required bool played}) {
    if (!vertical) {
      (played ? highlight : base)!.paint(canvas, Offset.zero);
      return;
    }
    for (final glyph in glyphs) {
      final painter = played ? glyph.highlight : glyph.base;
      canvas.save();
      canvas.translate(glyph.paintOffset.dx, glyph.paintOffset.dy);
      canvas.scale(glyph.scale, glyph.scale);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }
}

class DesktopLyricTextPainter extends CustomPainter {
  DesktopLyricTextPainter._(
      {required _DesktopLyricTextLayout layout,
      _DesktopLyricTextLayout? previousLayout,
      double layoutProgress = 1,
      Map<int, LyricGlyphMorph> glyphMotions = const {},
      Map<int, LyricGlyphMorph> strokeMotions = const {},
      this.rubyVisibility = 1,
      required this.clock,
      required this.reducedMotion})
      : _layout = previousLayout != null && layout.vertical
            ? _DesktopLyricTextLayout.interpolate(
                previousLayout, layout, layoutProgress)
            : layout,
        _previousLayout = layout.vertical ? null : previousLayout,
        _glyphMotions = glyphMotions,
        _strokeMotions = strokeMotions,
        _layoutProgress = layoutProgress,
        super(
            repaint: layout.words.isNotEmpty && !reducedMotion ? clock : null);

  final _DesktopLyricTextLayout _layout;
  final _DesktopLyricTextLayout? _previousLayout;
  final Map<int, LyricGlyphMorph> _glyphMotions, _strokeMotions;
  Size _paintSize = Size.zero;
  final double _layoutProgress;
  final double rubyVisibility;
  @visibleForTesting
  double get layoutProgress => _layoutProgress;
  @visibleForTesting
  bool get retainsPreviousLayout => _layoutProgress < 1;
  final PlaybackClock clock;
  final bool reducedMotion;

  bool get vertical => _layout.vertical;
  @visibleForTesting
  LyricRubyLayout? get rubyLayout => _layout.ruby;
  @visibleForTesting
  Object get layoutCacheIdentity => _layout;

  /// Opaque diagnostic identities; read only from resize regressions, never
  /// from the playback sampling or painting path.
  @visibleForTesting
  List<Object> get cachedShapingIdentities => List<Object>.unmodifiable([
        if (_layout.base != null) _layout.base!,
        if (_layout.highlight != null) _layout.highlight!,
        if (_layout.stroke != null) _layout.stroke!,
        for (final glyph in _layout.glyphs) ...[
          glyph.base,
          glyph.highlight,
          if (glyph.stroke != null) glyph.stroke!,
        ],
      ]);
  @visibleForTesting
  int get cachedStrokePainterCount => _layout.vertical
      ? _layout.glyphs.where((glyph) => glyph.stroke != null).length
      : (_layout.stroke == null ? 0 : 1);
  @visibleForTesting
  List<int> get wordSourceStarts => _layout.shaping.wordSourceStarts;
  @visibleForTesting
  int debugPrefixScanSteps = 0;
  @visibleForTesting
  List<LyricGlyphCell> get presentedGlyphCells =>
      List.unmodifiable(_glyphMotions[0]?.cells ?? const <LyricGlyphCell>[]);
  List<DesktopLyricGlyph> get glyphs =>
      List.unmodifiable(_layout.glyphs.map((glyph) => glyph.glyph));

  double progressForWord(int index) {
    final word = _layout.words[index];
    final elapsed = clock.positionMilliseconds - word.startMilliseconds;
    return word.lengthMilliseconds <= 0
        ? (elapsed >= 0 ? 1 : 0)
        : (elapsed / word.lengthMilliseconds).clamp(0.0, 1.0);
  }

  List<Rect> highlightRectsForWord(int index) {
    final boxes = _layout.wordBoxes[index];
    var remaining = _layout.wordExtents[index] * progressForWord(index);
    final result = <Rect>[];
    for (final box in boxes) {
      if (remaining <= 0) break;
      final fillVertically = vertical && !box.horizontal;
      final amount = math.min(
          remaining, fillVertically ? box.rect.height : box.rect.width);
      remaining -= amount;
      result.add(fillVertically
          ? Rect.fromLTRB(box.rect.left, box.rect.top, box.rect.right,
              box.rect.top + amount)
          : box.rtl
              ? Rect.fromLTRB(box.rect.right - amount, box.rect.top,
                  box.rect.right, box.rect.bottom)
              : Rect.fromLTRB(box.rect.left, box.rect.top,
                  box.rect.left + amount, box.rect.bottom));
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintSize = size;
    final previous = _previousLayout;
    if (previous == null || _layoutProgress >= 1 || _glyphMotions.isNotEmpty) {
      _paintLayout(canvas);
      return;
    }
    void endpoint(_DesktopLyricTextLayout layout, double opacity) {
      if (opacity <= 0) return;
      canvas.save();
      canvas.translate((size.width - layout.size.width) / 2, 0);
      canvas.saveLayer(Offset.zero & layout.size,
          Paint()..color = Colors.white.withValues(alpha: opacity));
      DesktopLyricTextPainter._(
              layout: layout, clock: clock, reducedMotion: reducedMotion)
          ._paintLayout(canvas);
      canvas.restore();
      canvas.restore();
    }

    endpoint(previous, 1 - _layoutProgress);
    endpoint(_layout, _layoutProgress);
  }

  void _paintLayout(Canvas canvas) {
    final ruby = _layout.ruby;
    if (ruby == null) {
      _paintPrimaryLayout(canvas);
      return;
    }
    canvas.save();
    if (!vertical) canvas.translate(0, ruby.extent * rubyVisibility);
    if (vertical) {
      _paintPrimaryLayout(canvas);
    } else {
      ruby.paintPrimary(canvas, () => _paintPrimaryLayout(canvas),
          visibility: rubyVisibility);
    }
    ruby.paint(canvas,
        visibility: rubyVisibility,
        displacement: !vertical && _glyphMotions[0] != null
            ? (glyph) {
                final motion = _glyphMotions[0]!;
                final presented = motion.bounds(
                    glyph.span.start, glyph.span.end, _layoutProgress);
                if (presented == null) return Offset.zero;
                final center = (_paintSize.width - motion.sourceSize.width) / 2;
                return Offset(
                    presented.center.dx + center - glyph.source.center.dx,
                    presented.top - glyph.source.top);
              }
            : null);
    canvas.restore();
  }

  void _paintPrimaryLayout(Canvas canvas) {
    _paintGlyphs(canvas, played: false, stroke: true);
    if (_layout.words.isEmpty || reducedMotion) {
      _paintGlyphs(canvas, played: true);
      return;
    }
    _paintGlyphs(canvas, played: false);
    final completed = Path();
    var hasCompleted = false;
    final active = <({
      Rect bounds,
      int word,
      double progress,
      double offset,
      bool reverse,
      bool vertical,
    })>[];
    for (var index = 0; index < _layout.words.length; index++) {
      final progress = progressForWord(index);
      if (progress <= 0) continue;
      final targetExtent = _layout.wordExtents[index];
      final presented = _presentedWordBoxes(index);
      // A word leaving the bounded paragraph keeps its current playback tint
      // while its old glyphs fade out; an empty target must not erase it early.
      final extent = targetExtent > 0
          ? targetExtent
          : presented.fold<double>(0, (sum, box) => sum + box.rect.width);
      if (extent <= 0) continue;
      final edges = LyricWordEffects.revealEdges(
          progress: progress,
          extent: extent,
          softness: _layout.wordSoftness[index]);
      var offset = 0.0;
      for (final box in presented) {
        final vertical = _layout.vertical && !box.horizontal;
        final end = offset + (vertical ? box.rect.height : box.rect.width);
        if (progress >= 1 || edges.start >= end) {
          completed.addRect(box.rect);
          hasCompleted = true;
        } else if (edges.end > offset && !box.rect.isEmpty) {
          active.add((
            bounds: box.rect,
            word: index,
            progress: progress,
            offset: offset,
            reverse: box.rtl,
            vertical: vertical,
          ));
        }
        offset = end;
      }
    }
    if (hasCompleted) {
      canvas.save();
      canvas.clipPath(completed);
      _paintGlyphs(canvas, played: true);
      canvas.restore();
    }
    // Only unfinished word fragments need an alpha mask. Completed text is
    // one cached pass; the outline remains a single untouched pass beneath.
    // Bounds stay local to each shaped fragment, including vertical foreign
    // words and RTL runs, rather than allocating a window-sized layer.
    for (final fragment in active) {
      canvas.save();
      canvas.clipRect(fragment.bounds);
      canvas.saveLayer(fragment.bounds, Paint());
      _paintGlyphs(canvas, played: true);
      canvas.drawRect(
          fragment.bounds,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = LyricWordEffects.revealShader(
                bounds: fragment.bounds,
                progress: fragment.progress,
                extent: _layout.wordExtents[fragment.word],
                offset: fragment.offset,
                softness: _layout.wordSoftness[fragment.word],
                reverse: fragment.reverse,
                vertical: fragment.vertical));
      canvas.restore();
      canvas.restore();
    }
  }

  List<({Rect rect, bool rtl, bool horizontal})> _presentedWordBoxes(
      int index) {
    final morph = _glyphMotions[0];
    if (vertical || morph == null) return _layout.wordBoxes[index];
    final start = _layout.shaping.wordSourceStarts[index];
    final shift = Offset((_paintSize.width - morph.sourceSize.width) / 2, 0);
    return [
      for (final box in morph.boxes(
          start, start + _layout.words[index].content.length, _layoutProgress))
        (
          rect: box.shift(shift),
          rtl: _layout.wordBoxes[index].firstOrNull?.rtl ??
              _previousLayout?.wordBoxes[index].firstOrNull?.rtl ??
              false,
          horizontal: true
        )
    ];
  }

  void _paintGlyphs(Canvas canvas,
      {required bool played, bool stroke = false}) {
    final motions = stroke ? _strokeMotions : _glyphMotions;
    if (motions.isEmpty) {
      if (stroke) {
        _layout.paintStroke(canvas);
      } else {
        _layout.paint(canvas, played: played);
      }
      return;
    }
    final tint = stroke
        ? null
        : played
            ? _layout.shaping.playedColor
            : _layout.shaping.unplayedColor;
    if (!vertical) {
      final morph = motions[0]!;
      canvas.save();
      canvas.translate((_paintSize.width - morph.sourceSize.width) / 2, 0);
      morph.paint(canvas,
          progress: _layoutProgress,
          tint: tint,
          colourParagraph: (_previousLayout ?? _layout).base,
          colourLayoutIdentity: _previousLayout ?? _layout,
          colourPaint: stroke
              ? null
              : (source) =>
                  (_previousLayout ?? _layout).paint(source, played: played));
      canvas.restore();
      return;
    }
    for (final (index, glyph) in _layout.glyphs.indexed) {
      canvas.save();
      canvas.translate(glyph.paintOffset.dx, glyph.paintOffset.dy);
      canvas.scale(glyph.scale, glyph.scale);
      final morph = motions[index];
      if (morph != null) {
        morph.paint(canvas,
            progress: _layoutProgress,
            tint: tint,
            colourParagraph: glyph.base,
            colourLayoutIdentity: glyph.base,
            colourPaint: stroke
                ? null
                : (source) => (played ? glyph.highlight : glyph.base)
                    .paint(source, Offset.zero));
      } else {
        (stroke
                ? glyph.stroke
                : played
                    ? glyph.highlight
                    : glyph.base)
            ?.paint(canvas, Offset.zero);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(DesktopLyricTextPainter oldDelegate) =>
      !identical(_layout, oldDelegate._layout) ||
      !identical(_previousLayout, oldDelegate._previousLayout) ||
      _layoutProgress != oldDelegate._layoutProgress ||
      !identical(clock, oldDelegate.clock) ||
      reducedMotion != oldDelegate.reducedMotion ||
      rubyVisibility != oldDelegate.rubyVisibility;
}
