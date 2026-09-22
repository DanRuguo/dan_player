import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Blur a lyric row without quantizing its slow movement to physical pixels.
///
/// A filter layer on the Windows raster-cache path rounds its incoming
/// translation. Place its source on a physical pixel, then restore the
/// fractional remainder with a bilinear matrix filter. The net geometry is
/// unchanged, including on renderers that do not round incoming translations.
class LyricFractionalFilter extends SingleChildRenderObjectWidget {
  const LyricFractionalFilter({
    super.key,
    required this.sigma,
    required this.dpr,
    this.enabled = true,
    super.child,
  })  : assert(sigma >= 0 && sigma < double.infinity),
        assert(dpr > 0 && dpr < double.infinity);

  final double sigma;
  final double dpr;
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLyricFractionalFilter(sigma, dpr, enabled);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLyricFractionalFilter)
      ..sigma = sigma
      ..dpr = dpr
      ..enabled = enabled;
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
  _RenderLyricFractionalFilter(this._sigma, this._dpr, this._enabled);

  double _sigma;
  double _dpr;
  bool _enabled;
  final _filterHandle = LayerHandle<ImageFilterLayer>();

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

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _enabled;

  // Deliberately not a repaint boundary: an ancestor scroll/paint offset must
  // recompute the remainder. Descendant boundaries retain their cached text.

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || !_enabled) {
      _filterHandle.layer = null;
      layer = null;
      super.paint(context, offset);
      return;
    }

    final remainder = lyricFilterRemainder(getTransformTo(null), _dpr);
    final anchor = offset - remainder;
    final transform =
        layer is TransformLayer ? layer! as TransformLayer : TransformLayer();
    transform
      ..offset = Offset.zero
      ..transform = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    layer = transform;

    // Preserve the existing clear/hover sampling path even at zero blur.
    // Disabling the effect explicitly still removes all our filter layers.
    final sigma = _sigma < .1 ? .1 : _sigma;
    final blur = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
    // Sample the fractional source before blurring it. Applying the matrix
    // after a blur changes its input raster origin when sigma changes.
    // Keep one layer so independently warming nested filter caches cannot
    // change glyph sampling partway through the slow return.
    final filter = _filterHandle.layer ??= ImageFilterLayer();
    filter
      ..offset = Offset.zero
      ..imageFilter = ui.ImageFilter.compose(
        outer: blur,
        inner: ui.ImageFilter.matrix(
          Matrix4.translationValues(remainder.dx, remainder.dy, 0).storage,
          filterQuality: ui.FilterQuality.low,
        ),
      );

    // Apply the layout offset only once, in the outer layer. The filter's
    // offset and child paint origin must both stay zero; otherwise part of the
    // translation is embedded in the display list instead of the aligned CTM.
    final bounds = paintBounds.inflate(sigma * 3 + 2);
    context.pushLayer(transform, (childContext, _) {
      childContext.pushLayer(filter, super.paint, Offset.zero,
          childPaintBounds: bounds);
    }, Offset.zero, childPaintBounds: bounds);
  }

  @override
  void dispose() {
    _filterHandle.layer = null;
    super.dispose();
  }
}
