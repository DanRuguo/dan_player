import 'dart:math' as math;

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';

import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/lyric_content_reveal.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricLineDisplayArea extends StatelessWidget {
  const LyricLineDisplayArea({
    super.key,
    this.controller,
    this.lyricSourceGeneration,
  });
  final DesktopLyricController? controller;
  final int? lyricSourceGeneration;

  @override
  Widget build(BuildContext context) {
    final textSettings = context.watch<TextDisplayController>();
    final theme = context.watch<ThemeChangedMessage>();
    final source = controller ?? DesktopLyricController.instance;
    final color = textSettings.hasSpecifiedColor
        ? textSettings.specifiedColor
        : Color(theme.primary);
    return ListenableBuilder(
      // Position updates only repaint cached text/update the existing scroll.
      listenable: Listenable.merge([
        source.detailedLyricLine,
        source.lyricLine,
        source.vertical,
      ]),
      builder: (context, _) => DesktopLyricLineContent(
        detailedLine: source.detailedLyricLine.value,
        lyricSourceGeneration:
            lyricSourceGeneration ??
            source.detailedLyricLine.value?.lyricSourceGeneration,
        legacyLine: source.lyricLine.value,
        clock: source.playbackClock,
        vertical: source.vertical.value,
        color: color,
        lyricFontSize: textSettings.lyricFontSize,
        translationFontSize: textSettings.translationFontSize,
        lyricLetterSpacing: textSettings.lyricLetterSpacing,
        showJapaneseReading: textSettings.value.showJapaneseReading,
        textOpacity: textSettings.value.textOpacity,
        strokeEnabled: textSettings.value.strokeEnabled,
      ),
    );
  }
}

/// The production line renderer, injectable without player/window globals.
class DesktopLyricLineContent extends StatelessWidget {
  const DesktopLyricLineContent({
    super.key,
    required this.detailedLine,
    this.lyricSourceGeneration,
    required this.legacyLine,
    required this.clock,
    required this.vertical,
    required this.color,
    this.lyricFontSize = 22,
    this.translationFontSize = 18,
    this.lyricLetterSpacing = 0,
    this.showJapaneseReading = true,
    this.textOpacity = 1,
    this.strokeEnabled = false,
  });

  final LyricLineTimelineMessage? detailedLine;
  final int? lyricSourceGeneration;
  final LyricLineChangedMessage legacyLine;
  final PlaybackClock clock;
  final bool vertical;
  final Color color;
  final double lyricFontSize;
  final double translationFontSize;
  final double lyricLetterSpacing;
  final bool showJapaneseReading;
  final double textOpacity;
  final bool strokeEnabled;

  @override
  Widget build(BuildContext context) {
    final content = detailedLine?.content ?? legacyLine.content;
    final translation = detailedLine == null
        ? legacyLine.translation
        : detailedLine!.translation;
    final romanization = detailedLine?.romanization;
    final japaneseReading = detailedLine?.japaneseReading;
    final text =
        content.trim().isEmpty &&
            (detailedLine?.lengthMilliseconds ??
                    legacyLine.length.inMilliseconds) >
                5000
        ? '•••'
        : content;
    final Object lineKey = detailedLine == null
        ? ('legacy', legacyLine.content, legacyLine.translation)
        : (detailedLine!.sequence, detailedLine!.lineIndex);
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final reduced =
        !AppMotion.enabled(context, MotionKind.lyrics) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
    final highContrast = MediaQuery.highContrastOf(context);
    final strokeColor = strokeEnabled
        ? (color.computeLuminance() > .45 ? Colors.black : Colors.white)
              .withValues(alpha: highContrast ? 1 : .9)
        : null;
    TextStyle style(double size) => TextStyle(
      fontSize: size,
      height: 1.3,
      fontWeight: FontWeight.w700,
      letterSpacing: lyricLetterSpacing == 0
          ? null
          : (DefaultTextStyle.of(context).style.letterSpacing ?? 0) +
                lyricLetterSpacing,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: .2),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
    final hasTranslation = translation?.trim().isNotEmpty == true;
    final hasRomanization = romanization?.trim().isNotEmpty == true;
    Widget columns(
      LyricContentVisibility visibility, {
      double? verticalColumnWidth,
    }) {
      final readingVisibility = visibility.japaneseReading;
      Widget column(Widget child) => verticalColumnWidth == null
          ? child
          : SizedBox(
              width: verticalColumnWidth,
              child: Align(alignment: Alignment.topCenter, child: child),
            );

      return Flex(
        key: const ValueKey('desktop-lyric-columns'),
        direction: vertical ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: vertical
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (hasRomanization) ...[
            column(
              DesktopLyricText(
                key: const ValueKey('desktop-romanization-lyric'),
                text: romanization!,
                clock: clock,
                vertical: vertical,
                verticalLetterSpacing: lyricLetterSpacing,
                maxVerticalUnitWidth: verticalColumnWidth,
                style: style(translationFontSize),
                playedColor: color.withValues(alpha: highContrast ? 1 : .78),
                unplayedColor: color,
                strokeColor: strokeColor,
                reducedMotion: reduced,
              ),
            ),
            SizedBox(width: vertical ? 16 : 0, height: vertical ? 0 : 4),
          ],
          column(
            DesktopLyricText(
              key: const ValueKey('desktop-primary-lyric'),
              text: text,
              clock: clock,
              vertical: vertical,
              verticalLetterSpacing: lyricLetterSpacing,
              maxVerticalUnitWidth: verticalColumnWidth,
              style: style(lyricFontSize),
              playedColor: color,
              unplayedColor: color.withValues(alpha: highContrast ? .85 : .38),
              strokeColor: strokeColor,
              words: detailedLine?.words ?? const [],
              rubySpans: visibility.japaneseReadingSpans,
              rubyVisibility: readingVisibility,
              reducedMotion: reduced,
            ),
          ),
          if (hasTranslation) ...[
            SizedBox(width: vertical ? 16 : 0, height: vertical ? 0 : 4),
            column(
              DesktopLyricText(
                key: const ValueKey('desktop-translation-lyric'),
                text: translation!,
                clock: clock,
                vertical: vertical,
                verticalLetterSpacing: lyricLetterSpacing,
                maxVerticalUnitWidth: verticalColumnWidth,
                style: style(translationFontSize),
                playedColor: color.withValues(alpha: highContrast ? 1 : .78),
                unplayedColor: color,
                strokeColor: strokeColor,
                reducedMotion: reduced,
              ),
            ),
          ],
        ],
      );
    }

