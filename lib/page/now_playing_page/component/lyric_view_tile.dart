import 'dart:math' as math;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';

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
    final translations = syncLine == null
        ? parts.skip(1).where((text) => text.trim().isNotEmpty).toList()
        : [
            if (syncLine.translation?.trim().isNotEmpty ?? false)
              syncLine.translation!,
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
                                  )
                                else
                                  // LRC has line times only. A uniform focus
                                  // transition does not invent word timing.
                                  Text(
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

  @override
  State<_TimedLyricText> createState() => _TimedLyricTextState();
}

class _TimedLyricTextState extends State<_TimedLyricText> {
  Object? _layoutIdentity;
  _TimedLyricLayout? _layout;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = Directionality.of(context);
        final scaler = MediaQuery.textScalerOf(context);
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
            maxWidth: width,
          );
          _layoutIdentity = identity;
        }
        final layout = _layout!;
        layout.setColors(widget.baseColor, widget.playedColor);
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
    required this.maxWidth,
  })  : base = TextPainter(
          textDirection: direction,
          textAlign: textAlign,
          textScaler: scaler,
        ),
        highlight = TextPainter(
          textDirection: direction,
          textAlign: textAlign,
          textScaler: scaler,
        ) {
    setColors(Colors.white, Colors.white);
    var offset = 0;
    wordBoxes = [
      for (final word in line.words)
        base.getBoxesForSelection(TextSelection(
          baseOffset: offset,
          extentOffset: offset += word.content.length,
        )),
    ];
  }

  final SyncLyricLine line;
  final TextStyle style;
  final double maxWidth;
  final TextPainter base;
  final TextPainter highlight;
  late final List<List<TextBox>> wordBoxes;
  Color? _baseColor;
  Color? _playedColor;

  void setColors(Color baseColor, Color playedColor) {
    if (_baseColor != baseColor) {
      base.text = TextSpan(
        text: line.content,
        style: style.copyWith(color: baseColor),
      );
      base.layout(maxWidth: maxWidth);
      _baseColor = baseColor;
    }
    if (_playedColor != playedColor) {
      highlight.text = TextSpan(
        text: line.content,
        style: style.copyWith(color: playedColor),
      );
      highlight.layout(maxWidth: maxWidth);
      _playedColor = playedColor;
    }
  }

  void dispose() {
    base.dispose();
    highlight.dispose();
  }
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

  Duration get position => _position.value;

  double progressForWord(int index) {
    final word = line.words[index];
    return LyricMotion.progress(position, word.start, word.length);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _layout.base.paint(canvas, Offset.zero);
    if (activation <= 0) return;
    if (reducedMotion) {
      _layout.highlight.paint(canvas, Offset.zero);
      return;
    }
    final clips = Path();
    var hasHighlight = false;
    for (var index = 0; index < line.words.length; index++) {
      final progress = progressForWord(index);
      if (progress <= 0) continue;
      final boxes = _layout.wordBoxes[index];
      final width =
          boxes.fold<double>(0, (sum, box) => sum + box.right - box.left);
      var remaining = width * progress;
      for (final box in boxes) {
        if (remaining <= 0) break;
        final filled = math.min(remaining, box.right - box.left);
        if (filled > 0) {
          clips.addRect(box.direction == TextDirection.rtl
              ? Rect.fromLTRB(
                  box.right - filled, box.top, box.right, box.bottom)
              : Rect.fromLTRB(
                  box.left, box.top, box.left + filled, box.bottom));
          hasHighlight = true;
        }
        remaining -= filled;
      }
    }
    if (!hasHighlight) return;
    canvas.save();
    canvas.clipPath(clips);
    _layout.highlight.paint(canvas, Offset.zero);
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
      playedColor != oldDelegate.playedColor;
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
    final elapsed = math.max(0, (position.value - start).inMilliseconds) / 1000;
    final progress = LyricMotion.progress(position.value, start, length);
    final radius = reducedMotion ? 4.0 : 4 + .45 * math.sin(elapsed * math.pi);
    final paint = Paint();
    for (var index = 0; index < 3; index++) {
      final amount =
          reducedMotion ? 1.0 : (progress * 3 - index).clamp(0.0, 1.0);
      paint.color = color.withValues(alpha: .28 + .72 * amount);
      canvas.drawCircle(Offset(12 + 24.0 * index, 12), radius, paint);
    }
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
