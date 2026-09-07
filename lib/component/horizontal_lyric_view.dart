import 'package:dan_player/component/app_motion.dart';
import 'dart:async';

import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class HorizontalLyricView extends StatelessWidget {
  const HorizontalLyricView({super.key});

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    final playback = PlayService.instance.playbackService;
    final lyrics = PlayService.instance.lyricService;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListenableBuilder(
        listenable: lyrics,
        builder: (context, _) => HorizontalLyricContent(
          lyricFuture: lyrics.currLyricFuture,
          positionStream: playback.positionStream,
          readPosition: () => playback.position,
        ),
      ),
    );
  }
}

/// Uses the selected lyric future and player position; it does not start a
/// second lyric request or a wall-clock marquee that continues after pause.
class HorizontalLyricContent extends StatefulWidget {
  const HorizontalLyricContent({
    super.key,
    required this.lyricFuture,
    required this.positionStream,
    required this.readPosition,
  });

  final Future<Lyric?>? lyricFuture;
  final Stream<double> positionStream;
  final double Function() readPosition;

  @override
  State<HorizontalLyricContent> createState() => _HorizontalLyricContentState();
}

class _HorizontalLyricContentState extends State<HorizontalLyricContent>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: FutureBuilder<Lyric?>(
          key: ObjectKey(widget.lyricFuture),
          future: widget.lyricFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                snapshot.data == null ||
                snapshot.data!.lines.isEmpty ||
                snapshot.hasError) {
              return Center(
                child: Text(
                  snapshot.hasError ? ui("歌词暂不可用") : 'Enjoy Music',
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              );
            }
            return _HorizontalLyricTimeline(
              key: ObjectKey(snapshot.data),
              lyric: snapshot.data!,
              positionStream: widget.positionStream,
              readPosition: widget.readPosition,
              reducedMotion: LyricMotion.reducedOf(context),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _HorizontalLyricTimeline extends StatefulWidget {
  const _HorizontalLyricTimeline({
    super.key,
    required this.lyric,
    required this.positionStream,
    required this.readPosition,
    required this.reducedMotion,
  });

  final Lyric lyric;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final bool reducedMotion;

  @override
  State<_HorizontalLyricTimeline> createState() =>
      _HorizontalLyricTimelineState();
}

class _HorizontalLyricTimelineState extends State<_HorizontalLyricTimeline> {
  late final ValueNotifier<Duration> _position;
  StreamSubscription<double>? _subscription;
  int _generation = 0;
  int _lineRevision = 0;
  late int _currentLine;

  Duration _safePosition(double value) => Duration(
        milliseconds: value.isFinite && value > 0 ? (value * 1000).round() : 0,
      );

  @override
  void initState() {
    super.initState();
    _position = ValueNotifier(_safePosition(widget.readPosition()));
    _currentLine =
        findCurrentLyricLineIndex(widget.lyric.lines, _position.value);
    _subscribe();
  }

  void _subscribe() {
    final generation = ++_generation;
    _subscription?.cancel();
    _subscription = widget.positionStream.listen((value) {
      if (!mounted || generation != _generation) return;
      _position.value = _safePosition(value);
      final next =
          findCurrentLyricLineIndex(widget.lyric.lines, _position.value);
      if (next != _currentLine) {
        setState(() {
          _currentLine = next;
          _lineRevision++;
        });
      }
    });
  }

  @override
  void didUpdateWidget(_HorizontalLyricTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.positionStream, widget.positionStream)) {
      _position.value = _safePosition(widget.readPosition());
      _currentLine =
          findCurrentLyricLineIndex(widget.lyric.lines, _position.value);
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final line = widget.lyric.lines[_currentLine];
    final plain =
        widget.lyric is PlainLyric ? widget.lyric as PlainLyric : null;
    final content = plain == null
        ? switch (line) {
            SyncLyricLine value => [
                value.content,
                if (value.translation != null) value.translation!
              ].where((part) => part.trim().isNotEmpty).join('┃'),
            UnsyncLyricLine value => value.content,
            _ => '',
          }
        : ui("{0} · 无时间轴歌词", [plain.firstLine]);
    var length = switch (line) {
      SyncLyricLine value => value.length,
      LrcLine value => value.length,
      _ => Duration.zero,
    };
    if (length <= Duration.zero &&
        _currentLine + 1 < widget.lyric.lines.length) {
      length = widget.lyric.lines[_currentLine + 1].start - line.start;
    }
    final key = ValueKey((_currentLine, _lineRevision, line.start, content));
    final child = _HorizontalLyricLine(
      key: key,
      content: content.isEmpty ? ui("间奏 · 聆听音乐") : content,
      start: line.start,
      length: length,
      position: _position,
      reducedMotion: widget.reducedMotion,
    );
    if (widget.reducedMotion) return child;
    return AnimatedSwitcher(
      key: const ValueKey('horizontal-lyric-switcher'),
      duration: AppMotion.standard,
      switchInCurve: LyricMotion.curve,
      switchOutCurve: LyricMotion.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) => IgnorePointer(
        ignoring: child.key != key,
        child: ExcludeSemantics(
          excluding: child.key != key,
          child: FadeTransition(opacity: animation, child: child),
        ),
      ),
      child: child,
    );
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _position.dispose();
    super.dispose();
  }
}

