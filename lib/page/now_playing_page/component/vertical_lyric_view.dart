import 'package:dan_player/lyric/lyric_lookup_status.dart';
import 'dart:async';
import 'package:dan_player/component/touch_gestures.dart';
import 'dart:math' as math;
import 'package:dan_player/component/app_motion.dart';
import 'package:dan_player/rendering_preferences.dart';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/lyric/lyric.dart';
import 'package:dan_player/lyric/plain_lyric.dart';
import 'package:dan_player/lyric/lyric_timeline.dart';
import 'package:dan_player/lyric/lyric_presentation_timeline.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_motion.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_controls.dart';
import 'package:dan_player/page/now_playing_page/component/lyric_view_tile.dart';
import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/play_service/lyric_line_practice.dart';
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
  final lyricViewController = LyricViewController();
  Future<Lyric?>? _practiceFuture;
  int? _practiceSession;
  ValueChanged<LyricLine>? _practiceCallback;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playback = PlayService.instance.playbackService;
    final lyrics = PlayService.instance.lyricService;
    return ChangeNotifierProvider.value(
      value: lyricViewController,
      child: LyricControlsSurface(
        controls: const LyricViewControls(),
        child: ValueListenableBuilder(
          valueListenable: AppSettings.instance.experience,
          builder: (context, experience, _) => ListenableBuilder(
            listenable: lyrics,
            builder: (context, _) => StreamBuilder<PlayerState>(
              stream: playback.playerStateStream,
              initialData: playback.playerState,
              builder: (context, state) {
                final future = lyrics.currLyricFuture;
                final session = playback.playbackSessionToken;
                if (!identical(_practiceFuture, future) ||
                    _practiceSession != session) {
                  _practiceFuture = future;
                  _practiceSession = session;
                  _practiceCallback = (line) async {
                    bool current() =>
                        identical(future, lyrics.currLyricFuture) &&
                        session == playback.playbackSessionToken;
                    if (!current()) return;
                    final lyric = await future;
                    if (!context.mounted || !current() || lyric == null) {
                      return;
                    }
                    final result = practiceLyricLine(
                        playback: playback,
                        lyric: lyric,
                        line: line,
                        playbackSession: session,
                        isCurrentLyric: current);
                    final message = switch (result) {
                      LyricPracticeResult.unavailable => '请先加载一首本地歌曲，再设置片段循环。',
                      LyricPracticeResult.invalidRange => '这句歌词没有至少 1 秒的有效时间范围',
                      LyricPracticeResult.applied => '已将这一句设为 A-B 练习范围',
                      LyricPracticeResult.stale => null,
                    };
                    if (message != null && context.mounted && current()) {
                      showAppNotice(ui(message), context: context);
                    }
                  };
                }
                return VerticalLyricContent(
                  lyricFuture: future,
                  positionStream: playback.positionStream,
                  readPosition: () => playback.position,
                  onSeek: playback.seek,
                  onPractice: _practiceCallback,
                  springLyrics: experience.springLyrics,
                  hidden: DesktopIntegration.instance.isHidden,
                  playing: state.data == PlayerState.playing,
                );
              },
            ),
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

/// Own the control hit targets and focus without rebuilding the media surface
/// when the pointer enters or leaves it. Controls remain mounted across states.
class LyricControlsSurface extends StatefulWidget {
  const LyricControlsSurface(
      {super.key, required this.child, required this.controls});

  final Widget child;
  final Widget controls;

  @override
  State<LyricControlsSurface> createState() => _LyricControlsSurfaceState();
}

class _LyricControlsSurfaceState extends State<LyricControlsSurface> {
  bool _hovering = false;
  bool _controlsFocused = false;
  bool _directControls = false;

  void _hoverChanged(PointerEvent event, bool hovering) {
    setState(() {
      _hovering = hovering;
      if (event.kind == PointerDeviceKind.mouse) _directControls = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _hovering ||
        _controlsFocused ||
        _directControls ||
        ALWAYS_SHOW_LYRIC_VIEW_CONTROLS;
    return MouseRegion(
      onEnter: (event) => _hoverChanged(event, true),
      onExit: (event) => _hoverChanged(event, false),
      onHover: (event) {
        if (_directControls && event.kind == PointerDeviceKind.mouse) {
          setState(() => _directControls = false);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        // Observe direct interaction without claiming the gesture arena: lyric
        // taps, scrolling, long presses and control buttons keep their actions.
        onPointerDown: (event) {
          if (!_directControls &&
              (event.kind == PointerDeviceKind.touch ||
                  event.kind == PointerDeviceKind.stylus ||
                  event.kind == PointerDeviceKind.invertedStylus)) {
            setState(() => _directControls = true);
          }
        },
        child: Material(
          type: MaterialType.transparency,
          child: Stack(children: [
            widget.child,
            Align(
              alignment: Alignment.bottomRight,
              // Keep the menu anchor mounted while its overlay has focus.
              child: Focus(
                onFocusChange: (value) =>
                    setState(() => _controlsFocused = value),
                child: Opacity(
                  opacity: visible ? 1 : 0,
                  child:
                      IgnorePointer(ignoring: !visible, child: widget.controls),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
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
    this.onPractice,
    this.springLyrics = false,
    this.hidden,
    this.playing = false,
  });

  final Future<Lyric?>? lyricFuture;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final ValueChanged<LyricLine>? onPractice;
  final bool springLyrics;
  final ValueListenable<bool>? hidden;
  final bool playing;

  @override
  State<VerticalLyricContent> createState() => _VerticalLyricContentState();
}

class _VerticalLyricContentState extends State<VerticalLyricContent>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;
  bool _entered = false;
  bool _wasVisible = false;
  bool _hasPresented = false;

  void _syncEntrance() {
    final visible =
        TickerMode.valuesOf(context).enabled && widget.hidden?.value != true;
    if (visible == _wasVisible) return;
    _wasVisible = visible;
    _entered = false;
    _hasPresented = false;
    if (visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wasVisible) setState(() => _entered = true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncEntrance();
  }

  void _visibilityChanged() {
    if (mounted) {
      _syncEntrance();
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant VerticalLyricContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hidden != widget.hidden) {
      oldWidget.hidden?.removeListener(_visibilityChanged);
      widget.hidden?.addListener(_visibilityChanged);
      _syncEntrance();
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
              onPractice: widget.onPractice,
              springLyrics: widget.springLyrics,
              hidden: widget.hidden,
              playing: widget.playing,
            );
          } else {
            final label = waiting
                ? ui("正在加载歌词")
                : snapshot.hasError
                    ? ui(lyricLookupStatus(snapshot.error) ?? "歌词加载失败，请切换来源或重试")
                    : ui("无歌词");
            content = Center(
              key: ValueKey(label),
              child: waiting
                  ? _LyricLoadingStatus(
                      label: label,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      animate: active && !reduced,
                    )
                  : Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer)),
            );
          }
          final firstPresentation = !_hasPresented;
          if (_entered) _hasPresented = true;
          return AnimatedSwitcher(
            duration:
                reduced ? Duration.zero : const Duration(milliseconds: 320),
            switchInCurve: firstPresentation
                ? Curves.easeOutCubic
                : const Interval(.5, 1, curve: Curves.easeOutCubic),
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
            child: _entered
                ? content
                : const SizedBox(key: ValueKey('lyric-entry')),
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

/// The pending lyric has a fixed layout box; only its ink bobs while visible.
/// The lyric motion switch, reduced-motion preference and hidden-page policy
/// all stop this one ticker without affecting loading or playback.
class _LyricLoadingStatus extends StatefulWidget {
  const _LyricLoadingStatus({
    required this.label,
    required this.color,
    required this.animate,
  });

  final String label;
  final Color color;
  final bool animate;

  @override
  State<_LyricLoadingStatus> createState() => _LyricLoadingStatusState();
}

class _LyricLoadingStatusState extends State<_LyricLoadingStatus>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _motion.repeat();
  }

  @override
  void didUpdateWidget(covariant _LyricLoadingStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.label,
        liveRegion: true,
        child: ExcludeSemantics(
          child: SizedBox(
            height: 56,
            child: Center(
              child: AnimatedBuilder(
                animation: _motion,
                child: RepaintBoundary(
                  child: Text(widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, color: widget.color)),
                ),
                builder: (context, child) {
                  if (!widget.animate) return child!;
                  // sin² meets both ends at zero velocity: the loop never
                  // snaps back, and the 6px travel reads clearly at high DPI.
                  final wave =
                      math.pow(math.sin(math.pi * _motion.value), 2).toDouble();
                  final scale = 1 + .04 * wave;
                  return Opacity(
                    opacity: .80 + .20 * wave,
                    child: Transform(
                      // Sample one fixed paragraph. Rerasterizing text at
                      // every tiny scale step changes glyph hinting instead
                      // of moving its ink continuously. Include translation
                      // in this matrix so it too uses fractional sampling.
                      alignment: Alignment.center,
                      transform: Matrix4.translationValues(0, -6 * wave, 0)
                        ..scaleByDouble(scale, scale, 1, 1),
                      filterQuality: FilterQuality.medium,
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _motion.dispose();
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
    this.onPractice,
    this.springLyrics = false,
    this.hidden,
    this.playing = false,
    this.suspended = false,
  });

  final Lyric lyric;
  final Stream<double> positionStream;
  final double Function() readPosition;
  final ValueChanged<double> onSeek;
  final ValueChanged<LyricLine>? onPractice;
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
  late LyricOverlapTimeline _overlaps;
  late LyricPresentationTimeline _presentationTimeline;
  Set<int> _singingLines = {};
  final Set<int> _releasingVoices = {};
  bool _presentationEnabled = false;
  int _singingRevision = 0;
  int _visualDistance(int index) => _singingLines.contains(index)
      ? 0
      : (index - _currentLine).abs().clamp(0, 4);
  ({double center, double bottom})? _rowExtent(int index) {
    if (index < 0 || index >= _lineKeys.length) return null;
    final row = _lineKeys[index].currentContext?.findRenderObject();
    if (row is! RenderBox || !row.attached || !row.hasSize) return null;
    final top = RenderAbstractViewport.of(row).getOffsetToReveal(row, 0).offset;
    return (center: top + row.size.height / 2, bottom: top + row.size.height);
  }

  double _blurForIndex(int index, double offset) {
    if (_singingLines.contains(index) || index == _currentLine) return 0;
    final ahead = index - _currentLine;
    if (ahead > 0 && ahead <= 2) return 0;
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasViewportDimension) {
      return LyricMotion.blurForDistance(_visualDistance(index));
    }
    final row = _rowExtent(index);
    final current = _rowExtent(_currentLine);
    if (row == null || current == null) {
      return LyricMotion.blurForDistance(_visualDistance(index));
    }
    final viewportBottom =
        offset + _scrollController.position.viewportDimension;
    final maximum = LyricMotion.blurForDistance(4);
    if (ahead < 0) {
      final span = math.max(1.0, current.center - offset);
      return maximum * ((current.center - row.center) / span).clamp(0.0, 1.0);
    }
    final second = _rowExtent(_currentLine + 2);
    if (second == null) return 0;
    final span = math.max(1.0, viewportBottom - second.center);
    return maximum * ((row.center - second.center) / span).clamp(0.0, 1.0);
  }

  int _sourceGeneration = 0;
  int _followGeneration = 0;
  Timer? _manualScrollTimer;
  bool _manualScrollActive = false;
  bool _readingMode = false;
  int _returnRequest = 0;
  bool _dragging = false;
  Object? _geometryIdentity;
  Object? _presentationIdentity;
  Object? _displayIdentity;
  Object? _fontIdentity;
  bool _fontSettingActive = false;
  bool _snapFontOnLineChange = false;
  bool _fontSnapReleaseScheduled = false;
  bool _fontBandUpdateScheduled = false;
  ({int first, int end})? _builtFontBand;
  bool _settingsAnchor = false;
  bool _resizeAnchor = false;
  double _resizeAnchorScreenTop = 0;
  double _resizeAnchorViewportHeight = 0;
  double _resizeAnchorViewportFraction = .34;
  double? _followTopInset;
  double _followTopFraction = .34;
  int _resizeAnchorGeneration = 0;
  int _resizeAnchorLine = -1;
  bool _contentSettingPending = false;
  bool _presentationSettingPending = false;
  int _settingsAnchorGeneration = 0;
  int _settingsAnchorLine = -1;
  ({double top, double height})? _anchorGeometry;
  double _anchorLeading = 0;
  bool? _wasReduced;
  AppLifecycleState? _lifecycle;
  bool _exiting = false;
  bool _treeVisible = false;
  ValueListenable<RenderingPreferences>? _preferences;
  bool _active = false;
  bool? _blurWasAllowed;
  late final AnimationController _followClock;
  late final AnimationController _voiceBlurClock;
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
  Map<int, Animation<double>> _voiceBlurs = {};
  bool _viewportBlurUpdateScheduled = false;
  double? _fontAnchorCenter;
  Object? _tileCacheIdentity;
  ValueChanged<LyricLine>? _tileCachePractice;
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
    _voiceBlurClock =
        AnimationController(vsync: this, duration: LyricMotion.lineDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _voiceBlurs.isNotEmpty) {
              setState(() => _voiceBlurs = {});
            }
          });
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
    if (_exiting) {
      _settingsAnchor = false;
      _fontSettingActive = false;
      _snapFontOnLineChange = false;
      // Freeze presentation at the painted pose while the parent fades it.
      // Stopping media is not the same as requesting reduced-motion styling.
      _active = false;
      _mediaTicker.stop();
      _followClock.stop();
      _voiceBlurClock.stop();
      _readingClock.stop();
      _sourceGeneration++;
      unawaited(_positionSubscription?.cancel());
      _positionSubscription = null;
      _listeningTo = null;
      _followGeneration++;
      _manualScrollTimer?.cancel();
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        _scrollController.jumpTo(_scrollController.offset);
      }
      return;
    }
    final blurAllowed = (_preferences?.value.surfaceBlur ?? true) &&
        !(MediaQuery.maybeHighContrastOf(context) ?? false);
    final restoreBlur = _blurWasAllowed == false && blurAllowed;
    _blurWasAllowed = blurAllowed;
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
      } else if (restoreBlur) {
        _refreshVoiceBlur();
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
      _settingsAnchor = false;
      _fontSettingActive = false;
      _snapFontOnLineChange = false;
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
    _settingsAnchor = false;
    _followTopInset = null;
    _fontSettingActive = false;
    _snapFontOnLineChange = false;
    _builtFontBand = null;
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
    _overlaps = LyricOverlapTimeline(widget.lyric.lines);
    _presentationTimeline = LyricPresentationTimeline(widget.lyric.lines);
    _releasingVoices.clear();
    _singingLines = _overlaps.activeIndices(_position.value, _currentLine);
    _singingRevision++;
    _scheduleFollow(immediate: true);
  }

  void _subscribeToPosition() {
    if (identical(_listeningTo, widget.positionStream)) return;
    final generation = ++_sourceGeneration;
    _positionSubscription?.cancel();
    _listeningTo = widget.positionStream;
    _positionSubscription = widget.positionStream.listen((position) {
      if (!mounted || generation != _sourceGeneration) return;
      // A queued low-frequency event can predate the latest display frame.
      // Read the same authoritative clock while frame sampling is active;
      // never rewind the word reveal to an older stream sample.
      _receivePosition(_presentationEnabled ? widget.readPosition() : position);
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
    final singing = _overlaps.activeIndices(nextPosition, nextLine);
    final voicesChanged = !setEquals(singing, _singingLines);
    _releasingVoices.removeWhere((index) =>
        singing.contains(index) ||
        widget.lyric.lines[index].start > nextPosition ||
        _presentationTimeline.endFor(index) <= nextPosition);
    if (voicesChanged) {
      _releasingVoices.addAll(_singingLines.difference(singing).where((index) =>
          widget.lyric.lines[index].start <= nextPosition &&
          _presentationTimeline.endFor(index) > nextPosition));
    }
    if (nextLine == _currentLine && !forceFollow && !voicesChanged) {
      _syncPresentationTicker();
      return;
    }
    final seek = (nextLine - _currentLine).abs() > 1;
    final anchorChanged = nextLine != _currentLine;
    if (anchorChanged) _followTopInset = null;
    if (anchorChanged && _fontSettingActive) {
      // Finish the old size before a new line claims the scroll target. The
      // previous visible rows would otherwise keep changing height beneath
      // an already-started seek animation.
      _fontSettingActive = false;
      _snapFontOnLineChange = true;
    }
    if (nextLine != _currentLine || voicesChanged) {
      setState(() {
        _currentLine = nextLine;
        _singingLines = singing;
        _singingRevision++;
      });
    }
    _syncPresentationTicker();
    if (!_manualScrollActive) {
      if (anchorChanged || forceFollow) {
        _scheduleFollow(seek: seek || forceFollow, immediate: immediate);
      } else if (voicesChanged) {
        _refreshVoiceBlur();
      }
    }
  }

  void _syncPresentationTicker() {
    bool rowNeedsFrames(int index) =>
        _presentationTimeline.needsFrames(index, _position.value) &&
        _presentationRowVisible(index);
    final needsFrames = _active &&
        _presentationEnabled &&
        (_singingLines.any(rowNeedsFrames) ||
            _releasingVoices.any(rowNeedsFrames));
    if (needsFrames && !_mediaTicker.isActive) _mediaTicker.start();
    if (!needsFrames) _mediaTicker.stop();
  }

  bool _presentationRowVisible(int index) {
    // Automatic following may be bringing the singer into view. During
    // manual reading only ink inside the held viewport needs display frames;
    // the regular position stream still tracks the song while it is offscreen.
    if (!_manualScrollActive && !_readingMode) return true;
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasViewportDimension) {
      return true;
    }
    final row = _rowExtent(index);
    if (row == null) return false;
    final offset = _scrollController.offset;
    return row.bottom > offset &&
        row.center * 2 - row.bottom <
            offset + _scrollController.position.viewportDimension;
  }

  // A voice can finish (or rejoin after a short seek) while the scroll anchor
  // stays on the same line. Fade only its focus blur: restarting the viewport
  // or lag clock here interrupts an otherwise continuous spring return.
  void _refreshVoiceBlur() {
    if (_restBlur.isEmpty) return;
    final animate = !_motionHidden &&
        !LyricMotion.reducedOf(context) &&
        !(MediaQuery.maybeHighContrastOf(context) ?? false) &&
        (_preferences?.value.surfaceBlur ?? true);
    final next = <int, Animation<double>>{};
    for (final index in _restBlur.keys.toList()) {
      final target = _blurForIndex(index, _scrollController.offset);
      final previousVoice = _voiceBlurs[index];
      if (target == _restBlur[index] && previousVoice == null) continue;
      final flight = _followTransitions[index];
      final begin = previousVoice?.value ??
          flight?.sample(_followClock.value).blur ??
          _restBlur[index]!;
      _restBlur[index] = target;
      if (flight != null) {
        // Its offset still samples the original follow clock. The independent
        // fade owns blur until completion, then hands off to this exact value.
        _followTransitions[index] = LyricFollowTransition(
          distance: flight.distance,
          delay: flight.delay,
          curve: flight.curve,
          initialOffset: flight.initialOffset,
          initialBlur: target,
          finalBlur: target,
        );
      }
      if (animate && begin != target) {
        next[index] = Tween<double>(begin: begin, end: target)
            .chain(CurveTween(curve: LyricMotion.curve))
            .animate(_voiceBlurClock);
      }
    }
    _voiceBlurClock.stop();
    setState(() => _voiceBlurs = next);
    if (next.isNotEmpty) _voiceBlurClock.forward(from: 0);
  }

  VoidCallback? _practiceLine(int index, ValueChanged<LyricLine>? callback) {
    if (callback == null || widget.lyric is PlainLyric) return null;
    final line = widget.lyric.lines[index];
    return () => callback(line);
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

  void _finishContentSetting() {
    _scheduleViewportBlurUpdate();
    if (!_settingsAnchor || !_contentSettingPending) return;
    _contentSettingPending = false;
    _finishSettingsAnchorIfReady();
  }

  void _finishPresentationSetting() {
    _scheduleViewportBlurUpdate();
    if (_fontSettingActive) {
      _fontSettingActive = false;
      if (mounted) setState(() {});
    }
    if (!_settingsAnchor || !_presentationSettingPending) return;
    _presentationSettingPending = false;
    _finishSettingsAnchorIfReady();
  }

  void _finishSettingsAnchorIfReady() {
    if (!_settingsAnchor ||
        _contentSettingPending ||
        _presentationSettingPending) {
      return;
    }
    final generation = _settingsAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _settingsAnchorGeneration) {
        _settingsAnchor = false;
      }
    });
  }

  double? _layoutAnchorOffset(ScrollMetrics dimensions) {
    final setting = _settingsAnchor && _settingsAnchorLine == _currentLine;
    final resizing = _resizeAnchor && _resizeAnchorLine == _currentLine;
    if ((!setting && !resizing) ||
        !_active ||
        _manualScrollActive ||
        _readingMode) {
      return null;
    }
    final geometry = _anchorGeometry;
    if (geometry == null) return null;
    final alignment =
        geometry.height > dimensions.viewportDimension * .7 ? 0.0 : .34;
    if (setting && _fontAnchorCenter != null) {
      return (_anchorLeading +
              geometry.top +
              geometry.height / 2 -
              _fontAnchorCenter!)
          .clamp(dimensions.minScrollExtent, dimensions.maxScrollExtent);
    }
    if (resizing) {
      // The first visible line stays put as the paragraph gains or loses
      // wrapped lines. Re-anchoring at a percentage of the *new* row height
      // would move the whole sentence by that percentage in one frame.
      final screenTop = _resizeAnchorScreenTop +
          (dimensions.viewportDimension - _resizeAnchorViewportHeight) *
              _resizeAnchorViewportFraction;
      return (_anchorLeading + geometry.top - screenTop)
          .clamp(dimensions.minScrollExtent, dimensions.maxScrollExtent);
    }
    if (_followTopInset != null) {
      final targetTop =
          dimensions.viewportDimension * _followTopFraction + _followTopInset!;
      return (_anchorLeading + geometry.top - targetTop)
          .clamp(dimensions.minScrollExtent, dimensions.maxScrollExtent);
    }
    return (_anchorLeading +
            geometry.top -
            (dimensions.viewportDimension - geometry.height) * alignment)
        .clamp(dimensions.minScrollExtent, dimensions.maxScrollExtent);
  }

  void _scheduleFollow({bool immediate = false, bool seek = false}) {
    if (!_active || _readingMode) return;
    // A playback line change or seek takes ownership from a settings reveal.
    _settingsAnchor = false;
    final generation = ++_followGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_active ||
          generation != _followGeneration ||
          _manualScrollActive ||
          _readingMode ||
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
      final viewport = RenderAbstractViewport.of(target);
      final offset = (_followTopInset == null
              ? viewport.getOffsetToReveal(target, alignment).offset
              : viewport.getOffsetToReveal(target, 0).offset -
                  (position.viewportDimension * _followTopFraction +
                      _followTopInset!))
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
    _settingsAnchor = false;
    _followGeneration++;
    final enteringManual = !_manualScrollActive;
    _manualScrollActive = true;
    if (enteringManual) {
      _cancelFollowEffects();
    }
    if (_scrollController.hasClients &&
        _scrollController.position.isScrollingNotifier.value &&
        !dragging) {
      _scrollController.jumpTo(_scrollController.offset);
    }
    // Subsequent touch updates only move the viewport. Rebuilding every lyric
    // row here turns a long-song drag into a whole-column build on every frame.
    if (enteringManual) setState(() {});
    _manualScrollTimer?.cancel();
    if (dragging) _dragging = true;
    if (!_dragging) _resumeAfterGrace();
  }

  void _resumeAfterGrace() {
    if (!_active || _readingMode) return;
    _manualScrollTimer?.cancel();
    _manualScrollTimer = Timer(LyricMotion.manualScrollGrace, () {
      if (!mounted || !_active || _dragging || _readingMode) return;
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
    _voiceBlurClock.stop();
    _readingClock.value = _pointerReading ? 0 : 1;
    _followTransitions = {};
    _restBlur = {};
    _voiceBlurs = {};
    _releasingVoices.clear();
  }

  // The whole lyric remains mounted so seeking and the layout-phase current
  // line anchor retain exact geometry. Only rows near the painted viewport
  // need two shaped font endpoints during a size-setting transition.
  ({int first, int end}) _fontAnimationBand() {
    final count = _lineKeys.length;
    final all = (first: 0, end: count);
    if (!_scrollController.hasClients || count == 0) return all;
    final position = _scrollController.position;
    if (!position.hasViewportDimension ||
        !position.viewportDimension.isFinite ||
        position.viewportDimension <= 0) {
      return all;
    }
    final viewport = position.viewportDimension;
    final lower = math.max(0.0, position.pixels - viewport * .75);
    final upper = position.pixels + viewport * 1.75;

    ({double top, double bottom})? rowGeometry(int index) {
      final row = _lineKeys[index].currentContext?.findRenderObject();
      if (row is! RenderBox || !row.attached || !row.hasSize) return null;
      final data = row.parentData;
      if (data is! FlexParentData) return null;
      final top = _anchorLeading + data.offset.dy;
      return (top: top, bottom: top + row.size.height);
    }

    var missingGeometry = false;
    var low = 0;
    var high = count;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final row = rowGeometry(middle);
      if (row == null) {
        missingGeometry = true;
        break;
      }
      if (row.bottom < lower) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (missingGeometry) return all;
    final first = low;
    low = first;
    high = count;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      final row = rowGeometry(middle);
      if (row == null) return all;
      if (row.top <= upper) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return (first: first, end: low);
  }

  void _scheduleFontBandUpdate() {
    if (!_fontSettingActive || _fontBandUpdateScheduled || !mounted) return;
    _fontBandUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fontBandUpdateScheduled = false;
      if (!mounted || !_fontSettingActive) return;
      if (_fontAnimationBand() != _builtFontBand) setState(() {});
    });
  }

  void _scheduleFontSnapRelease() {
    if (!_snapFontOnLineChange || _fontSnapReleaseScheduled || !mounted) {
      return;
    }
    _fontSnapReleaseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fontSnapReleaseScheduled = false;
      if (!mounted || !_snapFontOnLineChange) return;
      _snapFontOnLineChange = false;
      setState(() {});
    });
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
        i < _lineKeys.length;
        i++) {
      if (top(i) > offset + position.viewportDimension + 48) break;
      rows.add(i);
    }
    return rows;
  }

  void _scheduleViewportBlurUpdate() {
    if (_viewportBlurUpdateScheduled || !_active) return;
    _viewportBlurUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportBlurUpdateScheduled = false;
      if (!mounted ||
          !_active ||
          !_scrollController.hasClients ||
          !_scrollController.position.hasViewportDimension ||
          _manualScrollActive ||
          _readingMode ||
          _followClock.isAnimating) {
        return;
      }
      final offset = _scrollController.offset;
      final blur = <int, double>{
        for (final index in _visibleFollowRows(offset))
          index: _blurForIndex(index, offset),
      };
      if (!mapEquals(blur, _restBlur)) {
        _voiceBlurClock.stop();
        setState(() {
          _voiceBlurs = {};
          _restBlur = blur;
        });
      }
    });
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
    }.toList();
    final transitions = <int, LyricFollowTransition>{};
    final blur = <int, double>{};
    for (final index in rows) {
      final targetBlur = blurAllowed ? _blurForIndex(index, offset) : 0.0;
      blur[index] = targetBlur;
      if (animate && transitions.length < LyricMotion.maximumFollowRows) {
        final previous = _followTransitions[index]?.sample(_followClock.value);
        transitions[index] = LyricFollowTransition(
          distance: offset - _scrollController.offset,
          delay: ((index - _currentLine).abs() * .055).clamp(0, .26),
          curve: curve,
          initialOffset: previous?.offset ?? 0,
          initialBlur: _voiceBlurs[index]?.value ??
              previous?.blur ??
              _restBlur[index] ??
              0,
          finalBlur: targetBlur,
        );
      }
    }
    _followClock.stop();
    _voiceBlurClock.stop();
    setState(() {
      _voiceBlurs = {};
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
    _scheduleFontBandUpdate();
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
    _syncPresentationTicker();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final reduced = _exiting
        ? (_wasReduced ?? false)
        : !_active || _motionHidden || LyricMotion.reducedOf(context);
    _presentationEnabled = !_exiting && !reduced && widget.playing;
    final highContrast = MediaQuery.maybeHighContrastOf(context) ?? false;
    final settings = context.watch<LyricViewController>();
    if (_readingMode != settings.readingMode) {
      _readingMode = settings.readingMode;
      _settingsAnchor = false;
      _manualScrollTimer?.cancel();
      _followGeneration++;
      if (_readingMode) {
        _cancelFollowEffects();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _readingMode &&
              _scrollController.hasClients &&
              _scrollController.position.isScrollingNotifier.value) {
            _scrollController.jumpTo(_scrollController.offset);
          }
        });
      }
    }
    if (_returnRequest != settings.returnRequest) {
      _returnRequest = settings.returnRequest;
      _manualScrollTimer?.cancel();
      _manualScrollActive = false;
      _dragging = false;
      _scheduleFollow(seek: true);
    }
    final followEnabled = !reduced && !_manualScrollActive && !_readingMode;
    final blurEnabled = followEnabled &&
        !highContrast &&
        (_preferences?.value.surfaceBlur ?? true);
    final visibleBlurEnabled = blurEnabled && !settings.fontSizeAdjusting;
    if (!blurEnabled && _voiceBlurs.isNotEmpty) {
      _voiceBlurClock.stop();
      _voiceBlurs = {};
    }
    if (_wasReduced != null && reduced != _wasReduced && reduced) {
      _cancelFollowEffects();
      _scheduleFollow(immediate: true);
    }
    _wasReduced = reduced;
    _syncPresentationTicker();
    final fontIdentity = (settings.lyricFontSize, settings.translationFontSize);
    if (_fontIdentity != null && _fontIdentity != fontIdentity) {
      _snapFontOnLineChange = false;
      _fontSettingActive = !reduced &&
          !settings.directFontSize &&
          !_manualScrollActive &&
          !_readingMode &&
          !_dragging &&
          _currentLine >= 0 &&
          _currentLine < widget.lyric.lines.length;
    }
    _fontIdentity = fontIdentity;
    // A user-held viewport has no current-line anchor. Instantly completing
    // the many offscreen rows above it would shift its visible lyric index.
    if (reduced || _manualScrollActive || _readingMode || _dragging) {
      _fontSettingActive = false;
    }
    final fontBand = _fontSettingActive ? _fontAnimationBand() : null;
    _builtFontBand = fontBand;
    bool reducedAt(int index) =>
        reduced ||
        _snapFontOnLineChange ||
        (fontBand != null &&
            (index < fontBand.first || index >= fontBand.end) &&
            (index - _currentLine).abs() > 4);
    final tileIdentity = (
      widget.lyric,
      _currentLine,
      _singingRevision,
      reduced,
      fontBand,
      widget.onPractice,
      _snapFontOnLineChange
    );
    if (_tileCacheIdentity != tileIdentity) {
      final previous = _tileCache;
      final practice = widget.onPractice;
      final practiceChanged = _tileCachePractice != practice;
      _tileCachePractice = practice;
      _tileCacheIdentity = tileIdentity;
      _tileCache = [
        for (var index = 0; index < widget.lyric.lines.length; index++)
          if (index < previous.length &&
              !practiceChanged &&
              identical(previous[index].line, widget.lyric.lines[index]) &&
              previous[index].distance == _visualDistance(index) &&
              (previous[index].onPractice != null) ==
                  (widget.onPractice != null && widget.lyric is! PlainLyric) &&
              previous[index].reducedMotion == reducedAt(index))
            previous[index]
          else
            LyricViewTile(
              key: ValueKey(index),
              line: widget.lyric.lines[index],
              position: _position,
              distance: _visualDistance(index),
              opacity: LyricMotion.opacityForDistance(_visualDistance(index)),
              reducedMotion: reducedAt(index),
              onContentRevealEnd: _finishContentSetting,
              onPresentationEnd: _finishPresentationSetting,
              onTap:
                  widget.lyric is PlainLyric ? null : () => _seekToLine(index),
              onPractice: _practiceLine(index, practice),
            ),
      ];
    }
    _scheduleFontBandUpdate();
    _scheduleFontSnapRelease();

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        _anchorLeading = height * .34;
        final geometryIdentity = (
          constraints.maxWidth,
          height,
          settings.lyricFontSize,
          settings.translationFontSize,
          settings.lyricTextAlign,
          MediaQuery.textScalerOf(context),
        );
        final presentationIdentity = (
          settings.lyricFontSize,
          settings.translationFontSize,
          settings.lyricTextAlign,
        );
        final displayIdentity = (
          settings.showTranslation,
          settings.showRomanization,
          settings.showTimestamps,
        );
        final geometryChanged =
            _geometryIdentity != null && _geometryIdentity != geometryIdentity;
        final presentationChanged = _presentationIdentity != null &&
            _presentationIdentity != presentationIdentity;
        final previousPresentation =
            _presentationIdentity as (double, double, LyricTextAlign)?;
        final directFontChange = settings.directFontSize &&
            previousPresentation != null &&
            previousPresentation.$3 == settings.lyricTextAlign &&
            (previousPresentation.$1 != settings.lyricFontSize ||
                previousPresentation.$2 != settings.translationFontSize);
        final displayChanged =
            _displayIdentity != null && _displayIdentity != displayIdentity;
        if (displayChanged || presentationChanged) {
          _scheduleViewportBlurUpdate();
          // Row heights change during content reveals and font transitions.
          // ScrollPhysics corrects the
          // position during viewport layout, before the changed frame paints.
          // Post-frame jumpTo would show the old offset for one frame.
          if (_active &&
              !_manualScrollActive &&
              !_readingMode &&
              _currentLine >= 0 &&
              _currentLine < _lineKeys.length &&
              _scrollController.hasClients &&
              !_scrollController.position.isScrollingNotifier.value) {
            if (directFontChange &&
                (!_settingsAnchor || _settingsAnchorLine != _currentLine)) {
              final geometry = _anchorGeometry;
              if (geometry != null) {
                _fontAnchorCenter = _anchorLeading +
                    geometry.top +
                    geometry.height / 2 -
                    _scrollController.offset;
              }
            } else if (!directFontChange) {
              _fontAnchorCenter = null;
            }
            _settingsAnchor = true;
            _contentSettingPending = displayChanged && !reduced;
            _presentationSettingPending = presentationChanged && !reduced;
            _settingsAnchorGeneration++;
            _settingsAnchorLine = _currentLine;
            _followGeneration++;
            _followClock.stop();
            _followTransitions = {};
            if (reduced) {
              _finishSettingsAnchorIfReady();
            }
          } else {
            _settingsAnchor = false;
          }
        } else if (geometryChanged) {
          _scheduleViewportBlurUpdate();
          // A narrower viewport can wrap an earlier, currently offscreen
          // lyric. Its new height moves every visible row before paint. Keep
          // the current line fixed in the same layout pass rather than
          // correcting the scroll position after one displaced frame.
          if (_active &&
              !_manualScrollActive &&
              !_readingMode &&
              _currentLine >= 0 &&
              _currentLine < _lineKeys.length &&
              _scrollController.hasClients) {
            final previousGeometry = _geometryIdentity as (
              double,
              double,
              double,
              double,
              LyricTextAlign,
              TextScaler
            )?;
            final previousAnchor = _anchorGeometry;
            final position = _scrollController.position;
            if (previousGeometry != null && previousAnchor != null) {
              if (_followTopInset == null) {
                _followTopFraction =
                    previousAnchor.height > position.viewportDimension * .7
                        ? 0.0
                        : .34;
                _followTopInset = -previousAnchor.height * _followTopFraction;
              }
              _resizeAnchorViewportFraction =
                  previousAnchor.height > position.viewportDimension * .7
                      ? 0.0
                      : .34;
              _resizeAnchorViewportHeight = position.viewportDimension;
              _resizeAnchorScreenTop = previousGeometry.$2 * .34 +
                  previousAnchor.top -
                  position.pixels;
            } else {
              _resizeAnchorViewportFraction = .34;
              _resizeAnchorViewportHeight = position.viewportDimension;
              _resizeAnchorScreenTop = position.viewportDimension * .34;
            }
            _resizeAnchor = true;
            _resizeAnchorLine = _currentLine;
            final wasFollowing = position.isScrollingNotifier.value;
            final generation = ++_resizeAnchorGeneration;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && generation == _resizeAnchorGeneration) {
                _resizeAnchor = false;
                if (wasFollowing &&
                    _active &&
                    !_manualScrollActive &&
                    !_readingMode &&
                    _scrollController.hasClients) {
                  // The old DrivenScrollActivity still holds offsets from
                  // before reflow. Cancel it at the corrected position before
                  // its next tick can undo this frame's layout-phase anchor.
                  _scrollController.jumpTo(_scrollController.offset);
                  _scheduleFollow();
                }
              }
            });
          } else {
            _resizeAnchor = false;
            _scheduleFollow(immediate: true);
          }
        }
        _geometryIdentity = geometryIdentity;
        _presentationIdentity = presentationIdentity;
        _displayIdentity = displayIdentity;
        return Stack(children: [
          MouseRegion(
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
                  behavior: const DanPlayerScrollBehavior()
                      .copyWith(scrollbars: false, overscroll: false),
                  child: LyricViewportFade(
                    enabled: followEnabled && !highContrast,
                    retainLayer: !reduced && !highContrast,
                    child: CustomScrollView(
                      key: const ValueKey('vertical-lyric-scroll'),
                      physics: _LyricSettingsAnchorPhysics(
                          anchor: _layoutAnchorOffset),
                      controller: _scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                            child: SizedBox(height: height * .34)),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          sliver: SliverToBoxAdapter(
                            child: _LyricAnchorColumn(
                              index: _currentLine,
                              onGeometry: (geometry) =>
                                  _anchorGeometry = geometry,
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
                                      blur: visibleBlurEnabled
                                          ? _restBlur[index] ?? 0
                                          : 0,
                                      blurAnimation: _voiceBlurs[index],
                                      blurEnabled: visibleBlurEnabled &&
                                          _restBlur.containsKey(index),
                                      // Keep clear and blurred lyric rows on
                                      // the same supersampled paint path while
                                      // font size and hover states change.
                                      samplingEnabled: !reduced &&
                                          !highContrast &&
                                          (_preferences?.value.surfaceBlur ??
                                              true),
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
                        SliverToBoxAdapter(
                            child: SizedBox(height: height * .75)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if ((_manualScrollActive || _readingMode) &&
              widget.lyric is! PlainLyric)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Center(
                  child: FilledButton.tonalIcon(
                key: const ValueKey('lyric-return-current'),
                onPressed: settings.returnToCurrent,
                icon: const Icon(Icons.my_location, size: 18),
                label: Text(ui('回到当前歌词'), textAlign: TextAlign.center),
              )),
            ),
        ]);
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
    _voiceBlurClock.dispose();
    _scrollController.dispose();
    _position.dispose();
    super.dispose();
  }
}

/// Reconcile a changing lyric column while the viewport is laying it out.
/// A post-frame scroll correction has already painted the wrong position.
class _LyricSettingsAnchorPhysics extends ScrollPhysics {
  const _LyricSettingsAnchorPhysics({required this.anchor, super.parent});

  final double? Function(ScrollMetrics dimensions) anchor;

  @override
  _LyricSettingsAnchorPhysics applyTo(ScrollPhysics? ancestor) =>
      _LyricSettingsAnchorPhysics(
          anchor: anchor, parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) =>
      anchor(newPosition) ??
      super.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: isScrolling,
        velocity: velocity,
      );
}

/// The column publishes its own child geometry during layout; scroll physics
/// then reads plain numbers instead of asking a descendant RenderBox to lay
/// itself out from the viewport's dimension callback.
class _LyricAnchorColumn extends MultiChildRenderObjectWidget {
  const _LyricAnchorColumn(
      {required this.index, required this.onGeometry, required super.children});

  final int index;
  final ValueChanged<({double top, double height})> onGeometry;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricAnchorColumn(index, onGeometry, Directionality.of(context));

  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderLyricAnchorColumn renderObject) {
    renderObject
      ..index = index
      ..onGeometry = onGeometry
      ..textDirection = Directionality.of(context);
  }
}

class _RenderLyricAnchorColumn extends RenderFlex {
  _RenderLyricAnchorColumn(
      this._index, this.onGeometry, TextDirection direction)
      : super(
          direction: Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          textDirection: direction,
        );

  int _index;
  ValueChanged<({double top, double height})> onGeometry;

  set index(int value) {
    if (_index == value) return;
    _index = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    var child = firstChild;
    for (var i = 0; i < _index && child != null; i++) {
      child = childAfter(child);
    }
    if (child != null && _index >= 0) {
      onGeometry((
        top: (child.parentData! as FlexParentData).offset.dy,
        height: child.size.height,
      ));
    }
  }
}
