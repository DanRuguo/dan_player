import 'dart:async';
import 'dart:math' as math;

import 'package:dan_player/play_service/play_service.dart';
import 'package:dan_player/desktop_integration.dart';
import 'package:dan_player/rendering_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:desktop_lyric/ui_language.dart';

class FullWidthSpectrum extends StatelessWidget {
  const FullWidthSpectrum({super.key, this.height = 72.0});

  final double height;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final playback = PlayService.instance.playbackService;
    return FullWidthSpectrumView(
      height: height,
      samples: playback.frequencySpectrumStream,
      readLevels: () => playback.frequencySpectrumLevels,
      hidden: DesktopIntegration.instance.isHidden,
    );
  }
}

/// The real spectrum view, separated from the player singleton so rendering
/// and subscription lifetimes can also be tested without opening native audio.
/// Samples are already smoothed by BASS; this view never fabricates frequencies
/// or advances a separate animation clock.
class FullWidthSpectrumView extends StatefulWidget {
  const FullWidthSpectrumView({
    super.key,
    required this.samples,
    required this.readLevels,
    this.height = 72,
    this.hidden,
  }) : assert(height >= 0);

  final Stream<List<double>> samples;
  final List<double> Function() readLevels;
  final double height;
  final ValueListenable<bool>? hidden;

  @override
  State<FullWidthSpectrumView> createState() => _FullWidthSpectrumViewState();
}

class _FullWidthSpectrumViewState extends State<FullWidthSpectrumView>
    with WidgetsBindingObserver {
  final _levels = ValueNotifier<List<double>>(const []);
  StreamSubscription<List<double>>? _subscription;
  Stream<List<double>>? _listeningTo;
  AppLifecycleState? _lifecycle;
  ValueListenable<RenderingPreferences>? _preferences;
  bool _treeVisible = false;
  bool _mediaAllowsMotion = false;
  bool _enabled = false;
  int _sourceGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
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
    _mediaAllowsMotion =
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _syncActivity();
  }

  @override
  void didUpdateWidget(FullWidthSpectrumView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hidden, widget.hidden)) {
      oldWidget.hidden?.removeListener(_syncActivity);
      widget.hidden?.addListener(_syncActivity);
    }
    _syncActivity();
  }

  void _syncActivity() {
    if (!mounted) return;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final enabled = _mediaAllowsMotion &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        (_preferences?.value ?? const RenderingPreferences())
            .allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: _treeVisible,
          nativeHidden: widget.hidden?.value ?? false,
        );
    // Native hide and preference changes may arrive without another frame.
    // Release/resume native FFT demand synchronously under the current policy.
    _syncSubscription(enabled);
    if (_enabled != enabled) setState(() => _enabled = enabled);
  }

  @override
  void didChangeAccessibilityFeatures() => _syncActivity();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    _lifecycle = state;
    _syncActivity();
  }

  void _setLevels(List<double> values) {
    final previous = _levels.value;
    var changed = values.length != previous.length;
    if (!changed) {
      for (var index = 0; index < values.length; index++) {
        if (_safeLevel(values[index]) != previous[index]) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;
    // Take a snapshot even when an external producer reuses its input buffer.
    // Unchanged frames (including paused zeroes) need no allocation or paint.
    _levels.value = List<double>.unmodifiable(values.map(_safeLevel));
  }

  void _detach() {
    _sourceGeneration++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _listeningTo = null;
  }

  void _syncSubscription(bool enabled) {
    if (!enabled) {
      if (_listeningTo != null) _detach();
      _setLevels(const []);
      return;
    }
    if (identical(_listeningTo, widget.samples)) return;
    _detach();
    _listeningTo = widget.samples;
    final generation = _sourceGeneration;
    try {
      _setLevels(widget.readLevels());
    } catch (_) {
      _setLevels(const []);
    }
    _subscription = widget.samples.listen(
      (values) {
        if (mounted && generation == _sourceGeneration) _setLevels(values);
      },
      onError: (Object _, StackTrace __) {
        if (mounted && generation == _sourceGeneration) _setLevels(const []);
      },
      onDone: () {
        if (mounted && generation == _sourceGeneration) _setLevels(const []);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: _enabled ? ui("当前歌曲实时频谱") : ui("音频频谱，动态效果已暂停"),
      child: IgnorePointer(
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: FrequencySpectrumPainter(
                levels: _levels,
                startColor: scheme.primary,
                endColor: scheme.tertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.hidden?.removeListener(_syncActivity);
    _preferences?.removeListener(_syncActivity);
    _detach();
    _levels.dispose();
    super.dispose();
  }
}

/// Keeps the frequency display directly above, not behind, the seek control.
/// Both responsive playing pages share the same ordering and 24px track inset.
/// The spectrum cannot intercept touch/keyboard events intended for progress.
class SpectrumProgressSection extends StatelessWidget {
  const SpectrumProgressSection({
    super.key,
    required this.spectrum,
    required this.progress,
  });

  final Widget spectrum;
  final Widget progress;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: IgnorePointer(child: spectrum),
        ),
        progress,
      ],
    );
  }
}

double _safeLevel(double value) => value.isFinite ? value.clamp(0.0, 1.0) : 0;

/// FFT arrivals repaint this surface directly, without rebuilding or laying out
/// a widget per 33ms sample. Horizontal geometry and the shader survive frames.
class FrequencySpectrumPainter extends CustomPainter {
  FrequencySpectrumPainter({
    required this.levels,
    required this.startColor,
    required this.endColor,
  }) : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color startColor;
  final Color endColor;
  final _paint = Paint();
  Size? _geometrySize;
  List<_SpectrumBar> _bars = const [];

  double sampleAt(double position) {
    final frame = levels.value;
    if (frame.isEmpty) return 0;
    final safePosition = position.isFinite ? position.clamp(0.0, 1.0) : 0.0;
    final scaled = safePosition * (frame.length - 1);
    final left = scaled.floor();
    final right = math.min(left + 1, frame.length - 1);
    final fraction = scaled - left;
    return _safeLevel(frame[left]) * (1.0 - fraction) +
        _safeLevel(frame[right]) * fraction;
  }

  void _layoutBars(Size size) {
    if (size == _geometrySize) return;
    final count = (size.width / 5).floor().clamp(1, 112);
    final gap = math.min(2.0, size.width / count * .4);
    final barWidth = (size.width - gap * (count - 1)) / count;
    _bars = List.generate(count, (index) {
      final normalized = count == 1 ? .5 : index / (count - 1);
      final edgeFade = math.sin(math.pi * normalized).clamp(.18, 1.0);
      return _SpectrumBar(
        left: index * (barWidth + gap),
        width: barWidth,
        position: normalized,
        edgeFade: edgeFade,
      );
    }, growable: false);
    _paint.shader = LinearGradient(
      begin: Alignment.bottomLeft,
      end: Alignment.topRight,
      colors: [startColor, endColor],
    ).createShader(Offset.zero & size);
    _geometrySize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    _layoutBars(size);
    final baselineHeight = math.min(2.0, size.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final bar in _bars) {
      final height = math.max(
        baselineHeight,
        size.height * sampleAt(bar.position) * bar.edgeFade,
      );
      _paint.color = Colors.white.withValues(alpha: .35 + bar.edgeFade * .65);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bar.left, size.height - height, bar.width, height),
          Radius.circular(bar.width / 2),
        ),
        _paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FrequencySpectrumPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor;
}

class _SpectrumBar {
  const _SpectrumBar({
    required this.left,
    required this.width,
    required this.position,
    required this.edgeFade,
  });

  final double left;
  final double width;
  final double position;
  final double edgeFade;
}
