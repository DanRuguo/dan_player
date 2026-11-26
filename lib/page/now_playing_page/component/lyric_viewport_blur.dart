import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Fixed, progressively blurred regions above a composited lyric viewport.
///
/// On Impeller (`ui.ImageFilter.isShaderFilterSupported`), each configured edge
/// uses a single two-pass separable variable-radius Gaussian `ImageFilter.shader`
/// (`assets/shaders/lyric_viewport_blur.frag`) whose smooth ramp varies
/// continuously per physical scanline—eliminating discrete `ClipRect` strip
/// seams while reducing 24 backdrop passes to 2. Non-shader test/software
/// backends fall back to fine smooth strips with identical boundaries.
class LyricViewportBlur extends StatefulWidget {
  const LyricViewportBlur({
    super.key,
    required this.enabled,
    required this.reading,
    required this.child,
    this.viewOpacity = const AlwaysStoppedAnimation<double>(1),
    this.topFraction = .25,
    this.bottomFraction = .22,
  });

  final bool enabled;
  final double topFraction;
  final double bottomFraction;

  /// The existing reading clock: one is blurred and zero is clear.
  final Animation<double> reading;

  /// Fade the content below the filters, never the backdrop sampling surface.
  final Animation<double> viewOpacity;
  final Widget child;

  static const _fallbackGradientSteps = 24;
  static const _maximumSigma = 8.0;

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loadingProgram;

  /// Pre-warms the separable variable-blur shader on Impeller hosts.
  static Future<ui.FragmentProgram?> ensureShaderLoaded() {
    if (!ui.ImageFilter.isShaderFilterSupported) {
      return Future<ui.FragmentProgram?>.value(null);
    }
    final existing = _program;
    if (existing != null) {
      return Future<ui.FragmentProgram?>.value(existing);
    }
    return _loadingProgram ??= ui.FragmentProgram.fromAsset(
      'assets/shaders/lyric_viewport_blur.frag',
    ).then<ui.FragmentProgram?>((program) {
      _program = program;
      return program;
    }).catchError((Object _) => null);
  }

  /// Smooth blended cubic/quintic ramp matching `lyric_viewport_blur.frag`.
  static double smoothRamp(double t) {
    final p = t.clamp(0.0, 1.0);
    final cubic = p * p * (3.0 - 2.0 * p);
    final quintic = p * p * p * (p * (p * 6.0 - 15.0) + 10.0);
    return cubic + (quintic - cubic) * 0.35;
  }

  @override
  State<LyricViewportBlur> createState() => _LyricViewportBlurState();
}

class _LyricViewportBlurState extends State<LyricViewportBlur> {
  static final ui.ImageFilter _disabledFilter =
      ui.ImageFilter.blur(sigmaX: 0, sigmaY: 0);

  ui.FragmentShader? _topHorizontal;
  ui.FragmentShader? _topVertical;
  ui.FragmentShader? _bottomHorizontal;
  ui.FragmentShader? _bottomVertical;
  int? _cachedTopSigmaKey;
  ui.ImageFilter? _cachedTopFilter;
  int? _cachedBottomSigmaKey;
  ui.ImageFilter? _cachedBottomFilter;

  @override
  void initState() {
    super.initState();
    _initShadersIfAvailable();
  }

  void _initShadersIfAvailable() {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    if (LyricViewportBlur._program != null) {
      return;
    }
    unawaited(
      LyricViewportBlur.ensureShaderLoaded().then((loaded) {
        if (!mounted || loaded == null) return;
        setState(() {});
      }),
    );
  }

  void _disposeShaders() {
    _topHorizontal?.dispose();
    _topVertical?.dispose();
    _bottomHorizontal?.dispose();
    _bottomVertical?.dispose();
    _topHorizontal = null;
    _topVertical = null;
    _bottomHorizontal = null;
    _bottomVertical = null;
    _cachedTopSigmaKey = null;
    _cachedTopFilter = null;
    _cachedBottomSigmaKey = null;
    _cachedBottomFilter = null;
  }

  @override
  void dispose() {
    _disposeShaders();
    super.dispose();
  }

  bool get _hasShaderProgram =>
      ui.ImageFilter.isShaderFilterSupported &&
      LyricViewportBlur._program != null;

