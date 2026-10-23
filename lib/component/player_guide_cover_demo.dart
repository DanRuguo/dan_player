import 'dart:async';
import 'dart:ui' as drawing;

import 'package:dan_player/component/app_shape.dart';
import 'package:dan_player/component/cover_contour_glow.dart';
import 'package:desktop_lyric/ui_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Owns one small generated image. The real cover effect only borrows its frame;
/// neither the music library nor the user's artwork is involved in this demo.
class PlayerGuideCoverDemo extends StatefulWidget {
  const PlayerGuideCoverDemo(
      {super.key,
      required this.viewportKey,
      required this.motionEnabled,
      this.isHidden});

  final GlobalKey viewportKey;
  final ValueListenable<bool> motionEnabled;
  final ValueListenable<bool>? isHidden;

  @override
  State<PlayerGuideCoverDemo> createState() => _PlayerGuideCoverDemoState();
}

class _PlayerGuideCoverDemoState extends State<PlayerGuideCoverDemo> {
  drawing.Image? _frame;
  MemoryImage? _image;
  int _effect = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_createArtwork());
  }

  Future<void> _createArtwork() async {
    final recorder = drawing.PictureRecorder();
    final canvas = Canvas(recorder);
    const bounds = Rect.fromLTWH(0, 0, 256, 256);
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff122e51), Color(0xff652d67)])
              .createShader(bounds));
    canvas.drawCircle(
        const Offset(176, 80), 55, Paint()..color = const Color(0xfff6c77d));
    canvas.drawCircle(
        const Offset(176, 80), 35, Paint()..color = const Color(0xffdf7e87));
    final hills = Path()
      ..moveTo(0, 170)
      ..cubicTo(60, 100, 85, 208, 151, 152)
      ..cubicTo(193, 119, 213, 126, 256, 155)
      ..lineTo(256, 256)
      ..lineTo(0, 256)
      ..close();
    canvas.drawPath(hills, Paint()..color = const Color(0xff43a8ad));
    // Fine content edges make the real contour and local refraction visible.
    for (var row = 0; row < 9; row++) {
      canvas.drawLine(
          Offset(22, 177 + row * 6),
          Offset(234 - row * 8, 177 + row * 6),
          Paint()
            ..color = const Color(0xffd5f3df)
            ..strokeWidth = 1.25);
    }
    final picture = recorder.endRecording();
    drawing.Image? frame;
    try {
      frame = await picture.toImage(256, 256);
      final png = await frame.toByteData(format: drawing.ImageByteFormat.png);
      if (!mounted || png == null) return;
      setState(() {
        _frame = frame;
        _image = MemoryImage(png.buffer.asUint8List());
      });
      frame = null; // The state now owns this handle until the demo is removed.
    } finally {
      frame?.dispose();
      picture.dispose();
    }
  }

  @override
  void dispose() {
    _frame?.dispose();
    // The contour service owns its own bounded leases; release only this
    // demonstration's image-cache entry, never the shared contour cache.
    if (_image case final image?) unawaited(image.evict());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(ui('在示例封面上移动鼠标查看细线辉光与水滴折射，轻点可显示一次水波。移开鼠标后恢复原图；效果遵循当前动画设置。')),
      const SizedBox(height: 12),
      Align(
          alignment: AlignmentDirectional.center,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 256),
              child: AspectRatio(
                  key: widget.viewportKey,
                  aspectRatio: 1,
                  child: Semantics(
                      image: true,
                      label: ui('示例封面'),
                      child: ClipRRect(
                          borderRadius: AppShape.surfaceRadius,
                          child: _image == null
                              ? ColoredBox(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.album_outlined))
                              : CoverContourGlow(
                                  key: ValueKey('guide-cover-effect-$_effect'),
                                  image: _image!,
                                  currentFrame: _frame,
                                  hidden: widget.isHidden,
                                  activity: widget.motionEnabled,
                                  isActive: () => widget.motionEnabled.value,
                                  child: RawImage(
                                      image: _frame,
                                      fit: BoxFit.cover,
                                      filterQuality:
                                          FilterQuality.medium))))))),
      const SizedBox(height: 8),
      Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
              key: const ValueKey('guide-demo-cover-reset'),
              onPressed:
                  _image == null ? null : () => setState(() => _effect++),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(ui('恢复示例封面')))),
    ]);
  }
}
