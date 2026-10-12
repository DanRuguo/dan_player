import 'package:flutter/material.dart';
import 'package:desktop_lyric/app_motion.dart';
import 'package:desktop_lyric/lyric_ruby.dart';

/// Reveals optional lyric tracks without changing the timed paragraph's
/// element position. Each row keeps its own finite transition so a setting
/// change can expand every visible row without replacing its glyph painter.
typedef LyricContentVisibility = ({
  double timestamp,
  double romanization,
  double japaneseReading,
  List<LyricRubySpan> japaneseReadingSpans,
  double translation,
});

class LyricContentReveal extends ImplicitlyAnimatedWidget {
  const LyricContentReveal({
    super.key,
    super.onEnd,
    required this.timestamp,
    required this.romanization,
    this.japaneseReading = false,
    this.japaneseReadingSpans = const [],
    this.japaneseReadingSource,
    this.japaneseReadingTransitionIdentity,
    required this.translation,
    required this.builder,
    required bool reducedMotion,
  }) : super(
         duration: reducedMotion ? Duration.zero : AppMotion.lyricLine,
         curve: const Cubic(.22, 0, .16, 1),
       );

  final bool timestamp;
  final bool romanization;
  final bool japaneseReading;

  /// Only projected spans are retained; authored text and timings stay current.
  final List<LyricRubySpan> japaneseReadingSpans;

  /// A real document/row owner. Null disables outgoing-data retention.
  final Object? japaneseReadingSource;

  /// Same-document availability changes share this reveal's existing clock.
  /// The owning row can finish that clock even when it has no reading itself.
  final Object? japaneseReadingTransitionIdentity;
  final bool translation;
  final Widget Function(BuildContext, LyricContentVisibility) builder;

  /// A zero-height placeholder keeps the following primary paragraph at the
  /// same child index even when an optional track is entirely hidden.
  static Widget part(
    double value,
    Widget child, {
    Alignment alignment = Alignment.center,
  }) {
    final progress = value.clamp(0.0, 1.0);
    if (progress == 0) return const SizedBox.shrink();
    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        heightFactor: progress,
        child: Opacity(
          opacity: progress,
          child: Align(alignment: alignment, child: child),
        ),
      ),
    );
  }

  @override
  AnimatedWidgetBaseState<LyricContentReveal> createState() =>
      _LyricContentRevealState();
}

class _LyricContentRevealState
    extends AnimatedWidgetBaseState<LyricContentReveal> {
  Tween<double>? _timestamp;
  Tween<double>? _romanization;
  Tween<double>? _japaneseReading;
  Tween<double>? _translation;
  Tween<double>? _japaneseTransition;
  Object? _transitionIdentity;
  double _transitionRevision = 0;
  List<LyricRubySpan> _acceptedSpans = const [];
  List<LyricRubySpan> _outgoingSpans = const [];

  @override
  void initState() {
    _acceptedSpans = List.unmodifiable(widget.japaneseReadingSpans);
    super.initState();
  }

  @override
  void didUpdateWidget(LyricContentReveal oldWidget) {
    if (widget.japaneseReadingSource == null ||
        widget.japaneseReadingSource != oldWidget.japaneseReadingSource) {
      _outgoingSpans = const [];
    }
    if (!identical(
      widget.japaneseReadingSpans,
      oldWidget.japaneseReadingSpans,
    )) {
      _acceptedSpans = List.unmodifiable(widget.japaneseReadingSpans);
    }
    super.didUpdateWidget(oldWidget);
    if (widget.duration == Duration.zero) {
      controller.stop();
      controller.value = 1;
    }
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    Tween<double>? number(Tween<double>? tween, bool visible) => visitor(
      tween,
      visible ? 1.0 : 0.0,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
    _timestamp = number(_timestamp, widget.timestamp);
    _romanization = number(_romanization, widget.romanization);
    _japaneseReading = number(_japaneseReading, widget.japaneseReading);
    _translation = number(_translation, widget.translation);
    final identity = widget.japaneseReadingTransitionIdentity;
    if (identity != _transitionIdentity) {
      _transitionIdentity = identity;
      _transitionRevision++;
    }
    // No extra controller/timer. A partial projection can change another
    // row's local 0->1 tween while this callback owner remains at 0 or 1.
    _japaneseTransition = visitor(
      _japaneseTransition,
      _transitionRevision,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final reading = _japaneseReading!.evaluate(animation);
    if (reading == 0) {
      // Also handles reduced/hidden duration-zero endpoints. No timeout.
      _outgoingSpans = const [];
    } else if (widget.japaneseReadingSource != null &&
        _acceptedSpans.isNotEmpty) {
      _outgoingSpans = _acceptedSpans;
    }
    final spans = reading == 0
        ? const <LyricRubySpan>[]
        : _acceptedSpans.isNotEmpty
        ? _acceptedSpans
        : widget.japaneseReadingSource != null
        ? _outgoingSpans
        : const <LyricRubySpan>[];
    return widget.builder(context, (
      timestamp: _timestamp!.evaluate(animation),
      romanization: _romanization!.evaluate(animation),
      japaneseReading: reading,
      japaneseReadingSpans: spans,
      translation: _translation!.evaluate(animation),
    ));
  }
}
