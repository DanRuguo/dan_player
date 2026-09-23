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
  const FullWidthSpectrum(
      {super.key, this.height = 72.0, this.activity, this.shouldListen});

  final double height;
  final Listenable? activity;
  final bool Function(RenderingPreferences)? shouldListen;

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
      activity: activity,
      shouldListen: shouldListen,
    );
  }
}

class LyricPageSpectrum extends StatelessWidget {
  const LyricPageSpectrum({super.key, required this.height, this.coverVisible});
  final double height;
  final ValueListenable<bool>? coverVisible;

  bool _visible(RenderingPreferences preferences) =>
      lyricSpectrumVisibleAt(preferences, LyricSpectrumPlacement.progress,
          coverVisible: coverVisible?.value ?? true);

  @override
  Widget build(BuildContext context) {
    Widget buildSpectrum(BuildContext context) =>
        _visible(RenderingPreferencesScope.of(context))
            ? FullWidthSpectrum(
                height: height, activity: coverVisible, shouldListen: _visible)
            : const SizedBox.shrink();
    return coverVisible == null
        ? buildSpectrum(context)
        : ValueListenableBuilder<bool>(
            valueListenable: coverVisible!,
            builder: (context, _, __) => buildSpectrum(context));
  }
}

bool lyricSpectrumVisibleAt(
        RenderingPreferences preferences, LyricSpectrumPlacement location,
        {bool coverVisible = true}) =>
    preferences.lyricSpectrum &&
    (preferences.lyricSpectrumPlacement == LyricSpectrumPlacement.cover &&
            coverVisible
        ? location == LyricSpectrumPlacement.cover
        : location == LyricSpectrumPlacement.progress);

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
    this.coverRect,
    this.activity,
    this.shouldListen,
  }) : assert(height >= 0);

  final int maximumBars;
  final Stream<List<double>> samples;
  final List<double> Function() readLevels;
  final double height;
  final ValueListenable<bool>? hidden;
  final Rect? coverRect;
  final Listenable? activity;
  final bool Function(RenderingPreferences)? shouldListen;

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
  bool _attached = true;
  int _sourceGeneration = 0;
  int _activationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    widget.hidden?.addListener(_syncActivity);
    widget.activity?.addListener(_syncActivity);
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
    if (!identical(oldWidget.activity, widget.activity)) {
      oldWidget.activity?.removeListener(_syncActivity);
      widget.activity?.addListener(_syncActivity);
    }
    _syncActivity();
  }

  void _syncActivity() {
    if (!mounted) return;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    final preferences = _preferences?.value ?? const RenderingPreferences();
    final enabled = _attached &&
        (widget.shouldListen?.call(preferences) ?? true) &&
        _mediaAllowsMotion &&
        !features.disableAnimations &&
        !features.reduceMotion &&
        preferences.allowsVisualUpdates(
          lifecycle: _lifecycle,
          treeVisible: _treeVisible,
          nativeHidden: widget.hidden?.value ?? false,
        );
    // Native hide and preference changes may arrive without another frame.
    // Release native FFT demand synchronously under the current policy.
    final activation = ++_activationGeneration;
    if (enabled &&
        widget.activity != null &&
        !identical(_listeningTo, widget.samples)) {
      // A responsive switch can retain both fading surfaces. Release all old
      // owners first, then attach the new owner once, independent of listener
      // registration order. This schedules no timer or animation frame.
      _detach();
      try {
        _setLevels(widget.readLevels());
      } catch (_) {
        _setLevels(const []);
      }
      scheduleMicrotask(() {
        if (mounted && activation == _activationGeneration) {
          _syncSubscription(true);
        }
      });
    } else {
      _syncSubscription(enabled);
    }
    if (_enabled != enabled) setState(() => _enabled = enabled);
  }

  @override
  void didChangeAccessibilityFeatures() => _syncActivity();

  @override
  void deactivate() {
    _attached = false;
    _activationGeneration++;
    _syncSubscription(false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _syncActivity();
  }

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
              painter: widget.coverRect == null
                  ? FrequencySpectrumPainter(
                      levels: _levels,
                      maximumBars: widget.maximumBars,
                      pixelRatio: MediaQuery.devicePixelRatioOf(context),
                      startColor: scheme.primary,
                      endColor: scheme.tertiary,
                    )
                  : CoverSpectrumPainter(
                      levels: _levels,
                      coverRect: widget.coverRect!,
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
    widget.activity?.removeListener(_syncActivity);
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
    this.fixedBarCount,
    this.sampleStart = 0,
    this.sampleEnd = 1,
  }) : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Color startColor;
  final Color endColor;
  final double pixelRatio;
  final int maximumBars;
  final int? fixedBarCount;
  final double sampleStart;
  final double sampleEnd;
  final _paint = Paint();
  Size? _geometrySize;
  List<_SpectrumBar> _bars = const [];
  _SpectrumMesh? _mesh;

  double sampleAt(double position) {
    final frame = levels.value;
    if (frame.isEmpty) return 0;
    final safePosition = position.isFinite ? position.clamp(0.0, 1.0) : 0.0;
    final scaled = (sampleStart + (sampleEnd - sampleStart) * safePosition)
            .clamp(0.0, 1.0) *
        (frame.length - 1);
    final left = scaled.floor();
    final right = math.min(left + 1, frame.length - 1);
    final fraction = scaled - left;
    return _safeLevel(frame[left]) * (1.0 - fraction) +
        _safeLevel(frame[right]) * fraction;
  }

  void _layoutBars(Size size) {
    if (size == _geometrySize) return;
    final count =
        (fixedBarCount ?? (size.width / 5 * maximumBars / 112).floor())
            .clamp(1, maximumBars);
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
      oldDelegate.fixedBarCount != fixedBarCount ||
      oldDelegate.sampleStart != sampleStart ||
      oldDelegate.sampleEnd != sampleEnd ||
      oldDelegate.pixelRatio != pixelRatio ||
      oldDelegate.endColor != endColor;
}

