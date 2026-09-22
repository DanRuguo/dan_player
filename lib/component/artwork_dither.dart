import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Screen-aligned, sub-visible grain over the finished cover layers. The one
/// 16 KiB texture is shared for the app lifetime; playback never regenerates it.
/// Src-over approximates half-LSB dithering, with at most half-LSB mean bias
/// toward mid-grey before output quantization. It does not animate the grain.
class ArtworkDither extends StatefulWidget {
  const ArtworkDither({super.key});

  static final Future<ui.Image?> _texture = _makeTexture().then<ui.Image?>(
      (image) => image,
      onError: (Object _, StackTrace __) => null);

  @visibleForTesting
  static Future<void> prepare() async {
    await _texture;
  }

  static Future<ui.Image> _makeTexture() async {
    final pixels = Uint8List(64 * 64 * 4);
    final tones = List<int>.generate(4096, (index) => index & 1);
    // An equal number of black and white samples, shuffled once with a fixed
    // integer seed. Neither time, song, theme nor motion phase changes it.
    var seed = 0x7b3f2a19;
    for (var i = tones.length - 1; i > 0; i--) {
      seed = (seed ^ (seed << 13)) & 0xffffffff;
      seed = (seed ^ (seed >> 17)) & 0xffffffff;
      seed = (seed ^ (seed << 5)) & 0xffffffff;
      final index = seed % (i + 1);
      final previous = tones[i];
      tones[i] = tones[index];
      tones[index] = previous;
    }
    for (var i = 0; i < tones.length; i++) {
      final offset = i * 4;
      // Raw image descriptors expect premultiplied RGBA. White at alpha 1/255
      // must have RGB=1, not 255, or the supposedly faint grain becomes opaque.
      pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = tones[i];
      pixels[offset + 3] = 1;
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
    final descriptor = ui.ImageDescriptor.raw(buffer,
        width: 64, height: 64, pixelFormat: ui.PixelFormat.rgba8888);
    try {
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  State<ArtworkDither> createState() => _ArtworkDitherState();
}

class _ArtworkDitherState extends State<ArtworkDither> {
  ui.Image? _image;
  ui.ImageShader? _shader;
  double _dpr = 1;

  @override
  void initState() {
    super.initState();
    ArtworkDither._texture.then((image) {
      if (!mounted || image == null) return;
      setState(() {
        _image = image;
        _updateShader();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr == _dpr) return;
    _dpr = dpr;
    _updateShader();
  }

  void _updateShader() {
    _shader?.dispose();
    _shader = _image == null
        ? null
        : ui.ImageShader(
            _image!,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            (Matrix4.identity()..scaleByDouble(1 / _dpr, 1 / _dpr, 1, 1))
                .storage,
            filterQuality: FilterQuality.none);
  }

  @override
  Widget build(BuildContext context) => _shader == null
      ? const SizedBox.expand()
      : CustomPaint(painter: _ArtworkDitherPainter(_shader!));

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }
}

class _ArtworkDitherPainter extends CustomPainter {
  _ArtworkDitherPainter(this.shader);
  final ui.ImageShader shader;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);

  @override
  bool shouldRepaint(_ArtworkDitherPainter oldDelegate) =>
      !identical(shader, oldDelegate.shader);
}
