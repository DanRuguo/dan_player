import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Per-row paint parameters. Only the leaf filter depends on this scope, so a
/// follow tick does not rebuild or relayout the cached paragraph subtree.
class LyricFractionalFilterScope extends InheritedWidget {
  const LyricFractionalFilterScope(
      {super.key,
      required this.sigma,
      required this.dpr,
      required this.enabled,
      required this.repaintToken,
      required super.child});
  final double sigma;
  final double dpr;
  final bool enabled;
  final Object repaintToken;
  @override
  bool updateShouldNotify(LyricFractionalFilterScope oldWidget) =>
      enabled != oldWidget.enabled ||
      (enabled &&
          (sigma != oldWidget.sigma ||
              dpr != oldWidget.dpr ||
              repaintToken != oldWidget.repaintToken));
}

class ScopedLyricFractionalFilter extends StatelessWidget {
  const ScopedLyricFractionalFilter({
    super.key,
    required this.child,
    this.retainSourceBounds = false,
  });
  final Widget child;
  final bool retainSourceBounds;
  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LyricFractionalFilterScope>();
    if (scope == null) return child;
    return LyricFractionalFilter(
        sigma: scope.sigma,
        dpr: scope.dpr,
        enabled: scope.enabled,
        retainSourceBounds: retainSourceBounds,
        repaint: scope.enabled ? Scrollable.maybeOf(context)?.position : null,
        repaintToken: scope.repaintToken,
        child: child);
  }
}

/// Paint a row's source and inverse sampling matrix in one display list.
///
/// Windows Impeller culls nested display lists before an enclosing layer's
/// inverse filter projection. A supersampled TransformLayer can therefore lose
/// glyphs near the right window edge. Recording saveLayer, scale, and the actual
/// paragraph paints together lets the display list map their output bounds.
class LyricFractionalFilter extends SingleChildRenderObjectWidget {
  const LyricFractionalFilter({
    super.key,
    required this.sigma,
    required this.dpr,
    this.enabled = true,
    this.samplingScale = 1.5,
    this.repaintToken,
    this.repaint,
    this.retainSourceBounds = false,
    super.child,
  })  : assert(sigma >= 0 && sigma < double.infinity),
        assert(samplingScale >= 1 && samplingScale < double.infinity),
        assert(dpr > 0 && dpr < double.infinity);

  final double sigma;
  final double dpr;
  final bool enabled;

  /// Kept constant across font dragging and hover so neither transition
  /// changes the paragraph's raster sampling path.
  final double samplingScale;
  final Object? repaintToken;
  final Listenable? repaint;

  /// Retain the source coverage while attached ruby strokes animate. The
  /// transparent source guard is painted inside the isolated sampling layer.
  final bool retainSourceBounds;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricFractionalFilter(
          sigma, dpr, enabled, samplingScale, repaint, retainSourceBounds);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLyricFractionalFilter)
      ..sigma = sigma
      ..dpr = dpr
      ..enabled = enabled
      ..samplingScale = samplingScale
      ..repaintToken = repaintToken
      ..repaint = repaint
      ..retainSourceBounds = retainSourceBounds;
  }
}

/// Local translation that completes a physically pixel-aligned source origin.
/// getTransformTo(null) supplies logical global coordinates; [dpr] converts
/// those to physical pixels. Undo the axis scale to express the remainder in
/// the same local coordinates as the blur and matrix filter.
@visibleForTesting
Offset lyricFilterRemainder(Matrix4 logicalToGlobal, double dpr) {
  final m = logicalToGlobal.storage;
  if (m.any((value) => !value.isFinite) ||
      m[1] != 0 ||
      m[2] != 0 ||
      m[3] != 0 ||
      m[4] != 0 ||
      m[6] != 0 ||
      m[7] != 0 ||
      m[8] != 0 ||
      m[9] != 0 ||
      m[11] != 0 ||
      m[15] != 1 ||
      m[0] == 0 ||
      m[5] == 0) {
    // Rotation/skew/perspective already bypass integral-CTM optimization.
    return Offset.zero;
  }
  final x = m[12] * dpr;
  final y = m[13] * dpr;
  return Offset(
    (x - x.roundToDouble()) / (m[0] * dpr),
    (y - y.roundToDouble()) / (m[5] * dpr),
  );
}