    Widget animatedColumns(Widget child) => _DesktopLineEntrance(
      key: ValueKey(lineKey),
      reducedMotion: reduced,
      vertical: vertical,
      child: child,
    );

    Widget contents(LyricContentVisibility visibility) => vertical
        ? LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final count =
                  1 + (hasTranslation ? 1 : 0) + (hasRomanization ? 1 : 0);
              final gap = (count - 1) * 16.0;
              final columnWidth = math.max(1.0, (availableWidth - gap) / count);
              return animatedColumns(
                columns(visibility, verticalColumnWidth: columnWidth),
              );
            },
          )
        : animatedColumns(columns(visibility));
    final strictSource = detailedLine != null && lyricSourceGeneration != null
        ? (
            detailedLine!.sequence,
            lyricSourceGeneration,
            detailedLine!.lineIndex,
          )
        : null;
    final lyricColumns = LyricContentReveal(
      japaneseReadingSource: strictSource,
      japaneseReadingSpans: detailedLine?.japaneseReadingSpans ?? const [],
      key: ValueKey(('desktop-content', strictSource ?? lineKey)),
      timestamp: false,
      romanization: hasRomanization,
      translation: hasTranslation,
      japaneseReading:
          showJapaneseReading &&
          (detailedLine?.japaneseReadingSpans.isNotEmpty ?? false),
      reducedMotion: reduced,
      builder: (context, visibility) => contents(visibility),
    );
    return Semantics(
      label: [
        if (hasRomanization) romanization!,
        if (showJapaneseReading && japaneseReading?.trim().isNotEmpty == true)
          japaneseReading!,
        text,
        if (hasTranslation) translation!,
      ].join('\n'),
      child: ExcludeSemantics(
        child: Opacity(
          key: const ValueKey('desktop-lyric-text-opacity'),
          opacity: textOpacity,
          child: lyricColumns,
        ),
      ),
    );
  }
}

class _DesktopLineEntrance extends StatefulWidget {
  const _DesktopLineEntrance({
    super.key,
    required this.reducedMotion,
    required this.vertical,
    required this.child,
  });
  final bool reducedMotion;
  final bool vertical;
  final Widget child;

  @override
  State<_DesktopLineEntrance> createState() => _DesktopLineEntranceState();
}

class _DesktopLineEntranceState extends State<_DesktopLineEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: widget.reducedMotion ? 1 : 0,
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.standardCurve,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) _controller.forward();
  }

  @override
  void didUpdateWidget(_DesktopLineEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _animation.value,
      child: Transform.translate(
        offset: widget.vertical
            ? Offset((1 - _animation.value) * 4, 0)
            : Offset(0, (1 - _animation.value) * 4),
        child: child,
      ),
    ),
  );

  @override
  void dispose() {
    (_animation as CurvedAnimation).dispose();
    _controller.dispose();
    super.dispose();
  }
}
