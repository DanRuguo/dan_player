import 'dart:math' as math;

/// Physical-pixel decode requests. Round up into a finite set of cache sizes,
/// never down to an undersized thumbnail when a window moves between displays.
class ArtworkSize {
  const ArtworkSize(this.width, this.height);

  final int width;
  final int height;

  static const maxTargetEdge = 2048;
  static const maxDecodeEdge = 4096;
  static const maxDecodePixels = 4 * 1024 * 1024;
  static const buckets = [
    32,
    48,
    64,
    96,
    128,
    192,
    256,
    384,
    512,
    768,
    1024,
    1536,
    2048,
  ];

  factory ArtworkSize.forDisplay({
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
        ? devicePixelRatio
        : 1.0;
    int edge(double logical) {
      if (!logical.isFinite || logical <= 0) return buckets.first;
      final scaled = logical * ratio;
      if (!scaled.isFinite || scaled >= maxTargetEdge) return maxTargetEdge;
      final physical = scaled.ceil().clamp(1, maxTargetEdge);
      return buckets.firstWhere((bucket) => bucket >= physical);
    }

    return ArtworkSize(edge(logicalWidth), edge(logicalHeight));
  }

  /// Preserve the original aspect ratio while providing enough pixels for
  /// BoxFit.cover. A contain-style thumbnail would make the shorter axis blurry
  /// after cropping. Tiny sources remain tiny; extreme panoramas obey the same
  /// 16-MiB decoded thumbnail RGBA / 4096-edge output budget as local native
  /// thumbnails. This is not a cap on source-codec/Rust working memory: native
  /// extraction may first decode a larger original before resampling it.
  ArtworkSize decodeSize(int intrinsicWidth, int intrinsicHeight) {
    if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      throw ArgumentError('An artwork image must have positive dimensions.');
    }
    final needed = math.min(
      1.0,
      math.max(width / intrinsicWidth, height / intrinsicHeight),
    );
    final budget = math.min(
      math.min(maxDecodeEdge / intrinsicWidth, maxDecodeEdge / intrinsicHeight),
      math.sqrt(maxDecodePixels / (intrinsicWidth * intrinsicHeight)),
    );
    final scale = math.min(needed, budget);
    final budgetLimited = budget < needed;
    int dimension(int source) =>
        (budgetLimited ? (source * scale).floor() : (source * scale).ceil())
            .clamp(1, source);
    return ArtworkSize(dimension(intrinsicWidth), dimension(intrinsicHeight));
  }

  int get decodedRgbaBytes => width * height * 4;

  @override
  bool operator ==(Object other) =>
      other is ArtworkSize && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}