/// Four bounded strips share one spectrum subscription and repaint listener.
/// Each strip reuses the existing batched rounded-bar mesh; density is a total
/// budget around the cover, never a separate budget per edge.
class CoverSpectrumPainter extends CustomPainter {
  CoverSpectrumPainter({
    required this.levels,
    required this.coverRect,
    required this.startColor,
    required this.endColor,
    this.pixelRatio = 1,
    this.maximumBars = 112,
  }) : super(repaint: levels);

  final ValueListenable<List<double>> levels;
  final Rect coverRect;
  final Color startColor;
  final Color endColor;
  final double pixelRatio;
  final int maximumBars;
  Size? _layoutSize;
  List<FrequencySpectrumPainter> _edges = const [];

  @visibleForTesting
  int get barCount => _edges.fold(0, (sum, edge) => sum + edge.fixedBarCount!);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        !coverRect.isFinite ||
        coverRect.isEmpty) {
      return;
    }
    final inset = math.min(16.0, coverRect.shortestSide * .05);
    final width = coverRect.width - inset * 2;
    final height = coverRect.height - inset * 2;
    final gap = math.min(4.0, size.shortestSide * .012);
    final room = [
      coverRect.top - gap,
      size.width - coverRect.right - gap,
      size.height - coverRect.bottom - gap,
      coverRect.left - gap,
    ];
    if (width <= 0 || height <= 0 || room.any((space) => space <= 0)) return;
    if (_layoutSize != size) {
      final budget = maximumBars.clamp(4, 112);
      final count =
          ((width + height) * 2 / 5 * budget / 112).floor().clamp(4, budget);
      _edges = List.generate(4, (edge) {
        final edgeCount = count ~/ 4 + (edge < count % 4 ? 1 : 0);
        return FrequencySpectrumPainter(
            levels: levels,
            startColor: startColor,
            endColor: endColor,
            pixelRatio: pixelRatio,
            maximumBars: edgeCount,
            fixedBarCount: edgeCount,
            sampleStart: edge / 4,
            sampleEnd: (edge + 1) / 4);
      }, growable: false);
      _layoutSize = size;
    }
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var edge = 0; edge < 4; edge++) {
      canvas.save();
      final amplitude = room[edge];
      switch (edge) {
        case 0:
          canvas.translate(coverRect.left + inset, 0);
        case 1:
          canvas.translate(size.width, coverRect.top + inset);
          canvas.rotate(math.pi / 2);
        case 2:
          canvas.translate(coverRect.right - inset, size.height);
          canvas.rotate(math.pi);
        case 3:
          canvas.translate(0, coverRect.bottom - inset);
          canvas.rotate(-math.pi / 2);
      }
      _edges[edge].paint(canvas, Size(edge.isEven ? width : height, amplitude));
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverSpectrumPainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.coverRect != coverRect ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor ||
      oldDelegate.pixelRatio != pixelRatio ||
      oldDelegate.maximumBars != maximumBars;
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
