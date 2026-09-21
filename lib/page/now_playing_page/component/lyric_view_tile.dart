import 'dart:ui' as drawing;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_text_balance.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:desktop_lyric/lyric_word_effects.dart';

class LyricViewTile extends StatelessWidget {
  const LyricViewTile({
    super.key,
    required this.line,
    required this.position,
    required this.opacity,
    required this.reducedMotion,
    this.distance = 1,
    this.onTap,
  });

  final LyricLine line;
  final ValueListenable<Duration> position;
  final double opacity;
  final int distance;
  final bool reducedMotion;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final controller = context.watch<LyricViewController>();
    final scheme = Theme.of(context).colorScheme;
    final isMainLine = distance == 0;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final glowAllowed =
        !highContrast && RenderingPreferencesScope.of(context).surfaceBlur;
    final alignment = switch (controller.lyricTextAlign) {
      LyricTextAlign.left => Alignment.centerLeft,
      LyricTextAlign.center => Alignment.center,
      LyricTextAlign.right => Alignment.centerRight,
    };
    final textAlign = switch (controller.lyricTextAlign) {
      LyricTextAlign.left => TextAlign.left,
      LyricTextAlign.center => TextAlign.center,
      LyricTextAlign.right => TextAlign.right,
    };
    final crossAxisAlignment = switch (controller.lyricTextAlign) {
      LyricTextAlign.left => CrossAxisAlignment.start,
      LyricTextAlign.center => CrossAxisAlignment.center,
      LyricTextAlign.right => CrossAxisAlignment.end,
    };
    final syncLine = line is SyncLyricLine ? line as SyncLyricLine : null;
    final text = syncLine?.content ??
        (line is UnsyncLyricLine ? (line as UnsyncLyricLine).content : '');
    final parts = text.split('┃');
    final translations = <String>[
      ...(syncLine == null
          ? parts.skip(1).where((text) => text.trim().isNotEmpty).toList()
          : [
              if (syncLine.translation?.trim().isNotEmpty ?? false)
                syncLine.translation!,
            ]),
      if (line.romanization?.trim().isNotEmpty ?? false) line.romanization!,
    ];
    final blank = text.trim().isEmpty;
    final duration = switch (line) {
      LrcLine value => value.length,
      SyncLyricLine value => value.length,
      _ => Duration.zero,
    };
    final primaryStyle = DefaultTextStyle.of(context).style.copyWith(
          // Reserve the focused paragraph once. Context rows use a paint-only
          // scale, so increasing emphasis never changes line breaks mid-tween.
          fontSize: controller.lyricFontSize * LyricMotion.focusedFontScale,
          fontWeight: LyricMotion.focusedFontWeight,
          height: 1.3,
        );
    final label = blank
        ? ui("间奏")
        : [syncLine == null ? parts.first : text, ...translations].join('\n');

