import 'package:desktop_lyric/component/desktop_lyric_text.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';

/// A small, isolated glyph preview of the control's draft. It never publishes
/// appearance, advances media time or owns a word-sampling subscription.
class LyricLetterSpacingPreview extends StatefulWidget {
  const LyricLetterSpacingPreview(
      {super.key,
      required this.value,
      required this.text,
      this.visible = true});

  final double value;
  final String text;
  final bool visible;

  @override
  State<LyricLetterSpacingPreview> createState() =>
      _LyricLetterSpacingPreviewState();
}

class _LyricLetterSpacingPreviewState extends State<LyricLetterSpacingPreview> {
  final _clock = PlaybackClock(automaticTicks: false);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge!;
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: TickerMode(
          enabled: widget.visible,
          child: LayoutBuilder(builder: (context, constraints) {
            return ClipRect(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DesktopLyricText(
                  text: widget.text,
                  clock: _clock,
                  style: style.copyWith(
                      letterSpacing: (style.letterSpacing ?? 0) + widget.value),
                  verticalLetterSpacing: widget.value,
                  maxHorizontalWidth: constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : null,
                  playedColor: color,
                  unplayedColor: color,
                  reducedMotion: !widget.visible,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}
