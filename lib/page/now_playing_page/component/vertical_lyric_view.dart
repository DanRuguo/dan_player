import 'dart:async';
import 'package:dan_player/rendering_preferences.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:desktop_lyric/ui_language.dart';

bool ALWAYS_SHOW_LYRIC_VIEW_CONTROLS = false;

class VerticalLyricView extends StatefulWidget {
  const VerticalLyricView({super.key});

  @override
  State<VerticalLyricView> createState() => _VerticalLyricViewState();
}

class _VerticalLyricViewState extends State<VerticalLyricView> {
  bool isHovering = false;
  final lyricViewController = LyricViewController();

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playback = PlayService.instance.playbackService;
    final lyrics = PlayService.instance.lyricService;
    return MouseRegion(
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: Material(
        type: MaterialType.transparency,
        child: ChangeNotifierProvider.value(
          value: lyricViewController,
          child: Stack(
            children: [
              ValueListenableBuilder(
                valueListenable: AppSettings.instance.experience,
                builder: (context, experience, _) => ListenableBuilder(
                  listenable: lyrics,
                  builder: (context, _) => VerticalLyricContent(
                    lyricFuture: lyrics.currLyricFuture,
                    positionStream: playback.positionStream,
                    readPosition: () => playback.position,
                    onSeek: playback.seek,
                    springLyrics: experience.springLyrics,
                    hidden: DesktopIntegration.instance.isHidden,
                  ),
                ),
              ),
              if (isHovering || ALWAYS_SHOW_LYRIC_VIEW_CONTROLS)
                const Align(
                  alignment: Alignment.bottomRight,
                  child: LyricViewControls(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    lyricViewController.dispose();
    super.dispose();
  }
}

/// The real lyric surface, separated from the player singleton so its loading,
/// source replacement and playback transitions can be exercised in isolation.
/// The future belongs to LyricService; no lyric/network request is made here.
class VerticalLyricContent extends StatefulWidget {
  const VerticalLyricContent({
    super.key,
    required this.lyricFuture,
    required this.positionStream,
    required this.readPosition,
    required this.onSeek,
    this.springLyrics = false,
    this.hidden,
  });

  final Future<Lyric?>? lyricFuture;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final bool springLyrics;
  final ValueListenable<bool>? hidden;

  @override
  State<VerticalLyricContent> createState() => _VerticalLyricContentState();
}

class _VerticalLyricContentState extends State<VerticalLyricContent>
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
    return FutureBuilder<Lyric?>(
      // A source change clears the old snapshot immediately; late success or
      // failure from that source cannot resurrect its rows or scroll target.
      key: ObjectKey(widget.lyricFuture),
      future: widget.lyricFuture,
      builder: (context, snapshot) {
        if (widget.lyricFuture != null &&
            snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Semantics(
              label: ui("正在加载歌词"),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  value: LyricMotion.reducedOf(context) ? .72 : null,
                ),
              ),
            ),
          );
        }
        final lyric = snapshot.data;
        if (snapshot.hasError || lyric == null || lyric.lines.isEmpty) {
          return Center(
            child: Text(
              snapshot.hasError ? ui("歌词加载失败，请切换来源或重试") : ui("无歌词"),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          );
        }
        return VerticalLyricScrollView(
          lyric: lyric,
          positionStream: widget.positionStream,
          readPosition: widget.readPosition,
          onSeek: widget.onSeek,
          springLyrics: widget.springLyrics,
          hidden: widget.hidden,
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Scrollable rows keep their identity for the life of one resolved lyric.
/// Only changes of the current line rebuild the list; position samples repaint
/// the current timed paragraph/interlude without rebuilding every row.
class VerticalLyricScrollView extends StatefulWidget {
  const VerticalLyricScrollView({
    super.key,
    required this.lyric,
    required this.positionStream,
    required this.readPosition,
    required this.onSeek,
    this.springLyrics = false,
    this.hidden,
  });

  final Lyric lyric;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final bool springLyrics;
  final ValueListenable<bool>? hidden;

  @override
  State<VerticalLyricScrollView> createState() =>
      _VerticalLyricScrollViewState();
}

class _VerticalLyricScrollViewState extends State<VerticalLyricScrollView>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  late final ValueNotifier<Duration> _position;
  StreamSubscription<double>? _positionSubscription;
  Stream<double>? _listeningTo;
  List<GlobalKey> _lineKeys = [];
  int _currentLine = -1;
  int _sourceGeneration = 0;
  int _followGeneration = 0;
  Timer? _manualScrollTimer;
  bool _manualScrollActive = false;
  bool _dragging = false;
  Object? _layoutIdentity;
  bool? _wasReduced;
  AppLifecycleState? _lifecycle;
  bool _treeVisible = false;
  ValueListenable<RenderingPreferences>? _preferences;
  bool _active = false;

  Duration _safePosition(double seconds) => Duration(
        milliseconds:
            seconds.isFinite && seconds > 0 ? (seconds * 1000).round() : 0,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    widget.hidden?.addListener(_syncActivity);
    _position = ValueNotifier(Duration.zero);
    _resetLyric();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = RenderingPreferencesScope.listenableOf(context);
    if (!identical(preferences, _preferences)) {
      _preferences?.removeListener(_syncActivity);
      _preferences = preferences..addListener(_syncActivity);
    }
    _treeVisible = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Hidden HWNDs and paused bindings may not draw another frame.
    _syncActivity();
  }

  void _syncActivity() {
    final active = (_preferences?.value ?? const RenderingPreferences())
        .allowsVisualUpdates(
      lifecycle: _lifecycle,
      treeVisible: _treeVisible,
      nativeHidden: widget.hidden?.value ?? false,
    );
    if (active == _active) return;
    _active = active;
    setState(() {});
    if (active) {
      _subscribeToPosition();
      // Keep mounted glyph/row caches, but never replay hidden position frames
      // or a stale manual-scroll grace period when this surface returns.
      _receivePosition(widget.readPosition(),
          forceFollow: true, immediate: true);
    } else {
      _sourceGeneration++;
      unawaited(_positionSubscription?.cancel());
      _positionSubscription = null;
      _listeningTo = null;
      _followGeneration++;
      _manualScrollTimer?.cancel();
      _manualScrollTimer = null;
      _manualScrollActive = false;
      _dragging = false;
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        _scrollController.jumpTo(_scrollController.offset);
      }
    }
  }

  void _resetLyric() {
    _manualScrollTimer?.cancel();
    _manualScrollActive = false;
    _dragging = false;
    _followGeneration++;
    _lineKeys = List.generate(
      widget.lyric.lines.length,
      (index) => GlobalKey(debugLabel: 'lyric-line-$index'),
    );
    if (_active) _position.value = _safePosition(widget.readPosition());
    _currentLine =
        findCurrentLyricLineIndex(widget.lyric.lines, _position.value);
    _scheduleFollow(immediate: true);
  }

  void _subscribeToPosition() {
    if (identical(_listeningTo, widget.positionStream)) return;
    final generation = ++_sourceGeneration;
    _positionSubscription?.cancel();
    _listeningTo = widget.positionStream;
    _positionSubscription = widget.positionStream.listen((position) {
      if (!mounted || generation != _sourceGeneration) return;
      _receivePosition(position);
    });
  }

  @override
  void didUpdateWidget(VerticalLyricScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyric, widget.lyric)) _resetLyric();
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
      _syncActivity();
    }
    if (_active && !identical(_listeningTo, widget.positionStream)) {
      _subscribeToPosition();
      _receivePosition(widget.readPosition());
    }
    if (oldWidget.springLyrics != widget.springLyrics) {
      // Changing the preference cancels the previous driven activity. Respect
      // a user-held/manual scroll instead of pulling it back to the singer.
      _scheduleFollow(seek: true);
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  void _receivePosition(double seconds,
      {bool forceFollow = false, bool immediate = false}) {
    if (!_active) return;
    final nextPosition = _safePosition(seconds);
    _position.value = nextPosition;
    final nextLine =
        findCurrentLyricLineIndex(widget.lyric.lines, nextPosition);
    if (nextLine == _currentLine && !forceFollow) return;
    final seek = (nextLine - _currentLine).abs() > 1;
    if (nextLine != _currentLine) setState(() => _currentLine = nextLine);
    if (!_manualScrollActive) {
      _scheduleFollow(seek: seek || forceFollow, immediate: immediate);
    }
  }

  void _seekToLine(int index) {
    try {
      widget.onSeek(widget.lyric.lines[index].start.inMilliseconds / 1000);
    } catch (error) {
      showAppNotice(
        ui("无法跳转到该歌词：{0}", [error]),
        context: context,
        kind: AppNoticeKind.error,
      );
      return;
    }
    _manualScrollTimer?.cancel();
    _manualScrollActive = false;
    _dragging = false;
    // A successful native seek reports its real position immediately. Do not
    // display a guessed target if the source quantizes/limits seeking.
    _receivePosition(widget.readPosition(), forceFollow: true);
  }

  void _scheduleFollow({bool immediate = false, bool seek = false}) {
    if (!_active) return;
    final generation = ++_followGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_active ||
          generation != _followGeneration ||
          _manualScrollActive ||
          !_scrollController.hasClients ||
          _currentLine < 0 ||
          _currentLine >= _lineKeys.length) {
        return;
      }
      final target = _lineKeys[_currentLine].currentContext?.findRenderObject();
      if (target is! RenderBox || !target.attached || !target.hasSize) return;
      final position = _scrollController.position;
      final alignment =
          target.size.height > position.viewportDimension * .7 ? 0.0 : .25;
      final offset = RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, alignment)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((offset - position.pixels).abs() < .5) {
        if (position.isScrollingNotifier.value) {
          _scrollController.jumpTo(offset);
        }
        return;
      }
      if (immediate || LyricMotion.reducedOf(context)) {
        _scrollController.jumpTo(offset);
      } else {
        // A new animateTo starts at the current offset and cancels the previous
        // activity. Seeks stay monotonic even when the optional spring is on.
        final spring = widget.springLyrics && !seek;
        unawaited(_scrollController.animateTo(
          offset,
          duration: seek
              ? LyricMotion.seekScrollDuration
              : spring
                  ? LyricMotion.springScrollDuration
                  : LyricMotion.scrollDuration,
          curve: LyricMotion.scrollCurveFor(
            spring: spring,
            distance: offset - position.pixels,
          ),
        ));
      }
    });
  }