  ui.ImageFilter _buildSeparableShaderFilter({
    required bool top,
    required double physicalMaxSigma,
  }) {
    final sigmaKey = (physicalMaxSigma * 256.0).round();
    if (top && _cachedTopSigmaKey == sigmaKey && _cachedTopFilter != null) {
      return _cachedTopFilter!;
    }
    if (!top &&
        _cachedBottomSigmaKey == sigmaKey &&
        _cachedBottomFilter != null) {
      return _cachedBottomFilter!;
    }

    final program = LyricViewportBlur._program!;
    final topFlag = top ? 1.0 : 0.0;
    final quantizedSigma = sigmaKey / 256.0;

    if (top) {
      _topHorizontal?.dispose();
      _topVertical?.dispose();
    } else {
      _bottomHorizontal?.dispose();
      _bottomVertical?.dispose();
    }

    // Uniforms 0 & 1 (`vec2 u_size`) are populated by Impeller automatically.
    final horizontal = program.fragmentShader()
      ..setFloat(2, quantizedSigma)
      ..setFloat(3, 0.0)
      ..setFloat(4, topFlag);
    final vertical = program.fragmentShader()
      ..setFloat(2, quantizedSigma)
      ..setFloat(3, 1.0)
      ..setFloat(4, topFlag);

    final composed = ui.ImageFilter.compose(
      outer: ui.ImageFilter.shader(vertical),
      inner: ui.ImageFilter.shader(horizontal),
    );

    if (top) {
      _topHorizontal = horizontal;
      _topVertical = vertical;
      _cachedTopSigmaKey = sigmaKey;
      _cachedTopFilter = composed;
    } else {
      _bottomHorizontal = horizontal;
      _bottomVertical = vertical;
      _cachedBottomSigmaKey = sigmaKey;
      _cachedBottomFilter = composed;
    }
    return composed;
  }

  double _fraction(double value, double fallback) =>
      value.isFinite ? value.clamp(0.0, .45).toDouble() : fallback;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth ||
              !constraints.hasBoundedHeight ||
              constraints.maxWidth <= 0 ||
              constraints.maxHeight <= 0) {
            return FadeTransition(
              opacity: widget.viewOpacity,
              child: widget.child,
            );
          }
          final height = constraints.maxHeight;
          final dpr = View.of(context).devicePixelRatio;
          final identityRadius = .1 / dpr;
          final topFraction = _fraction(widget.topFraction, .25);
          final bottomFraction = _fraction(widget.bottomFraction, .22);
          return ClipRect(
            child: AnimatedBuilder(
              animation:
                  widget.enabled && (topFraction > 0 || bottomFraction > 0)
                      ? Listenable.merge([widget.reading, widget.viewOpacity])
                      : const AlwaysStoppedAnimation<double>(0),
              child: FadeTransition(
                opacity: widget.viewOpacity,
                child: widget.child,
              ),
              builder: (context, child) {
                final sigma = widget.enabled
                    ? LyricViewportBlur._maximumSigma *
                        widget.reading.value.clamp(0.0, 1.0) *
                        widget.viewOpacity.value.clamp(0.0, 1.0)
                    : 0.0;
                final useShader = _hasShaderProgram;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    if (useShader) ...[
                      if (height * topFraction > 0)
                        _shaderZone(
                          extent: height * topFraction,
                          sigma: sigma,
                          dpr: dpr,
                          top: true,
                          identityRadius: identityRadius,
                        ),
                      if (height * bottomFraction > 0)
                        _shaderZone(
                          extent: height * bottomFraction,
                          sigma: sigma,
                          dpr: dpr,
                          top: false,
                          identityRadius: identityRadius,
                        ),
                    ] else ...[
                      ..._fallbackBands(
                        height * topFraction,
                        sigma,
                        top: true,
                        identityRadius: identityRadius,
                      ),
                      ..._fallbackBands(
                        height * bottomFraction,
                        sigma,
                        top: false,
                        identityRadius: identityRadius,
                      ),
                    ],
                  ],
                );
              },
            ),
          );
        },
      );

  Widget _shaderZone({
    required double extent,
    required double sigma,
    required double dpr,
    required bool top,
    required double identityRadius,
  }) {
    final active = widget.enabled && sigma >= identityRadius;
    return Positioned(
      key: ValueKey(('lyric-blur-shader', top)),
      left: 0,
      right: 0,
      top: top ? 0 : null,
      bottom: top ? null : 0,
      height: extent,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: ClipRect(
            child: BackdropFilter(
              enabled: active,
              filter: active
                  ? _buildSeparableShaderFilter(
                      top: top,
                      physicalMaxSigma: sigma * dpr,
                    )
                  : _disabledFilter,
              blendMode: BlendMode.src,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _fallbackBands(
    double extent,
    double sigma, {
    required bool top,
    required double identityRadius,
  }) sync* {
    if (extent <= 0) return;
    const steps = LyricViewportBlur._fallbackGradientSteps;
    for (var index = 0; index < steps; index++) {
      final near = extent * index / steps;
      final far = extent * (index + 1) / steps;
      final progress = (index + .5) / steps;
      final radius = sigma * LyricViewportBlur.smoothRamp(progress);
      final active = widget.enabled && radius >= identityRadius;
      yield Positioned(
        key: ValueKey((top, index)),
        left: 0,
        right: 0,
        top: top ? extent - far : null,
        bottom: top ? null : extent - far,
        height: far - near,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: ClipRect(
              child: BackdropFilter(
                enabled: active,
                filter: active
                    ? ui.ImageFilter.blur(sigmaX: radius, sigmaY: radius)
                    : _disabledFilter,
                blendMode: BlendMode.src,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
    }
  }
}
