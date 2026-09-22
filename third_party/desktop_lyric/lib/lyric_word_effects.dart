import 'dart:math' as math;
import 'dart:ui' as ui;

/// Paint-only effects driven by supplied word timestamps, never by a ticker or
/// guessed LRC syllables. Shared by the player and desktop lyric renderers.
abstract final class LyricWordEffects {
  static const maximumScaleExpansion = .08;
  static double presentationLeadMs(int durationMilliseconds, bool phraseEnd) =>
      phraseEnd && durationMilliseconds > 650
          ? math.min(400, durationMilliseconds * .18)
          : 0;

  static double presentationTailMs(int durationMilliseconds, bool phraseEnd) =>
      phraseEnd && durationMilliseconds > 650
          ? math.min(400, durationMilliseconds * .2)
          : 0;

  /// Phrase-ending held notes anticipate and release around their real timing.
  /// Highlight progress still uses the unmodified provider interval. Keeping
  /// this a pure media-time sample makes pause, reverse seek and hidden resume
  /// deterministic without a second animation clock.
  static ({double lift, double scale}) timedPose({
    required double elapsedMilliseconds,
    required int durationMilliseconds,
    required double fontSize,
    bool phraseEnd = false,
    double phase = 0,
  }) {
    final lead = presentationLeadMs(durationMilliseconds, phraseEnd);
    final tail = presentationTailMs(durationMilliseconds, phraseEnd);
    final span = durationMilliseconds + lead + tail;
    if (span <= 0) return (lift: 0, scale: 1);
    final progress = (elapsedMilliseconds + lead) / span;
    final pose = sustain(
      progress: (progress - phase) / (1 - phase),
      durationMilliseconds: durationMilliseconds,
      fontSize: fontSize,
    );
    final strength = phraseEnd && durationMilliseconds > 650 ? 1.6 : 1.0;
    return (lift: pose.lift * strength, scale: 1 + (pose.scale - 1) * strength);
  }

  static double softEdgeWidth(
          {required double fontSize, required double extent}) =>
      math.min(math.max(0, extent) * .35, fontSize.clamp(10, 120) * .22);

  /// Coordinates along the whole word, including words wrapped across rows.
  /// At zero the feather lies before the first glyph; at one it lies beyond
  /// the last. This keeps both endpoint handoffs continuous.
  static ({double start, double end}) revealEdges({
    required double progress,
    required double extent,
    required double softness,
  }) {
    final end = (math.max(0, extent) + math.max(.001, softness)) *
        progress.clamp(0.0, 1.0);
    return (start: end - math.max(.001, softness), end: end);
  }

  /// [offset] is the cumulative visual extent of earlier boxes in this word.
  /// Reverse describes an RTL horizontal box; vertical uses top-to-bottom.
  static ui.Shader revealShader({
    required ui.Rect bounds,
    required double progress,
    required double extent,
    required double offset,
    required double softness,
    bool reverse = false,
    bool vertical = false,
    ui.Color leading = const ui.Color(0xffffffff),
    ui.Color trailing = const ui.Color(0x00ffffff),
  }) {
    final edges =
        revealEdges(progress: progress, extent: extent, softness: softness);
    ui.Offset point(double value) {
      final coordinate = value - offset;
      return vertical
          ? ui.Offset(bounds.center.dx, bounds.top + coordinate)
          : ui.Offset(
              reverse ? bounds.right - coordinate : bounds.left + coordinate,
              bounds.center.dy);
    }

    return ui.Gradient.linear(
        point(edges.start), point(edges.end), [leading, trailing]);
  }

  /// Every timed syllable rises and settles with zero endpoint velocity.
  /// Very short timings taper smoothly, while held notes retain a wider pose.
  /// This is presentation only: a seek samples the original word interval.
  static ({double lift, double scale}) sustain({
    required double progress,
    required int durationMilliseconds,
    required double fontSize,
  }) {
    if (durationMilliseconds <= 0 || progress <= 0 || progress >= 1) {
      return (lift: 0, scale: 1);
    }
    double smooth(double value) {
      final t = value.clamp(0.0, 1.0);
      return t * t * (3 - 2 * t);
    }

    final weight = smooth(durationMilliseconds / 180) *
        (.45 + .55 * smooth((durationMilliseconds - 650) / 1100));
    final envelope =
        smooth(progress / .24) * smooth((1 - progress) / .28) * weight;
    return (
      lift: math.min(6, fontSize * .10) * envelope,
      scale: 1 + maximumScaleExpansion * envelope
    );
  }
}
