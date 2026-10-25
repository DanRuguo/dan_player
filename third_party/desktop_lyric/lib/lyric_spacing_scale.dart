import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'app_motion.dart';

/// The existing main-lyric target-layout entrance, shared with desktop text.
abstract final class LyricSpacingMotion {
  static const duration = AppMotion.standard;
  static const curve = Cubic(.22, 0, .16, 1);
  static double scale(double progress) =>
      .96 + .04 * progress.clamp(0.0, 1.0);

  // Keep the main lyric's existing terminal geometry policy: reach the exact
  // target before the retained image filter is released on the final tick.
  static double settledGeometryProgress(double progress) =>
      (progress / .995).clamp(0.0, 1.0);
}

/// The target layout enters as one group. A held search glyph is its vertical
/// scale origin; other rows keep the normal top origin. Read cached geometry
/// only after child layout, rather than relaying paint ticks to the viewport.
class LyricSpacingScale extends Transform {
  LyricSpacingScale({
    super.key,
    required double scale,
    required Alignment alignment,
    required bool moving,
    FilterQuality? movingFilterQuality = FilterQuality.low,
    this.readingIdentity,
    this.readingY,
    required super.child,
  }) : super(
          transform: Matrix4.diagonal3Values(scale, scale, 1),
          alignment: alignment,
          filterQuality: moving ? movingFilterQuality : null,
        );

  final Object? readingIdentity;
  final double? Function(RenderBox ancestor)? readingY;

  @override
  RenderTransform createRenderObject(BuildContext context) =>
      _RenderLyricSpacingScale(
        transform: transform,
        baseAlignment: alignment! as Alignment,
        filterQuality: filterQuality,
        readingIdentity: readingIdentity,
        readingY: readingY,
      );

  @override
  void updateRenderObject(BuildContext context, RenderTransform renderObject) {
    (renderObject as _RenderLyricSpacingScale)
      ..transform = transform
      ..filterQuality = filterQuality
      ..configureReading(readingIdentity, readingY, alignment! as Alignment);
  }
}

class _RenderLyricSpacingScale extends RenderTransform {
  _RenderLyricSpacingScale({
    required super.transform,
    required Alignment baseAlignment,
    required super.filterQuality,
    required Object? readingIdentity,
    required double? Function(RenderBox ancestor)? readingY,
  })  : _baseAlignment = baseAlignment,
        _readingIdentity = readingIdentity,
        _readingY = readingY,
        super(alignment: baseAlignment);

  Alignment _baseAlignment;
  Object? _readingIdentity;
  double? Function(RenderBox ancestor)? _readingY;
  double? _anchorY;

  void configureReading(Object? identity,
      double? Function(RenderBox ancestor)? readY, Alignment baseAlignment) {
    // Closures change when the finite presentation rebuilds. Only changing the
    // owner invalidates layout; width and auxiliary reveals propagate child
    // layout changes through the existing render tree themselves.
    _readingY = readY;
    _baseAlignment = baseAlignment;
    if (_readingIdentity != identity) {
      _readingIdentity = identity;
      _anchorY = null;
      markNeedsLayout();
    }
    _updatePivot();
  }

  void _updatePivot() {
    final anchor = _anchorY;
    alignment =
        _readingIdentity != null && anchor != null && hasSize && size.height > 0
            ? Alignment(_baseAlignment.x, anchor / size.height * 2 - 1)
            : _baseAlignment;
  }

  @override
  void performLayout() {
    super.performLayout();
    _anchorY = _readingIdentity == null ? null : _readingY?.call(this);
    _updatePivot();
  }
}
