import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricLineView extends StatefulWidget {
  const LyricLineView({super.key, this.controller});
  final DesktopLyricController? controller;

  @override
  State<LyricLineView> createState() => _LyricLineViewState();
}

class _LyricLineViewState extends State<LyricLineView>
    with WidgetsBindingObserver {
  final scrollController = ScrollController();
  late DesktopLyricController _controller;
  int _layoutGeneration = 0;
  int _lastClockRevision = -1;
  bool _layoutPending = false;
  bool _reduced = false;
  Object? _legacyIdentity;
  Object? _layoutIdentity;
  int _legacyStartMilliseconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attach();
  }

  void _attach() {
    _controller = widget.controller ?? DesktopLyricController.instance;
    _controller.lyricLine.addListener(_scheduleLineLayout);
    _controller.detailedLyricLine.addListener(_scheduleLineLayout);
    _controller.isPlaying.addListener(_scheduleLineLayout);
    _controller.vertical.addListener(_directionChanged);
    _controller.playbackClock.addListener(_syncScroll);
    _scheduleLineLayout();
  }

  void _detach() {
    _controller.lyricLine.removeListener(_scheduleLineLayout);
    _controller.detailedLyricLine.removeListener(_scheduleLineLayout);
    _controller.isPlaying.removeListener(_scheduleLineLayout);
    _controller.vertical.removeListener(_directionChanged);
    _controller.playbackClock.removeListener(_syncScroll);
  }

  @override
  void didUpdateWidget(LyricLineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _detach();
      _legacyIdentity = null;
      _attach();
    }
  }

  void _directionChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleLineLayout();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  void _syncScroll({bool force = false}) {
    if (!mounted || _layoutPending || !scrollController.hasClients) return;
    final clock = _controller.playbackClock;
    if (_reduced && !force && _lastClockRevision == clock.revision) return;
    _lastClockRevision = clock.revision;
    final detailed = _controller.detailedLyricLine.value;
    final legacy = _controller.lyricLine.value;
    double progress;
    if (detailed != null) {
      progress = detailed.lengthMilliseconds <= 0
          ? 0
          : ((clock.positionMilliseconds - detailed.startMilliseconds) /
                  detailed.lengthMilliseconds)
              .clamp(0.0, 1.0);
    } else {
      final duration = legacy.length.inMilliseconds - 600;
      progress = duration <= 0
          ? 0
          : ((clock.positionMilliseconds - _legacyStartMilliseconds - 300) /
                  duration)
              .clamp(0.0, 1.0);
    }
    final maxExtent = scrollController.position.maxScrollExtent;
    final target = maxExtent * progress;
    if ((scrollController.offset - target).abs() < .5) return;
    scrollController.jumpTo(target);
  }

  void _scheduleLineLayout() {
    final legacy = _controller.lyricLine.value;
    final identity = (legacy.content, legacy.translation, legacy.length);
    if (_legacyIdentity != identity) {
      _legacyIdentity = identity;
      _legacyStartMilliseconds = _controller.playbackClock.positionMilliseconds;
    }
    final generation = ++_layoutGeneration;
    _layoutPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutGeneration) return;
      _layoutPending = false;
      _syncScroll(force: true);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TextDisplayController>();
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    _reduced = MediaQuery.disableAnimationsOf(context) ||
        features.disableAnimations ||
        features.reduceMotion ||
        !TickerMode.valuesOf(context).enabled;
    return LayoutBuilder(builder: (context, constraints) {
      final identity = (
        constraints.biggest,
        _controller.vertical.value,
        settings.lyricFontSize,
        settings.translationFontSize,
        MediaQuery.textScalerOf(context),
        _reduced
      );
      if (_layoutIdentity != identity) {
        _layoutIdentity = identity;
        _scheduleLineLayout();
      }
      return Padding(
        padding: EdgeInsets.symmetric(
            horizontal: _controller.vertical.value ? 8 : 16),
        child: SingleChildScrollView(
          key: const ValueKey('desktop-lyric-scroll'),
          physics: const NeverScrollableScrollPhysics(),
          controller: scrollController,
          scrollDirection:
              _controller.vertical.value ? Axis.vertical : Axis.horizontal,
          child: Center(child: LyricLineDisplayArea(controller: _controller)),
        ),
      );
    });
  }

  @override
  void dispose() {
    ++_layoutGeneration;
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    scrollController.dispose();
    super.dispose();
  }
}
