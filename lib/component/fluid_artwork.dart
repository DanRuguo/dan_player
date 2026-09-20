import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/component/app_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A small palette per source, shared across revisits. Sampling never runs at
/// playback frequency and never retains a full-resolution image or pixel buffer.
abstract final class FluidArtworkPalette {
  static final _cache = LinkedHashMap<ImageProvider, Future<List<Color>?>>();

  static Future<List<Color>?> resolve(ImageProvider provider) {
    var source = provider;
    while (source is ArtworkImageProvider || source is ResizeImage) {
      source = source is ArtworkImageProvider
          ? source.source
          : (source as ResizeImage).imageProvider;
    }
    final hit = _cache.remove(source);
    if (hit != null) {
      _cache[source] = hit;
      return hit;
    }
    final result = _read(source);
    _cache[source] = result;
    unawaited(result.then((colors) {
      // Failed/transient sources may recover on a later visit. An evicted
      // request must never remove a newer retry for the same source.
      if (colors == null && identical(_cache[source], result)) {
        _cache.remove(source);
      }
    }));
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  static Future<List<Color>?> _read(ImageProvider provider) {
    final result = Completer<List<Color>?>();
    final sample = ResizeImage(provider,
        width: 32, height: 32, policy: ResizeImagePolicy.fit);
    final stream = sample.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    Timer? timeout;
    var finished = false;
    Future<void> finish(List<Color>? colors) async {
      if (finished) return;
      finished = true;
      timeout?.cancel();
      stream.removeListener(listener);
      if (colors == null) {
        // A fully transparent decoded frame is also an unsuccessful sample.
        // Drop this tiny cache entry so a same-source retry can decode again.
        try {
          await sample.evict();
        } catch (_) {}
      }
      result.complete(colors);
    }

    listener = ImageStreamListener((info, _) async {
      stream.removeListener(listener);
      try {
        final bytes =
            await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bytes == null) {
          finish(null);
          return;
        }
        final sums = List.generate(4, (_) => [0.0, 0.0, 0.0, 0.0]);
        for (var y = 0; y < info.image.height; y++) {
          for (var x = 0; x < info.image.width; x++) {
            final quadrant =
                (y * 2 ~/ info.image.height) * 2 + x * 2 ~/ info.image.width;
            final offset = (y * info.image.width + x) * 4;
            final alpha = bytes.getUint8(offset + 3) / 255;
            final sum = sums[quadrant];
            for (var channel = 0; channel < 3; channel++) {
              sum[channel] += bytes.getUint8(offset + channel) * alpha;
            }
            sum[3] += alpha;
          }
        }
        final all = [0.0, 0.0, 0.0, 0.0];
        for (final sum in sums) {
          for (var i = 0; i < 4; i++) {
            all[i] += sum[i];
          }
        }
        if (all[3] == 0) {
          finish(null);
          return;
        }
        Color color(List<double> sample) => Color.fromARGB(
            255,
            (sample[0] / sample[3]).round().clamp(0, 255),
            (sample[1] / sample[3]).round().clamp(0, 255),
            (sample[2] / sample[3]).round().clamp(0, 255));
        finish(List.unmodifiable([
          for (final sum in sums) color(sum[3] > 0 ? sum : all),
        ]));
      } catch (_) {
        finish(null);
      } finally {
        info.dispose();
      }
    }, onError: (_, __) => finish(null));
    timeout = Timer(const Duration(seconds: 5), () => finish(null));
    stream.addListener(listener);
    return result.future;
  }
}

/// Four cached radial fields blend into a slowly flowing cover-colour mesh.
/// Reuses the background's existing gated 20Hz phase; its only local ticker is
/// a finite colour handoff, cancelled by the same playback/visibility gate.
class FluidArtwork extends StatefulWidget {
  const FluidArtwork(
      {super.key,
      required this.image,
      required this.phase,
      required this.active,
      required this.fallback});
  final ImageProvider image;
  final ValueListenable<double> phase;
  final ValueListenable<bool> active;
  final Widget fallback;

  @override
  State<FluidArtwork> createState() => _FluidArtworkState();
}

class _FluidArtworkState extends State<FluidArtwork>
    with SingleTickerProviderStateMixin {
  late Future<List<Color>?> _palette;
  late final _transition =
      AnimationController(vsync: this, duration: AppMotion.long, value: 1);
  List<Color>? _from;
  List<Color>? _to;
  bool _themeMotion = false;

  List<Color> get _colors {
    if (_from == null || _transition.value == 1) return _to!;
    final value = AppMotion.standardCurve.transform(_transition.value);
    return List.generate(
        4, (index) => Color.lerp(_from![index], _to![index], value)!);
  }

  void _syncGate() {
    if (!widget.active.value || !_themeMotion) _transition.value = 1;
  }

  @override
  void initState() {
    super.initState();
    widget.active.addListener(_syncGate);
    _palette = FluidArtworkPalette.resolve(widget.image);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeMotion = TickerMode.valuesOf(context).enabled &&
        AppMotion.enabled(context, MotionKind.theme);
    _syncGate();
  }

  @override
  void didUpdateWidget(FluidArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.active, widget.active)) {
      oldWidget.active.removeListener(_syncGate);
      widget.active.addListener(_syncGate);
      _syncGate();
    }
    if (oldWidget.image != widget.image) {
      _palette = FluidArtworkPalette.resolve(widget.image);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Color>?>(
      future: _palette,
      builder: (context, snapshot) {
        final colors = snapshot.data;
        if (colors == null) return widget.fallback;
        if (!listEquals(colors, _to)) {
          _from = _to == null ? null : _colors;
          _to = colors;
          if (_from == null || !widget.active.value || !_themeMotion) {
            _transition.value = 1;
          } else {
            _transition.forward(from: 0);
          }
        }
        return AnimatedBuilder(
          animation: _transition,
          builder: (_, child) => CustomPaint(
              painter: FluidArtworkPainter(_colors, widget.phase),
              child: child),
          child: const SizedBox.expand(),
        );
      });

  @override
  void dispose() {
    widget.active.removeListener(_syncGate);
    _transition.dispose();
    super.dispose();
  }
}

class FluidArtworkPainter extends CustomPainter {
  FluidArtworkPainter(this.colors, this.phase) : super(repaint: phase);
  final List<Color> colors;
  final ValueListenable<double> phase;
  Size? _size;
  double _radius = 0;
  final _fields = <Paint>[];
  final _base = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (_size != size) {
      _size = size;
      _radius = size.longestSide * .82;
      _base.color = Color.lerp(colors[0], colors[3], .5)!;
      _fields
        ..clear()
        ..addAll(colors.map((color) => Paint()
          ..shader = ui.Gradient.radial(
              Offset.zero,
              _radius,
              [color, color.withValues(alpha: .75), color.withValues(alpha: 0)],
              [0, .38, 1])));
    }
    canvas.drawRect(Offset.zero & size, _base);
    final time = phase.value * math.pi * 2;
    for (var i = 0; i < 4; i++) {
      final angle = time + i * math.pi / 2;
      final x = .5 + .38 * math.cos(angle) + .06 * math.sin(time * 2 + i);
      final y = .5 + .38 * math.sin(angle) + .06 * math.cos(time * 2 + i);
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.drawCircle(Offset.zero, _radius, _fields[i]);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(FluidArtworkPainter oldDelegate) =>
      !listEquals(colors, oldDelegate.colors) ||
      !identical(phase, oldDelegate.phase);
}
