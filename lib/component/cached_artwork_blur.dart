import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dan_player/component/artwork_mesh_painter.dart';

/// Flatten only the decoded, blurred artwork before it is rotated/scaled.
/// Moving a live ImageFilter can change its raster-cache/filter bounds at the
/// viewport edge. A bounded texture keeps those edges and the blur stable.
class CachedArtworkBlur extends StatefulWidget {
  const CachedArtworkBlur(
      {super.key, required this.image, required this.blur, this.phase});
  final ImageProvider image;
  final double blur;
  final ValueListenable<double>? phase;

  @override
  State<CachedArtworkBlur> createState() => _CachedArtworkBlurState();
}

class _CachedArtworkBlurState extends State<CachedArtworkBlur> {
  final _snapshot = SnapshotController();
  late final _painter = ArtworkMeshPainter(widget.phase);
  int _generation = 0;
  bool _pending = false;

  @override
  void didUpdateWidget(CachedArtworkBlur oldWidget) {
    super.didUpdateWidget(oldWidget);
    _painter.phase = widget.phase;
    if (oldWidget.image != widget.image || oldWidget.blur != widget.blur) {
      _generation++;
      _pending = false;
      _snapshot.allowSnapshotting = false;
    }
  }

  void _freezeWhenReady() {
    if (_snapshot.allowSnapshotting || _pending) return;
    _pending = true;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _pending = false;
      _snapshot.allowSnapshotting = true;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final longest = math.max(constraints.maxWidth, constraints.maxHeight);
          final media = MediaQuery.of(context);
          // The source is already sampled at 512px. 768px leaves extra sampling
          // room for rotation without allocating two full-screen 4K textures.
          final ratio = longest.isFinite && longest > 0
              ? math.min(media.devicePixelRatio, 768 / longest)
              : media.devicePixelRatio;
          return MediaQuery(
            data: media.copyWith(devicePixelRatio: ratio),
            child: SnapshotWidget(
              controller: _snapshot,
              painter: _painter,
              autoresize: true,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: widget.blur.clamp(0, 100),
                  sigmaY: widget.blur.clamp(0, 100),
                  tileMode: ui.TileMode.clamp,
                ),
                child: Image(
                  image: widget.image,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.low,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, synchronous) {
                    if (frame != null || synchronous) _freezeWhenReady();
                    return child;
                  },
                  errorBuilder: (_, __, ___) => const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      );

  @override
  void dispose() {
    _generation++;
    _snapshot.dispose();
    _painter.dispose();
    super.dispose();
  }
}
