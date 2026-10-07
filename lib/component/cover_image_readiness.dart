import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A decoded, unmodified cover filling this boundary can share its texture.
/// Partial opacity, composited images and cropped geometry need raster capture.
ui.Image? decodedCoverImage(RenderBox boundary) {
  RenderImage? found;
  var usable = true;
  void visit(RenderObject render) {
    if (!usable) return;
    if (render is RenderOpacity && render.opacity != 1 ||
        render is RenderAnimatedOpacity && render.opacity.value != 1) {
      usable = false;
      return;
    }
    if (render is RenderImage && render.image != null) {
      if (found != null ||
          render.fit != BoxFit.cover ||
          render.color != null ||
          render.centerSlice != null ||
          render.repeat != ImageRepeat.noRepeat ||
          render.matchTextDirection) {
        usable = false;
        return;
      }
      final rect = MatrixUtils.transformRect(
          render.getTransformTo(boundary), Offset.zero & render.size);
      final box = Offset.zero & boundary.size;
      if ((rect.topLeft - box.topLeft).distance > .5 ||
          (rect.bottomRight - box.bottomRight).distance > .5) {
        usable = false;
        return;
      }
      found = render;
    }
    render.visitChildren(visit);
  }

  visit(boundary);
  return usable ? found?.image : null;
}

/// Route endpoints may wrap their square artwork in a wider caption surface.
ui.Image? firstDecodedCoverImage(RenderObject render) {
  if (render is RenderImage &&
      render.image != null &&
      render.color == null &&
      render.fit == BoxFit.cover) {
    return render.image;
  }
  ui.Image? found;
  render.visitChildren((child) {
    found ??= firstDecodedCoverImage(child);
  });
  return found;
}

bool hasDecodedCoverImage(RenderObject render) {
  if (!render.attached) return false;
  if (render is RenderImage && render.image != null) return true;
  var found = false;
  render.visitChildren((child) {
    if (!found) found = hasDecodedCoverImage(child);
  });
  return found;
}

/// Image completion changes a descendant's layout/paint state even while the
/// target is fully transparent. Observe those events instead of polling frames.
class CoverImageReadinessObserver extends SingleChildRenderObjectWidget {
  const CoverImageReadinessObserver(
      {super.key,
      required this.onChanged,
      this.hidePlaceholder = false,
      required super.child});
  final VoidCallback onChanged;
  final bool hidePlaceholder;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCoverImageReadiness(onChanged, hidePlaceholder);
  @override
  void updateRenderObject(
      BuildContext context, RenderCoverImageReadiness renderObject) {
    renderObject.onChanged = onChanged;
    renderObject.hidePlaceholder = hidePlaceholder;
    renderObject.markNeedsPaint();
  }
}

class RenderCoverImageReadiness extends RenderProxyBox {
  RenderCoverImageReadiness(this.onChanged, this.hidePlaceholder);
  VoidCallback onChanged;
  bool hidePlaceholder;
  @override
  void paint(PaintingContext context, Offset offset) {
    if (hidePlaceholder && child != null && !hasDecodedCoverImage(child!)) {
      return;
    }
    super.paint(context, offset);
  }

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    onChanged();
  }

  @override
  void performLayout() {
    super.performLayout();
    onChanged();
  }
}
