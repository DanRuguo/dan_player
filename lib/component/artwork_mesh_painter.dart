import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Deforms the real blurred cover's texture coordinates, not a sampled colour
/// palette. One shader draw over a fixed rectangle keeps every edge covered.
/// Uses the existing background phase and owns no timer or image readback.
class ArtworkMeshPainter extends SnapshotPainter {
  ArtworkMeshPainter(ValueListenable<double>? phase) {
    this.phase = phase;
    if (phase != null) _prepareShader();
  }
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  bool _disposed = false;
  bool _preparing = false;
  @visibleForTesting
  bool get shaderReady => _shader != null;
  void _prepareShader() {
    if (_preparing || _shader != null) return;
    _preparing = true;
    (_program ??=
            ui.FragmentProgram.fromAsset('assets/shaders/artwork_flow.frag'))
        .then((program) {
      if (_disposed) return;
      _shader = program.fragmentShader();
      notifyListeners();
    }, onError: (Object error, StackTrace stack) {
      // Unsupported backends keep the existing blurred-cover flow. Do not
      // substitute the much more expensive per-triangle texture path.
      _preparing = false;
    });
  }

  ValueListenable<double>? _phase;
  set phase(ValueListenable<double>? value) {
    if (identical(value, _phase)) return;
    _phase?.removeListener(notifyListeners);
    _phase = value;
    _phase?.addListener(notifyListeners);
    if (value != null) _prepareShader();
    notifyListeners();
  }

  @visibleForTesting
  static Offset texturePoint(double x, double y, double phase) {
    final t = phase * math.pi * 2;
    // Zero displacement on all borders. Integer phase frequencies make the
    // complete 36-second cycle position- and velocity-continuous.
    final envelope = math.sin(math.pi * x) * math.sin(math.pi * y);
    final dx = .12 * envelope * math.sin(t) * math.sin(2 * math.pi * y + t);
    final dy = .10 * envelope * math.sin(t * 2) * math.cos(2 * math.pi * x - t);
    return Offset((x + dx).clamp(0, 1), (y + dy).clamp(0, 1));
  }

  @override
  void paint(PaintingContext context, Offset offset, Size size,
          PaintingContextCallback painter) =>
      painter(context, offset);

  @override
  void paintSnapshot(PaintingContext context, Offset offset, Size size,
      ui.Image image, Size sourceSize, double pixelRatio) {
    if (_phase == null || _shader == null) {
      context.canvas.drawImageRect(image, Offset.zero & sourceSize,
          offset & size, Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    if (_shader case final shader?) {
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, sourceSize.width / image.width)
        ..setFloat(3, sourceSize.height / image.height)
        ..setFloat(4, _phase!.value)
        ..setImageSampler(0, image);
      context.canvas.save();
      context.canvas.translate(offset.dx, offset.dy);
      context.canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      context.canvas.restore();
      return;
    }
  }

  @override
  bool shouldRepaint(covariant ArtworkMeshPainter oldPainter) =>
      !identical(_phase, oldPainter._phase);

  @override
  void dispose() {
    _disposed = true;
    _phase?.removeListener(notifyListeners);
    _shader?.dispose();
    super.dispose();
  }
}