class _HorizontalLyricLine extends StatefulWidget {
  const _HorizontalLyricLine({
    super.key,
    required this.content,
    required this.start,
    required this.length,
    required this.position,
    required this.reducedMotion,
  });

  final String content;
  final Duration start;
  final Duration length;
  final ValueNotifier<Duration> position;
  final bool reducedMotion;

  @override
  State<_HorizontalLyricLine> createState() => _HorizontalLyricLineState();
}

class _HorizontalLyricLineState extends State<_HorizontalLyricLine> {
  final _scrollController = ScrollController();
  Timer? _manualTimer;
  bool _manual = false;
  bool _dragging = false;
  int _frameGeneration = 0;
  Object? _layoutIdentity;
  late Duration _previousPosition;

  @override
  void initState() {
    super.initState();
    _previousPosition = widget.position.value;
    widget.position.addListener(_onPosition);
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(_HorizontalLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.position, widget.position)) {
      oldWidget.position.removeListener(_onPosition);
      widget.position.addListener(_onPosition);
      _previousPosition = widget.position.value;
      _scheduleScroll();
    }
    if (oldWidget.reducedMotion != widget.reducedMotion) _scheduleScroll();
  }

  void _scheduleScroll() {
    final generation = ++_frameGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _frameGeneration) {
        _syncScroll(immediate: true);
      }
    });
  }

  void _onPosition() {
    final delta = widget.position.value - _previousPosition;
    _previousPosition = widget.position.value;
    _syncScroll(
      immediate: delta.isNegative || delta > const Duration(milliseconds: 200),
    );
  }

  void _syncScroll({required bool immediate}) {
    if (!mounted || !_scrollController.hasClients || _manual) return;
    final extent = _scrollController.position.maxScrollExtent;
    final movingTime = widget.length - const Duration(milliseconds: 600);
    final progress = movingTime > Duration.zero
        ? LyricMotion.progress(
            widget.position.value,
            widget.start + const Duration(milliseconds: 300),
            movingTime,
          )
        : 0.0;
    final target = widget.reducedMotion ? 0.0 : extent * progress;
    if ((target - _scrollController.offset).abs() < .25) return;
    if (immediate || widget.reducedMotion) {
      _scrollController.jumpTo(target);
    } else {
      // Smooth only between actual samples, never extrapolate past the latest
      // playback time. The finite activity settles even when playback pauses.
      unawaited(_scrollController.animateTo(
        target,
        duration: AppMotion.followSample,
        curve: Curves.linear,
      ));
    }
  }

  void _manualInteraction({bool dragging = false}) {
    _manual = true;
    _manualTimer?.cancel();
    if (dragging) _dragging = true;
    if (!_dragging) _resumeAfterGrace();
  }

  void _resumeAfterGrace() {
    _manualTimer?.cancel();
    _manualTimer = Timer(LyricMotion.manualScrollGrace, () {
      if (!mounted || _dragging) return;
      _manual = false;
      _syncScroll(immediate: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutIdentity = (
          constraints.maxWidth,
          MediaQuery.textScalerOf(context),
          Theme.of(context).textTheme.bodyMedium,
        );
        if (_layoutIdentity != layoutIdentity) {
          _layoutIdentity = layoutIdentity;
          _scheduleScroll();
        }
        return Semantics(
          label: widget.content,
          child: ExcludeSemantics(
            child: Tooltip(
              message: widget.content,
              excludeFromSemantics: true,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _manualInteraction();
                },
                onPointerCancel: (_) {
                  _dragging = false;
                  if (_manual) _resumeAfterGrace();
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.depth != 0) return false;
                    if (notification is ScrollStartNotification &&
                            notification.dragDetails != null ||
                        notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                      _manualInteraction(dragging: true);
                    }
                    if (notification is ScrollEndNotification && _dragging) {
                      _dragging = false;
                      _resumeAfterGrace();
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    key: const ValueKey('horizontal-lyric-scroll'),
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    // Short lines fill the viewport so they can be centred.
                    // Long lines retain their natural single-line width and
                    // the same playback-driven scroll extent, without slicing
                    // words, graphemes or bidirectional lyric content.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Center(
                        child: Text(
                          widget.content,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _frameGeneration++;
    widget.position.removeListener(_onPosition);
    _manualTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
}
