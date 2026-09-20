import 'dart:async';
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/lrc.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/src/bass/bass_player.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
                  builder: (context, _) => StreamBuilder<PlayerState>(
                    stream: playback.playerStateStream,
                    initialData: playback.playerState,
                    builder: (context, state) => VerticalLyricContent(
                      lyricFuture: lyrics.currLyricFuture,
                      positionStream: playback.positionStream,
                      readPosition: () => playback.position,
                      onSeek: playback.seek,
                      springLyrics: experience.springLyrics,
                      hidden: DesktopIntegration.instance.isHidden,
                      playing: state.data == PlayerState.playing,
                    ),
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
    this.playing = false,
  });

  final Future<Lyric?>? lyricFuture;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final bool springLyrics;
  final ValueListenable<bool>? hidden;
  final bool playing;

  @override
  State<VerticalLyricContent> createState() => _VerticalLyricContentState();
}

class _VerticalLyricContentState extends State<VerticalLyricContent>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;

  void _visibilityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant VerticalLyricContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) {
      oldWidget.hidden?.removeListener(_visibilityChanged);
      widget.hidden?.addListener(_visibilityChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _visibilityChanged();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    widget.hidden?.addListener(_visibilityChanged);
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final reduced =
        LyricMotion.reducedOf(context) || widget.hidden?.value == true;
    final active = RenderingPreferencesScope.listenableOf(context)
        .value
        .allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: TickerMode.valuesOf(context).enabled,
          nativeHidden: widget.hidden?.value ?? false,
        );
    return TickerMode(
      enabled: active,
      child: FutureBuilder<Lyric?>(
        // A pending replacement must not retain the preceding song on screen.
        future: widget.lyricFuture,
        builder: (context, snapshot) {
          final waiting = widget.lyricFuture != null &&
              snapshot.connectionState != ConnectionState.done;
          final lyric =
              waiting || widget.lyricFuture == null ? null : snapshot.data;
          Widget content;
          if (lyric != null && lyric.lines.isNotEmpty && !snapshot.hasError) {
            content = VerticalLyricScrollView(
              key: ObjectKey(lyric),
              lyric: lyric,
              positionStream: widget.positionStream,
              readPosition: widget.readPosition,
              onSeek: widget.onSeek,
              springLyrics: widget.springLyrics,
              hidden: widget.hidden,
              playing: widget.playing,
            );
          } else {
            final label = waiting
                ? ui("正在加载歌词")
                : snapshot.hasError
                    ? ui("歌词加载失败，请切换来源或重试")
                    : ui("无歌词");
            content = Center(
              key: ValueKey(label),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      color:
                          Theme.of(context).colorScheme.onSecondaryContainer)),
            );
          }
          return AnimatedSwitcher(
            duration:
                reduced ? Duration.zero : const Duration(milliseconds: 320),
            switchInCurve: const Interval(.5, 1, curve: Curves.easeOutCubic),
            switchOutCurve: const Interval(.5, 1, curve: Curves.easeInCubic),
            transitionBuilder: (child, animation) => AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, child) {
                final leaving = animation.status == AnimationStatus.reverse;
                return TickerMode(
                  enabled: !leaving,
                  child: IgnorePointer(
                      ignoring: leaving,
                      child: ExcludeSemantics(
                          excluding: leaving,
                          child: FadeTransition(
                              opacity: animation,
                              child: _LyricExitScope(
                                  exiting: leaving, child: child!)))),
                );
              },
            ),
            child: content,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.hidden?.removeListener(_visibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

// An outgoing surface must stop consuming the new song's timeline even when
// the user allows offscreen visuals. This scope changes only at entry/exit.
class _LyricExitScope extends InheritedWidget {
  const _LyricExitScope({required this.exiting, required super.child});
  final bool exiting;
  @override
  bool updateShouldNotify(_LyricExitScope oldWidget) =>
      exiting != oldWidget.exiting;
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
    this.playing = false,
    this.suspended = false,
  });

  final Lyric lyric;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final bool springLyrics;
  final ValueListenable<bool>? hidden;
  final bool playing;
  final bool suspended;

  @override
  State<VerticalLyricScrollView> createState() =>
      _VerticalLyricScrollViewState();
}