    // The hit region and semantics remain outside the smaller context-row
    // transform. Even a blank/distant line keeps its complete 48px touch area.
    return Semantics(
      label: label,
      selected: isMainLine,
      button: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: InkWell(
            // Context deblur is the hover feedback. Tinting beneath fractional
            // glyph edges can change perceived ink bounds by a physical pixel.
            hoverColor: Colors.transparent,
            onTap: onTap,
            borderRadius: AppShape.controlRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: LyricLineMotion(
                opacity: highContrast ? 1 : opacity,
                scale:
                    reducedMotion ? 1 : LyricMotion.scaleForDistance(distance),
                activation: isMainLine ? 1 : 0,
                alignment: alignment,
                reducedMotion: reducedMotion,
                builder: (context, activation) {
                  final foreground = scheme.onSecondaryContainer;
                  final primaryColor = Color.lerp(
                    foreground,
                    scheme.primary,
                    activation,
                  )!;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Align(
                      alignment: alignment,
                      child: blank
                          ? SizedBox(
                              height: 24,
                              child: duration > const Duration(seconds: 5)
                                  ? Opacity(
                                      opacity: activation,
                                      child: LyricTransitionTile(
                                        line: line,
                                        length: duration,
                                        position: position,
                                        active: isMainLine,
                                        reducedMotion: reducedMotion,
                                      ),
                                    )
                                  : null,
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: crossAxisAlignment,
                              children: [
                                if (syncLine != null)
                                  _TimedLyricText(
                                    line: syncLine,
                                    position: position,
                                    active: isMainLine,
                                    activation: activation,
                                    reducedMotion: reducedMotion,
                                    style: primaryStyle,
                                    textAlign: textAlign,
                                    baseColor: foreground,
                                    playedColor: primaryColor,
                                    glowAllowed: glowAllowed,
                                  )
                                else
                                  // LRC has line times only. A uniform focus
                                  // transition does not invent word timing.
                                  BalancedLyricText(
                                    parts.first,
                                    textAlign: textAlign,
                                    style: primaryStyle.copyWith(
                                      color: primaryColor,
                                    ),
                                  ),
                                for (final translation in translations)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      translation,
                                      textAlign: textAlign,
                                      style: TextStyle(
                                        color: foreground.withValues(
                                          alpha: highContrast
                                              ? 1
                                              : .78 + .12 * activation,
                                        ),
                                        fontSize:
                                            controller.translationFontSize,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Both inactive and active timed lines use this exact paragraph layout.
/// Highlighting is painted over the original shaping, so a word changing color
/// cannot replace Text with WidgetSpan or move a long/translated line.
class _TimedLyricText extends StatefulWidget {
  const _TimedLyricText({
    required this.line,
    required this.position,
    required this.active,
    required this.activation,
    required this.reducedMotion,
    required this.style,
    required this.textAlign,
    required this.baseColor,
    required this.playedColor,
    required this.glowAllowed,
  });

  final SyncLyricLine line;
  final ValueListenable<Duration> position;
  final bool active;
  final double activation;
  final bool reducedMotion;
  final TextStyle style;
  final TextAlign textAlign;
  final Color baseColor;
  final Color playedColor;
  final bool glowAllowed;

  @override
  State<_TimedLyricText> createState() => _TimedLyricTextState();
}

class _TimedLyricTextState extends State<_TimedLyricText> {
  Object? _layoutIdentity;
  _TimedLyricLayout? _layout;

  @override
  void didUpdateWidget(_TimedLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activation <= 0 || widget.reducedMotion || !widget.glowAllowed) {
      _layout?.releaseGlowMasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final identity = (
          widget.line,
          widget.line.content,
          widget.style,
          widget.textAlign,
          direction,
          scaler,
          pixelRatio,
          width,
        );
        if (_layoutIdentity != identity) {
          _layout?.dispose();
          _layout = _TimedLyricLayout(
            line: widget.line,
            style: widget.style,
            textAlign: widget.textAlign,
            direction: direction,
            scaler: scaler,
            pixelRatio: pixelRatio,
            maxWidth: width,
          );
          _layoutIdentity = identity;
        }
        final layout = _layout!;
        return SizedBox(
          width: layout.base.width,
          height: layout.base.height,
          child: CustomPaint(
            painter: LyricWordHighlightPainter._(
              layout: layout,
              line: widget.line,
              position: widget.position,
              active: widget.active,
              activation: widget.activation,
              reducedMotion: widget.reducedMotion,
              baseColor: widget.baseColor,
              playedColor: widget.playedColor,
              glowAllowed: widget.glowAllowed,
            ),
            isComplex: true,
            willChange: widget.active && !widget.reducedMotion,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _layout?.dispose();
    super.dispose();
  }
}

class _TimedLyricLayout {
  _TimedLyricLayout({
    required this.line,
    required this.style,
    required TextAlign textAlign,
    required TextDirection direction,
    required TextScaler scaler,
    required this.pixelRatio,
    required this.maxWidth,
  })  : base = TextPainter(
          textDirection: direction,
          textAlign: textAlign,
          textScaler: scaler,
        ),
        fontSize = scaler.scale(style.fontSize ?? 14) {
    // White shapes are recorded once; theme/focus colors are paint operations.
    // Sampling playback never rebuilds paragraphs or changes line breaks.
    base.text = TextSpan(
        text: line.content, style: style.copyWith(color: Colors.white));
    layoutBalancedLyric(base, maxWidth);
    final recorder = drawing.PictureRecorder();
    base.paint(Canvas(recorder), Offset.zero);
    glyphs = recorder.endRecording();

    // Timing providers sometimes split a surrogate/ZWJ cluster into separate
    // words. Keep that grapheme in one mask with its actual combined interval.
    final boundaries = <int>{0};
    var boundary = 0;
    for (final character in line.content.characters) {
      boundary += character.length;
      boundaries.add(boundary);
    }
    var offset = 0;
    words = [];
    for (var index = 0; index < line.words.length; index++) {
      final startOffset = offset;
      var start = line.words[index].start;
      var end = start + line.words[index].length;
      offset += line.words[index].content.length;
      while (!boundaries.contains(offset) && index + 1 < line.words.length) {
        final next = line.words[++index];
        if (next.start < start) start = next.start;
        if (next.start + next.length > end) end = next.start + next.length;
        offset += next.content.length;
      }
      final boxes = base.getBoxesForSelection(
          TextSelection(baseOffset: startOffset, extentOffset: offset),
          boxHeightStyle: drawing.BoxHeightStyle.includeLineSpacingMiddle);
      if (boxes.isEmpty) continue;
      final text = line.content.substring(startOffset, offset);
      final characters = text.characters.toList(growable: false);
      // CJK graphemes have independent glyphs. Keep Latin ligatures, joining
      // scripts and emoji clusters intact. Splitting is visual only: every
      // slice retains the provider word's original time and reveal distance.
      if (characters.length > 1 &&
          characters.length <= 24 &&
          _independentCharacters.hasMatch(text)) {
        final extent =
            boxes.fold<double>(0, (sum, box) => sum + box.right - box.left);
        var characterOffset = startOffset;
        var revealOffset = 0.0;
        for (var c = 0; c < characters.length; c++) {
          final nextOffset = characterOffset + characters[c].length;
          final pieces = base.getBoxesForSelection(
              TextSelection(
                  baseOffset: characterOffset, extentOffset: nextOffset),
              boxHeightStyle: drawing.BoxHeightStyle.includeLineSpacingMiddle);
          if (pieces.isNotEmpty) {
            words.add(_TimedWordShape(
                start: start,
                length: end - start,
                boxes: pieces,
                group: index,
                phase: .28 * c / characters.length,
                revealExtent: extent,
                revealOffset: revealOffset,
                canLift: pieces.length == 1 &&
                    characters[c].trim().isNotEmpty &&
                    pieces.single.direction == TextDirection.ltr));
            revealOffset += pieces.fold<double>(
                0, (sum, box) => sum + box.right - box.left);
          }
          characterOffset = nextOffset;
        }
        continue;
      }
      // A transformed slice must never separate a joining script or ligature
      // from its neighbours. Such words still receive the full soft reveal.
      bool joinsAt(int position) =>
          position > 0 &&
          position < line.content.length &&
          _joiningLetter
              .hasMatch(line.content.substring(position - 1, position + 1));
      words.add(_TimedWordShape(
        start: start,
        length: end - start,
        boxes: boxes,
        group: index,
        canLift: boxes.length == 1 &&
            text.trim().isNotEmpty &&
            boxes.single.direction == TextDirection.ltr &&
            !joinsAt(startOffset) &&
            !joinsAt(offset) &&
            !_joiningScript.hasMatch(text),
      ));
    }
    // Reserve four non-overlapping presentation lanes once per layout.
    // A fifth overlapping note keeps its reveal, but must neither suppress
    // all motion in the paragraph nor interrupt the four existing poses.
    final ordered = [for (var i = 0; i < words.length; i++) i]..sort((a, b) {
        final order = words[a].start.compareTo(words[b].start);
        return order == 0 ? a.compareTo(b) : order;
      });
    final laneEnds = List<Duration?>.filled(4, null);
    final reservedGroups = <int>{};
    movingIndices = <int>{};
    for (final index in ordered) {
      final word = words[index];
      if (!word.canLift || word.length <= Duration.zero) continue;
      if (reservedGroups.contains(word.group)) {
        movingIndices.add(index);
        continue;
      }
      final lane =
          laneEnds.indexWhere((end) => end == null || end <= word.start);
      if (lane < 0) continue;
      movingIndices.add(index);
      reservedGroups.add(word.group);
      laneEnds[lane] = word.start + word.length;
    }
  }

  final SyncLyricLine line;
  final TextStyle style;
  final double maxWidth;
  final double pixelRatio;
  final TextPainter base;
  final double fontSize;
  late final drawing.Picture glyphs;
  late final List<_TimedWordShape> words;
  late final Set<int> movingIndices;
  static final _joiningLetter = RegExp(r'^[A-Za-z\u00c0-\u024f]{2}$');
  static final _joiningScript = RegExp(r'[\u0590-\u109f]');
  static final _independentCharacters =
      RegExp(r'^[\u2e80-\u9fff\uac00-\ud7af\s]+$');

  // Long-note glow is a static white mask: only its transform/tint changes.
  // Rasterize the tiny diffuse mask once instead of running a Gaussian pass
  // every display frame. Bound both count and total pixels; release on exit.
  final _glowMasks = <int, (drawing.Image, Rect)>{};
  int _glowPixels = 0;
  (drawing.Image, Rect)? glowMask(int index) {
    final cached = _glowMasks.remove(index);
    if (cached != null) {
      _glowMasks[index] = cached;
      return cached;
    }
    final word = words[index];
    final bounds = word.bounds.inflate(4);
    final ratio = (pixelRatio * 1.3).clamp(1.0, 5.0);
    final width = (bounds.width * ratio).ceil();
    final height = (bounds.height * ratio).ceil();
    if (width <= 0 || height <= 0 || width * height > 1024 * 1024) return null;
    final recorder = drawing.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..translate(-bounds.left, -bounds.top);
    canvas.saveLayer(
        bounds,
        Paint()
          ..imageFilter = drawing.ImageFilter.blur(sigmaX: 1.1, sigmaY: 1.1));
    canvas.clipRect(word.bounds, doAntiAlias: false);
    canvas.drawPicture(glyphs);
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    while (_glowMasks.isNotEmpty &&
        (_glowMasks.length >= 96 ||
            _glowPixels + width * height > 4 * 1024 * 1024)) {
      final old = _glowMasks.remove(_glowMasks.keys.first)!.$1;
      _glowPixels -= old.width * old.height;
      old.dispose();
    }
    final mask = (
      image,
      Rect.fromLTWH(bounds.left, bounds.top, width / ratio, height / ratio)
    );
    _glowMasks[index] = mask;
    _glowPixels += width * height;
    return mask;
  }

  void releaseGlowMasks() {
    for (final mask in _glowMasks.values) {
      mask.$1.dispose();
    }
    _glowMasks.clear();
    _glowPixels = 0;
  }

  void dispose() {
    releaseGlowMasks();
    base.dispose();
    glyphs.dispose();
  }
}

class _TimedWordShape {
  _TimedWordShape(
      {required this.start,
      required this.length,
      required this.boxes,
      required this.group,
      this.phase = 0,
      double? revealExtent,
      this.revealOffset = 0,
      required this.canLift})
      : extent = revealExtent ??
            boxes.fold<double>(0, (sum, box) => sum + box.right - box.left),
        bounds = boxes
            .map((box) => box.toRect())
            .reduce((a, b) => a.expandToInclude(b));
  final Duration start;
  final Duration length;
  final int group;
  final double phase;
  final double revealOffset;
  final List<TextBox> boxes;
  final bool canLift;
  final double extent;
  final Rect bounds;
}

/// Paints only the actual timed words; updates repaint the active paragraph,
/// rather than rebuilding every lyric row at the 33ms playback sampling rate.
class LyricWordHighlightPainter extends CustomPainter {
  LyricWordHighlightPainter._({
    required _TimedLyricLayout layout,
    required this.line,
    required ValueListenable<Duration> position,
    required this.active,
    required this.activation,
    required this.reducedMotion,
    required this.baseColor,
    required this.playedColor,
    required this.glowAllowed,
  })  : _layout = layout,
        _position = position,
        super(repaint: active && !reducedMotion ? position : null);

  final _TimedLyricLayout _layout;
  final ValueListenable<Duration> _position;
  final SyncLyricLine line;
  final bool active;
  final double activation;
  final bool reducedMotion;
  final Color baseColor;
  final Color playedColor;
  final bool glowAllowed;

  Duration get position => _position.value;

  double progressForWord(int index) {
    final word = line.words[index];
    return LyricMotion.progress(position, word.start, word.length);
  }

  @visibleForTesting
  Object get layoutIdentity => _layout;

  @visibleForTesting
  int get shapedWordCount => _layout.words.length;

  @visibleForTesting
  int get movingWordCount => _movingWords().length;

  @visibleForTesting
  List<double> get movingWordLifts =>
      [for (final pose in _movingWords()) pose.lift];

  List<({int index, double lift, double scale, double scaleY, double anchorX})>
      _movingWords() {
    if (reducedMotion || activation <= 0) {
      return const [];
    }
    final result = <({
      int index,
      double lift,
      double scale,
      double scaleY,
      double anchorX
    })>[];
    for (var index = 0; index < _layout.words.length; index++) {
      final word = _layout.words[index];
      if (!_layout.movingIndices.contains(index)) continue;
      final progress = LyricMotion.progress(position, word.start, word.length);
      final pose = LyricWordEffects.sustain(
          progress: ((progress - word.phase) / (1 - word.phase)).clamp(0, 1),
          durationMilliseconds: word.length.inMilliseconds,
          fontSize: _layout.fontSize);
      if (pose.lift <= .001) continue;
      // Edge words grow away from their neighbour. Inner words stretch only
      // vertically: they remain expressive without crossing adjacent glyphs.
      final first = index == 0;
      final last = index == _layout.words.length - 1;
      final expansion = first || last
          ? (pose.scale - 1).clamp(0, 10 / word.bounds.width)
          : 0.0;
      result.add((
        index: index,
        lift: pose.lift * activation,
        scale: 1 + expansion * activation,
        scaleY: 1 + (pose.scale - 1) * activation,
        anchorX: first && !last
            ? word.bounds.right
            : last && !first
                ? word.bounds.left
                : word.bounds.center.dx,
      ));
    }
    return result;
  }

  void _paintWordColor(Canvas canvas, _TimedWordShape word,
      {BlendMode blendMode = BlendMode.srcATop}) {
    final progress = LyricMotion.progress(position, word.start, word.length);
    if (progress <= 0 && blendMode == BlendMode.srcATop) return;
    final paint = Paint()..blendMode = blendMode;
    var offset = word.revealOffset;
    final softness = LyricWordEffects.softEdgeWidth(
        fontSize: _layout.fontSize, extent: word.extent);
    for (final box in word.boxes) {
      final rect = box.toRect();
      if (progress <= 0 || progress >= 1) {
        paint.shader = null;
        paint.color = progress >= 1 ? playedColor : baseColor;
      } else {
        paint.shader = LyricWordEffects.revealShader(
            bounds: rect,
            progress: progress,
            extent: word.extent,
            offset: offset,
            softness: softness,
            reverse: box.direction == TextDirection.rtl,
            leading: playedColor,
            trailing: baseColor);
      }
      canvas.drawRect(rect, paint);
      offset += rect.width;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final moving = _movingWords();
    for (final pose in moving) {
      final word = _layout.words[pose.index];
      canvas.save();
      canvas.translate(pose.anchorX, word.bounds.center.dy - pose.lift);
      canvas.scale(pose.scale, pose.scaleY);
      canvas.translate(-pose.anchorX, -word.bounds.center.dy);
      if (glowAllowed &&
          pose.scaleY > 1.00001 &&
          word.length.inMilliseconds > 650) {
        // One small diffuse mask per active long word, never the whole line.
        final intensity =
            ((pose.scaleY - 1) / LyricWordEffects.maximumScaleExpansion)
                .clamp(0.0, 1.0);
        final mask = _layout.glowMask(pose.index);
        if (mask != null) {
          canvas.drawImageRect(
              mask.$1,
              Rect.fromLTWH(
                  0, 0, mask.$1.width.toDouble(), mask.$1.height.toDouble()),
              mask.$2,
              Paint()
                ..filterQuality = FilterQuality.low
                ..colorFilter = ColorFilter.mode(
                    playedColor.withValues(alpha: .18 * intensity),
                    BlendMode.srcIn));
        }
      }
      canvas.restore();
    }
    // Compose all white glyph slices first, then tint them in one paragraph
    // layer. A separate offscreen surface per character scales poorly and is
    // unnecessary because the glyph geometry already supplies the alpha mask.
    final paintBounds = bounds.inflate(12);
    canvas.saveLayer(paintBounds, Paint());
    canvas.save();
    for (final pose in moving) {
      canvas.clipRect(_layout.words[pose.index].bounds,
          clipOp: drawing.ClipOp.difference, doAntiAlias: false);
    }
    canvas.drawPicture(_layout.glyphs);
    canvas.restore();
    for (final pose in moving) {
      final word = _layout.words[pose.index];
      canvas.save();
      canvas.translate(pose.anchorX, word.bounds.center.dy - pose.lift);
      canvas.scale(pose.scale, pose.scaleY);
      canvas.translate(-pose.anchorX, -word.bounds.center.dy);
      canvas.clipRect(word.bounds, doAntiAlias: false);
      canvas.drawPicture(_layout.glyphs);
      canvas.restore();
    }
    canvas.drawRect(
        paintBounds,
        Paint()
          ..blendMode = BlendMode.srcIn
          ..color = reducedMotion && activation > 0 ? playedColor : baseColor);
    if (activation > 0 && !reducedMotion) {
      final poses = {for (final pose in moving) pose.index: pose};
      for (var index = 0; index < _layout.words.length; index++) {
        final word = _layout.words[index];
        final pose = poses[index];
        canvas.save();
        if (pose != null) {
          canvas.translate(pose.anchorX, word.bounds.center.dy - pose.lift);
          canvas.scale(pose.scale, pose.scaleY);
          canvas.translate(-pose.anchorX, -word.bounds.center.dy);
        }
        _paintWordColor(canvas, word);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LyricWordHighlightPainter oldDelegate) =>
      !identical(_layout, oldDelegate._layout) ||
      !identical(_position, oldDelegate._position) ||
      active != oldDelegate.active ||
      activation != oldDelegate.activation ||
      reducedMotion != oldDelegate.reducedMotion ||
      baseColor != oldDelegate.baseColor ||
      playedColor != oldDelegate.playedColor ||
      glowAllowed != oldDelegate.glowAllowed;
}

/// The interlude occupies the same space before, during and after activation.
/// Its subtle breathing is derived from playback time, not a free-running
/// ticker, so pause/seek and reduced motion cannot leave an orphaned animation.
class LyricTransitionTile extends StatelessWidget {
  const LyricTransitionTile({
    super.key,
    required this.line,
    required this.length,
    required this.position,
    required this.active,
    required this.reducedMotion,
  });

  final LyricLine line;
  final Duration length;
  final ValueListenable<Duration> position;
  final bool active;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return CustomPaint(
      size: const Size(72, 24),
      painter: _LyricInterludePainter(
        start: line.start,
        length: length,
        position: position,
        active: active,
        reducedMotion: reducedMotion,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }
}

class _LyricInterludePainter extends CustomPainter {
  _LyricInterludePainter({
    required this.start,
    required this.length,
    required this.position,
    required this.active,
    required this.reducedMotion,
    required this.color,
  }) : super(repaint: active && !reducedMotion ? position : null);

  final Duration start;
  final Duration length;
  final ValueListenable<Duration> position;
  final bool active;
  final bool reducedMotion;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = LyricMotion.interludePose(position.value - start, length,
        reduced: reducedMotion);
    final paint = Paint();
    canvas.save();
    canvas.translate(36, 12);
    canvas.scale(pose.scale);
    canvas.translate(-36, -12);
    for (var index = 0; index < 3; index++) {
      final amount = (pose.progress * 3 - index).clamp(0.0, 1.0);
      final eased = amount * amount * (3 - 2 * amount);
      paint.color = color.withValues(alpha: pose.opacity * (.28 + .72 * eased));
      canvas.drawCircle(Offset(12 + 24.0 * index, 12), 4.2, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LyricInterludePainter oldDelegate) =>
      start != oldDelegate.start ||
      length != oldDelegate.length ||
      !identical(position, oldDelegate.position) ||
      active != oldDelegate.active ||
      reducedMotion != oldDelegate.reducedMotion ||
      color != oldDelegate.color;
}