class _RenderLyricFractionalFilter extends RenderProxyBox {
  _RenderLyricFractionalFilter(this._sigma, this._dpr, this._enabled,
      this._samplingScale, this._repaint, this._retainSourceBounds);
  double _sigma;
  double _dpr;
  bool _enabled;
  double _samplingScale;
  Object? _repaintToken;
  Listenable? _repaint;
  bool _retainSourceBounds;
  final _sourceGuard = ui.Paint()
    ..color = const ui.Color(0x00000000)
    ..blendMode = ui.BlendMode.src;

  set retainSourceBounds(bool value) {
    if (_retainSourceBounds == value) return;
    _retainSourceBounds = value;
    markNeedsPaint();
  }

  void _onAncestorMotion() {
    if (_enabled) markNeedsPaint();
  }

  set repaint(Listenable? value) {
    if (identical(_repaint, value)) return;
    if (attached) _repaint?.removeListener(_onAncestorMotion);
    _repaint = value;
    if (attached) _repaint?.addListener(_onAncestorMotion);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(_onAncestorMotion);
  }

  @override
  void detach() {
    _repaint?.removeListener(_onAncestorMotion);
    super.detach();
  }

  final _fallbackFilter = LayerHandle<ImageFilterLayer>();

  set sigma(double value) {
    if (_sigma == value) return;
    _sigma = value;
    markNeedsPaint();
  }

  set dpr(double value) {
    if (_dpr == value) return;
    _dpr = value;
    markNeedsPaint();
  }

  set samplingScale(double value) {
    if (_samplingScale == value) return;
    _samplingScale = value;
    markNeedsPaint();
  }

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  set repaintToken(Object? value) {
    if (_repaintToken == value) return;
    _repaintToken = value;
    // The enclosing paragraph boundary otherwise retains a remainder sampled
    // before its ancestor's follow/scroll transform changed.
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_enabled) {
      _fallbackFilter.layer = null;
      super.paint(context, offset);
      return;
    }
    final sigma = _sigma < .1 ? .1 : _sigma;
    if (child!.needsCompositing) {
      // Interlude opacity can require its own layer. Its few geometric dots
      // need no high-resolution glyph sampling; never span canvas state across
      // independently recorded child layers.
      if (_sigma == 0) {
        _fallbackFilter.layer = null;
        super.paint(context, offset);
        return;
      }
      final fallback = _fallbackFilter.layer ??= ImageFilterLayer();
      fallback.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      context.pushLayer(fallback, super.paint, offset);
      return;
    }
    _fallbackFilter.layer = null;
    // Vertical subpixel correction keeps optional-track reveals on their
    // established raster baseline. Horizontal nearest-pixel snapping can
    // jump by a full source pixel as the two-pane lyric origin crosses a
    // half-pixel while a focus transform finishes.
    final remainder = Offset(
      0,
      lyricFilterRemainder(getTransformTo(null), _dpr).dy,
    );
    final anchor = offset - remainder;
    final samplingScale = _samplingScale;
    final sampling = ui.ImageFilter.matrix(
        (Matrix4.translationValues(remainder.dx, remainder.dy, 0)
              ..scaleByDouble(1 / samplingScale, 1 / samplingScale, 1, 1))
            .storage,
        filterQuality: ui.FilterQuality.medium);
    // Restore v26.0.6's single display-list filter grouping. Keep the
    // current source guard, 1.5x Gaussian radius and sampling density.
    final filter = _sigma == 0
        ? sampling
        : ui.ImageFilter.compose(
            outer: ui.ImageFilter.blur(
                sigmaX: sigma * 1.5, sigmaY: sigma * 1.5),
            inner: sampling);
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(anchor.dx, anchor.dy);
    // The child and matrix stay in one display list; explicit source bounds
    // would clip supersampled input before its inverse projection.
    canvas.saveLayer(null, ui.Paint()..imageFilter = filter);
    canvas.scale(samplingScale);
    if (_retainSourceBounds) {
      // Keep the offscreen source origin stable as ruby ink rises. This adds
      // transparent coverage rather than clipping strokes; BlendMode.src is
      // confined to this empty sampling layer and cannot erase the backdrop.
      canvas.drawRect((Offset.zero & size).inflate(24), _sourceGuard);
    }
    super.paint(context, Offset.zero);
    canvas.restore();
    canvas.restore();
  }

  @override
  void dispose() {
    _fallbackFilter.layer = null;
    super.dispose();
  }
}