  void _markManualInteraction({bool dragging = false}) {
    if (!_active) return;
    _followGeneration++;
    _manualScrollActive = true;
    _manualScrollTimer?.cancel();
    if (dragging) _dragging = true;
    if (!_dragging) _resumeAfterGrace();
  }

  void _resumeAfterGrace() {
    if (!_active) return;
    _manualScrollTimer?.cancel();
    _manualScrollTimer = Timer(LyricMotion.manualScrollGrace, () {
      if (!mounted || !_active || _dragging) return;
      _manualScrollActive = false;
      _scheduleFollow();
      // Timer callbacks can arrive while paused, without a new position frame.
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final directDrag = notification is ScrollStartNotification &&
            notification.dragDetails != null ||
        notification is ScrollUpdateNotification &&
            notification.dragDetails != null ||
        notification is OverscrollNotification &&
            notification.dragDetails != null;
    if (directDrag) _markManualInteraction(dragging: true);
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _resumeAfterGrace();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final reduced = !_active || LyricMotion.reducedOf(context);
    if (_wasReduced != null && reduced != _wasReduced && reduced) {
      _scheduleFollow(immediate: true);
    }
    _wasReduced = reduced;
    final settings = context.watch<LyricViewController>();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final layoutIdentity = (
          constraints.maxWidth,
          height,
          settings.lyricFontSize,
          settings.translationFontSize,
          settings.lyricTextAlign,
          MediaQuery.textScalerOf(context),
        );
        if (_layoutIdentity != null && _layoutIdentity != layoutIdentity) {
          _scheduleFollow(immediate: true);
        }
        _layoutIdentity = layoutIdentity;
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _markManualInteraction();
          },
          onPointerPanZoomStart: (_) => _markManualInteraction(dragging: true),
          onPointerPanZoomEnd: (_) {
            _dragging = false;
            if (_manualScrollActive) _resumeAfterGrace();
          },
          onPointerCancel: (_) {
            _dragging = false;
            if (_manualScrollActive) _resumeAfterGrace();
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: ScrollConfiguration(
              behavior: const ScrollBehavior().copyWith(scrollbars: false),
              child: CustomScrollView(
                key: const ValueKey('vertical-lyric-scroll'),
                controller: _scrollController,
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: height * .25)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < widget.lyric.lines.length;
                              index++)
                            SizedBox(
                              key: _lineKeys[index],
                              width: double.infinity,
                              child: LyricViewTile(
                                key: ValueKey(index),
                                line: widget.lyric.lines[index],
                                position: _position,
                                distance: (index - _currentLine).abs(),
                                opacity: LyricMotion.opacityForDistance(
                                    index - _currentLine),
                                reducedMotion: reduced,
                                onTap: widget.lyric is PlainLyric
                                    ? null
                                    : () => _seekToLine(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: height * .75)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sourceGeneration++;
    _followGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    widget.hidden?.removeListener(_syncActivity);
    _preferences?.removeListener(_syncActivity);
    _positionSubscription?.cancel();
    _manualScrollTimer?.cancel();
    _scrollController.dispose();
    _position.dispose();
    super.dispose();
  }
}
