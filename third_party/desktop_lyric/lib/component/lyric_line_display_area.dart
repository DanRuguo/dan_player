import 'dart:math' as math;

import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricLineDisplayArea extends StatelessWidget {
  const LyricLineDisplayArea({super.key, this.controller});
  final DesktopLyricController? controller;

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
        legacyLine: source.lyricLine.value,
        clock: source.playbackClock,
        vertical: source.vertical.value,
        color: color,
        lyricFontSize: textSettings.lyricFontSize,
        translationFontSize: textSettings.translationFontSize,
        textOpacity: textSettings.value.textOpacity,
        strokeEnabled: textSettings.value.strokeEnabled,
      ),
    );
  }
}

/// The production line renderer, injectable without player/window globals.
class DesktopLyricLineContent extends StatelessWidget {
  const DesktopLyricLineContent(
      {super.key,
      required this.detailedLine,
      required this.legacyLine,
      required this.clock,
      required this.vertical,
      required this.color,
      this.lyricFontSize = 22,
      this.translationFontSize = 18,
      this.textOpacity = 1,
      this.strokeEnabled = false});

  final LyricLineTimelineMessage? detailedLine;
  final LyricLineChangedMessage legacyLine;
  final PlaybackClock clock;
  final bool vertical;
  final Color color;
  final double lyricFontSize;
  final double translationFontSize;
  final double textOpacity;
  final bool strokeEnabled;

  @override
  Widget build(BuildContext context) {
    final content = detailedLine?.content ?? legacyLine.content;
    final translation = detailedLine == null
        ? legacyLine.translation
        : detailedLine!.translation;
    final text = content.trim().isEmpty &&
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
    final reduced = MediaQuery.disableAnimationsOf(context) ||
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
          shadows: [
            Shadow(
                color: Colors.black.withValues(alpha: .2),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        );
    final hasTranslation = translation?.trim().isNotEmpty == true;
    Widget columns({double? verticalColumnWidth}) {
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
        crossAxisAlignment:
            vertical ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          column(DesktopLyricText(
            key: const ValueKey('desktop-primary-lyric'),
            text: text,
            clock: clock,
            vertical: vertical,
            maxVerticalUnitWidth: verticalColumnWidth,
            style: style(lyricFontSize),
            playedColor: color,
            unplayedColor: color.withValues(alpha: highContrast ? .85 : .38),
            strokeColor: strokeColor,
            words: detailedLine?.words ?? const [],
            reducedMotion: reduced,
          )),
          if (hasTranslation) ...[
            SizedBox(width: vertical ? 16 : 0, height: vertical ? 0 : 4),
            column(DesktopLyricText(
              key: const ValueKey('desktop-translation-lyric'),
              text: translation!,
              clock: clock,
              vertical: vertical,
              maxVerticalUnitWidth: verticalColumnWidth,
              style: style(translationFontSize),
              playedColor: color.withValues(alpha: highContrast ? 1 : .78),
              unplayedColor: color,
              strokeColor: strokeColor,
              reducedMotion: reduced,
            )),
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

    final lyricColumns = vertical
        ? LayoutBuilder(builder: (context, constraints) {
            final availableWidth = constraints.hasBoundedWidth
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final gap = hasTranslation ? 16.0 : 0.0;
            final count = hasTranslation ? 2 : 1;
            final columnWidth = math.max(1.0, (availableWidth - gap) / count);
            return animatedColumns(columns(verticalColumnWidth: columnWidth));
          })
        : animatedColumns(columns());
    return Semantics(
      label: [text, if (translation?.trim().isNotEmpty == true) translation!]
          .join('\n'),
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
  const _DesktopLineEntrance(
      {super.key,
      required this.reducedMotion,
      required this.vertical,
      required this.child});
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
      value: widget.reducedMotion ? 1 : 0);
  late final Animation<double> _animation =
      CurvedAnimation(parent: _controller, curve: AppMotion.standardCurve);

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