class _VerticalLyricScrollViewState extends State<VerticalLyricScrollView>
    with WidgetsBindingObserver, TickerProviderStateMixin {
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
  bool _exiting = false;
  bool _treeVisible = false;
  ValueListenable<RenderingPreferences>? _preferences;
  bool _active = false;
  late final AnimationController _followClock;
  late final AnimationController _readingClock;
  late final Ticker _mediaTicker;
  bool _pointerReading = false;

  void _setPointerReading(bool reading) {
    if (_pointerReading == reading) return;
    _pointerReading = reading;
    final target = reading ? 0.0 : 1.0;
    if (!_active || _motionHidden || LyricMotion.reducedOf(context)) {
      _readingClock.value = target;
    } else {
      _readingClock.animateTo(target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic);
    }
  }

  Map<int, LyricFollowTransition> _followTransitions = {};
  Map<int, double> _restBlur = {};
  Object? _tileCacheIdentity;
  List<LyricViewTile> _tileCache = [];
  bool get _motionHidden =>
      widget.hidden?.value == true ||
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached;

  Duration _safePosition(double seconds) => Duration(
        milliseconds:
            seconds.isFinite && seconds > 0 ? (seconds * 1000).round() : 0,
      );

  @override
  void initState() {
    super.initState();
    // Native playback time remains authoritative. The low-frequency position
    // stream still drives nonanimated/hidden states; no extrapolated clock.
    _mediaTicker = createTicker((_) {
      if (_active && widget.playing && !_exiting) {
        _receivePosition(widget.readPosition());
      }
    });
    _readingClock = AnimationController(vsync: this, value: 1);
    _followClock = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed &&
            _followTransitions.isNotEmpty) {
          setState(() => _followTransitions = {});
        }
      });
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
    // Popup routes leave this surface visible. Overlay already disables
    // TickerMode when an opaque route covers it; isCurrent would also stop
    // playback visuals behind ordinary dialogs and popup menus.
    _treeVisible = TickerMode.valuesOf(context).enabled;
    _exiting = context
            .dependOnInheritedWidgetOfExactType<_LyricExitScope>()
            ?.exiting ??
        false;
    _syncActivity();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    // Hidden HWNDs and paused bindings may not draw another frame.
    _syncActivity();
  }

  void _syncActivity() {
    final active = !widget.suspended &&
        !_exiting &&
        (_preferences?.value ?? const RenderingPreferences())
            .allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: _treeVisible,
          nativeHidden: widget.hidden?.value ?? false,
        );
    if (active == _active) {
      if (!active ||
          _motionHidden ||
          !(_preferences?.value.animations.allows(MotionKind.lyrics) ?? true)) {
        _cancelFollowEffects();
      }
      if (mounted) setState(() {});
      return;
    }
    _active = active;
    setState(() {});
    if (active) {
      _subscribeToPosition();
      // Keep mounted glyph/row caches, but never replay hidden position frames
      // or a stale manual-scroll grace period when this surface returns.
      _receivePosition(widget.readPosition(),
          forceFollow: true, immediate: true);
    } else {
      _cancelFollowEffects();
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
    _cancelFollowEffects();
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
    if (!widget.playing) _mediaTicker.stop();
    if (!identical(oldWidget.lyric, widget.lyric)) _resetLyric();
    if (oldWidget.suspended != widget.suspended) _syncActivity();
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
          target.size.height > position.viewportDimension * .7 ? 0.0 : .34;
      final offset = RenderAbstractViewport.of(target)
          .getOffsetToReveal(target, alignment)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      final reduced = _motionHidden || LyricMotion.reducedOf(context);
      final spring = widget.springLyrics && !seek;
      final duration = seek
          ? LyricMotion.seekScrollDuration
          : spring
              ? LyricMotion.springScrollDuration
              : LyricMotion.scrollDuration;
      final curve = LyricMotion.scrollCurveFor(
        spring: spring,
        distance: offset - position.pixels,
      );
      _prepareFollowEffects(
        offset: offset,
        duration: duration,
        curve: curve,
        animate: !immediate && !reduced && !seek,
      );
      if ((offset - position.pixels).abs() < .5) {
        if (position.isScrollingNotifier.value) {
          _scrollController.jumpTo(offset);
        }
        return;
      }
      if (immediate || reduced) {
        _scrollController.jumpTo(offset);
      } else {
        // A new animateTo starts at the current offset and cancels the previous
        // activity. Seeks stay monotonic even when the optional spring is on.
        unawaited(_scrollController.animateTo(
          offset,
          duration: duration,
          curve: curve,
        ));
      }
    });
  }

  void _markManualInteraction({bool dragging = false}) {
    if (!_active) return;
    _followGeneration++;
    _manualScrollActive = true;
    _cancelFollowEffects();
    if (_scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value &&
        !dragging) {
      _scrollController.jumpTo(_scrollController.offset);
    }
    setState(() {});
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
      setState(() {});
      _scheduleFollow();
      // Timer callbacks can arrive while paused, without a new position frame.
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  void _cancelFollowEffects() {
    _mediaTicker.stop();
    _followClock.stop();
    _readingClock.value = _pointerReading ? 0 : 1;
    _followTransitions = {};
    _restBlur = {};
  }

  /// Find the viewport band by binary search over already-laid-out rows. No
  /// whole-song geometry scan or per-frame position lookup is needed.
  List<int> _visibleFollowRows(double offset) {
    final position = _scrollController.position;
    double top(int index) {
      final row = _lineKeys[index].currentContext?.findRenderObject();
      if (row is! RenderBox || !row.hasSize) return double.infinity;
      return RenderAbstractViewport.of(row).getOffsetToReveal(row, 0).offset;
    }

    var low = 0;
    var high = _lineKeys.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (top(middle) < offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final rows = <int>[];
    for (var i = (low - 1).clamp(0, _lineKeys.length);
        i < _lineKeys.length && rows.length < LyricMotion.maximumFollowRows;
        i++) {
      if (top(i) > offset + position.viewportDimension + 48) break;
      rows.add(i);
    }
    return rows;
  }

  void _prepareFollowEffects({
    required double offset,
    required Duration duration,
    required Curve curve,
    required bool animate,
  }) {
    final reduced = _motionHidden || LyricMotion.reducedOf(context);
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final blurAllowed =
        !reduced && !highContrast && (_preferences?.value.surfaceBlur ?? true);
    final rows = <int>{
      ..._visibleFollowRows(offset),
      ..._visibleFollowRows(_scrollController.offset),
    }.take(LyricMotion.maximumFollowRows).toList();
    final transitions = <int, LyricFollowTransition>{};
    final blur = <int, double>{};
    for (final index in rows) {
      final targetBlur =
          blurAllowed ? LyricMotion.blurForDistance(index - _currentLine) : 0.0;
      blur[index] = targetBlur;
      if (animate) {
        final previous = _followTransitions[index]?.sample(_followClock.value);
        transitions[index] = LyricFollowTransition(
          distance: offset - _scrollController.offset,
          delay: ((index - _currentLine).abs() * .055).clamp(0, .26),
          curve: curve,
          initialOffset: previous?.offset ?? 0,
          initialBlur: previous?.blur ?? _restBlur[index] ?? 0,
          finalBlur: targetBlur,
        );
      }
    }
    _followClock.stop();
    setState(() {
      _followTransitions = transitions;
      _restBlur = blur;
    });
    if (transitions.isNotEmpty) {
      _followClock.duration = duration;
      _followClock.forward(from: 0);
    }
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
    final reduced = !_active || _motionHidden || LyricMotion.reducedOf(context);
    final current =
        _currentLine >= 0 && _currentLine < widget.lyric.lines.length
            ? widget.lyric.lines[_currentLine]
            : null;
    final frameSampled = !reduced &&
        widget.playing &&
        (current is SyncLyricLine &&
                (current.content.trim().isNotEmpty ||
                    current.length > const Duration(seconds: 5)) ||
            current is LrcLine &&
                current.content.trim().isEmpty &&
                current.length > const Duration(seconds: 5));
    if (frameSampled && !_mediaTicker.isActive) _mediaTicker.start();
    if (!frameSampled) _mediaTicker.stop();
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final followEnabled = !reduced && !_manualScrollActive;
    final blurEnabled = followEnabled &&
        !highContrast &&
        (_preferences?.value.surfaceBlur ?? true);
    if (_wasReduced != null && reduced != _wasReduced && reduced) {
      _cancelFollowEffects();
      _scheduleFollow(immediate: true);
    }
    _wasReduced = reduced;
    final settings = context.watch<LyricViewController>();
    final tileIdentity = (widget.lyric, _currentLine, reduced);
    if (_tileCacheIdentity != tileIdentity) {
      final previous = _tileCache;
      _tileCacheIdentity = tileIdentity;
      _tileCache = [
        for (var index = 0; index < widget.lyric.lines.length; index++)
          if (index < previous.length &&
              identical(previous[index].line, widget.lyric.lines[index]) &&
              previous[index].distance ==
                  (index - _currentLine).abs().clamp(0, 4) &&
              previous[index].reducedMotion == reduced)
            previous[index]
          else
            LyricViewTile(
              key: ValueKey(index),
              line: widget.lyric.lines[index],
              position: _position,
              distance: (index - _currentLine).abs().clamp(0, 4),
              opacity: LyricMotion.opacityForDistance(index - _currentLine),
              reducedMotion: reduced,
              onTap:
                  widget.lyric is PlainLyric ? null : () => _seekToLine(index),
            ),
      ];
    }

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
        return MouseRegion(
          onEnter: (_) => _setPointerReading(true),
          onExit: (_) => _setPointerReading(false),
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) _markManualInteraction();
            },
            onPointerPanZoomStart: (_) =>
                _markManualInteraction(dragging: true),
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
                child: LyricViewportFade(
                  enabled: followEnabled && !highContrast,
                  child: CustomScrollView(
                    key: const ValueKey('vertical-lyric-scroll'),
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(child: SizedBox(height: height * .34)),
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
                                  child: LyricFollowEffects(
                                    clock: _followClock,
                                    transition: followEnabled
                                        ? _followTransitions[index]
                                        : null,
                                    blur:
                                        blurEnabled ? _restBlur[index] ?? 0 : 0,
                                    blurEnabled: blurEnabled &&
                                        _restBlur.containsKey(index),
                                    reading: (_restBlur[index] ?? 0) > 0 ||
                                            _followTransitions
                                                .containsKey(index)
                                        ? _readingClock
                                        : null,
                                    child: _tileCache[index],
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
    _readingClock.dispose();
    _mediaTicker.dispose();
    _followClock.dispose();
    _scrollController.dispose();
    _position.dispose();
    super.dispose();
  }
}
