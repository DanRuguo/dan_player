import 'dart:ui' show Offset;

/// Snaps a logical translation [offset] to whole physical pixels for [dpr].
///
/// Pure vertical or horizontal entrances on live hinted text can otherwise land
/// on fractional physical coordinates, making individual glyphs cross
/// DirectWrite/Skia hinting boundaries on different frames.
Offset snapOffsetToPhysicalPixel(Offset offset, double dpr) {
  if (!dpr.isFinite || dpr <= 0 || !offset.dx.isFinite || !offset.dy.isFinite) {
    return offset;
  }
  return Offset(
    (offset.dx * dpr).roundToDouble() / dpr,
    (offset.dy * dpr).roundToDouble() / dpr,
  );
}
