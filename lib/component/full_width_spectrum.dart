import 'dart:typed_data';
import 'dart:ui' as graphics;
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
      maximumBars:
          RenderingPreferencesScope.of(context).spectrumDensity.maximumBars,
      samples: playback.frequencySpectrumStream,
      readLevels: () => playback.frequencySpectrumLevels,
      hidden: DesktopIntegration.instance.isHidden,
    );
  }
}

class LyricPageSpectrum extends StatelessWidget {
  const LyricPageSpectrum({super.key, required this.height});
  final double height;
  @override
  Widget build(BuildContext context) =>
      RenderingPreferencesScope.of(context).lyricSpectrum
          ? FullWidthSpectrum(height: height)
          : const SizedBox.shrink();
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
    this.maximumBars = 112,
    this.hidden,
  }) : assert(height >= 0);

  final int maximumBars;
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
                maximumBars: widget.maximumBars,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
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
    this.pixelRatio = 1,
    this.maximumBars = 112,
  }) : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color startColor;
  final Color endColor;
  final double pixelRatio;
  final int maximumBars;
  final _paint = Paint();
  Size? _geometrySize;
  List<_SpectrumBar> _bars = const [];
  _SpectrumMesh? _mesh;

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
    final count =
        (size.width / 5 * maximumBars / 112).floor().clamp(1, maximumBars);
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
    _mesh = _SpectrumMesh(_bars, .5 / pixelRatio);
    _geometrySize = size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    _layoutBars(size);
    final baselineHeight = math.min(2.0, size.height);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (size.height >= 2 && _bars.first.width >= 2) {
      _paint.color = Colors.white;
      _mesh!.paint(canvas, size, _bars, sampleAt, _paint);
    } else {
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
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FrequencySpectrumPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) ||
      oldDelegate.startColor != startColor ||
      oldDelegate.maximumBars != maximumBars ||
      oldDelegate.pixelRatio != pixelRatio ||
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

/// One indexed draw instead of one gradient draw call per rounded bar. Each
/// contour has an explicit one-pixel coverage fringe, so batching retains soft
/// edges, the diagonal theme gradient and the per-bar edge attenuation.
class _SpectrumMesh {
  final double fringe;
  static const _steps = 8;
  static const _ring = 4 * (_steps + 1);
  static const _verticesPerBar = _ring * 2;
  final Float32List positions;
  final Int32List colors;
  final Uint16List indices;
  static final _directions = [
    for (var corner = 0; corner < 4; corner++)
      for (var step = 0; step <= _steps; step++)
        (
          x: math.cos((-math.pi / 2) +
              corner * math.pi / 2 +
              step * math.pi / (2 * _steps)),
          y: math.sin((-math.pi / 2) +
              corner * math.pi / 2 +
              step * math.pi / (2 * _steps))
        ),
  ];
  _SpectrumMesh(List<_SpectrumBar> bars, this.fringe)
      : positions = Float32List(bars.length * _verticesPerBar * 2),
        colors = Int32List(bars.length * _verticesPerBar),
        indices = Uint16List(bars.length * ((_ring - 2) * 3 + _ring * 6)) {
    var index = 0;
    for (var bar = 0; bar < bars.length; bar++) {
      final base = bar * _verticesPerBar;
      final alpha = ((.35 + bars[bar].edgeFade * .65) * 255).round();
      for (var p = 0; p < _ring; p++) {
        colors[base + p] = (alpha << 24) | 0xffffff;
        colors[base + _ring + p] = 0x00ffffff;
      }
      for (var p = 1; p < _ring - 1; p++) {
        indices[index++] = base;
        indices[index++] = base + p;
        indices[index++] = base + p + 1;
      }
      for (var p = 0; p < _ring; p++) {
        final next = (p + 1) % _ring;
        for (final v in [p, next, p + _ring, next, next + _ring, p + _ring]) {
          indices[index++] = base + v;
        }
      }
    }
  }
  void paint(Canvas canvas, Size size, List<_SpectrumBar> bars,
      double Function(double) sample, Paint paint) {
    for (var bar = 0; bar < bars.length; bar++) {
      final geometry = bars[bar];
      final height = math.max(
          2.0, size.height * sample(geometry.position) * geometry.edgeFade);
      final radius = math.min(geometry.width, height) / 2;
      for (var p = 0; p < _ring; p++) {
        final corner = p ~/ (_steps + 1);
        final cx =
            geometry.left + (corner < 2 ? geometry.width - radius : radius);
        final cy = size.height -
            (corner == 0 || corner == 3 ? height - radius : radius);
        final direction = _directions[p];
        for (var outer = 0; outer < 2; outer++) {
          final r = radius + (outer == 0 ? -fringe : fringe);
          final offset = (bar * _verticesPerBar + outer * _ring + p) * 2;
          positions[offset] = cx + direction.x * r;
          positions[offset + 1] = cy + direction.y * r;
        }
      }
    }
    final vertices = graphics.Vertices.raw(
        graphics.VertexMode.triangles, positions,
        colors: colors, indices: indices);
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
    vertices.dispose();
  }
}
