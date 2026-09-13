import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:flutter/material.dart';

class CoverCaptionColors {
  const CoverCaptionColors(this.foreground, this.background);
  final Color foreground, background;
  static const fallback = CoverCaptionColors(Colors.white, Colors.transparent);
}

/// One bounded sample per decoded source revision and crop shape, never per
/// animation frame. Futures also deduplicate simultaneous visible requests.
class CoverCaptionCache {
  static final _cache = LinkedHashMap<Object, Future<CoverCaptionColors>>();
  static final _resolved = <Object, CoverCaptionColors>{};
  static Object _key(ImageProvider provider, double aspect) =>
      (provider, (aspect * 100).round());
  static CoverCaptionColors? cached(ImageProvider provider, double aspect) =>
      _resolved[_key(provider, aspect)];
  static Future<CoverCaptionColors> resolve(
      ImageProvider provider, double aspect) {
    final key = _key(provider, aspect);
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return hit;
    }
    final future = _sample(provider, aspect).then((colors) {
      if (_cache.containsKey(key)) _resolved[key] = colors;
      return colors;
    });
    _cache[key] = future;
    while (_cache.length > 512) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _resolved.remove(oldest);
    }
    return future;
  }

  static Future<CoverCaptionColors> _sample(
      ImageProvider provider, double aspect) async {
    final result = Completer<CoverCaptionColors>();
    var source = provider;
    while (source is ArtworkImageProvider) {
      source = source.source;
    }
    final stream = ArtworkImageProvider(source, const ArtworkSize(48, 48))
        .resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    Timer? timeout;
    void finish(CoverCaptionColors colors) {
      if (result.isCompleted) return;
      timeout?.cancel();
      stream.removeListener(listener);
      result.complete(colors);
    }

    listener = ImageStreamListener((info, _) async {
      try {
        final bytes =
            await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bytes == null) {
          finish(CoverCaptionColors.fallback);
          return;
        }
        final imageSize =
            Size(info.image.width.toDouble(), info.image.height.toDouble());
        final crop = Alignment.center.inscribe(
            applyBoxFit(BoxFit.cover, imageSize, Size(aspect * 100, 100))
                .source,
            Offset.zero & imageSize);
        final colors = <Color>[];
        for (var y = 0; y < 12; y++) {
          for (var x = 0; x < 24; x++) {
            final px = (crop.left + (x + .5) * crop.width / 24)
                .floor()
                .clamp(0, info.image.width - 1);
            final py = (crop.top + crop.height * (.78 + (y + .5) * .22 / 12))
                .floor()
                .clamp(0, info.image.height - 1);
            final offset = (py * info.image.width + px) * 4;
            colors.add(Color.fromARGB(
                bytes.getUint8(offset + 3),
                bytes.getUint8(offset),
                bytes.getUint8(offset + 1),
                bytes.getUint8(offset + 2)));
          }
        }
        finish(captionColorsForSamples(colors));
      } catch (_) {
        finish(CoverCaptionColors.fallback);
      } finally {
        info.dispose();
      }
    }, onError: (_, __) => finish(CoverCaptionColors.fallback));
    timeout = Timer(
        const Duration(seconds: 5), () => finish(CoverCaptionColors.fallback));
    stream.addListener(listener);
    return result.future;
  }
}

@visibleForTesting
CoverCaptionColors captionColorsForSamples(List<Color> samples) {
  if (samples.isEmpty) return CoverCaptionColors.fallback;
  // A small bright illustration should not make text over the predominantly
  // dark caption area turn black. Median is robust to those local highlights.
  final values = samples.map((color) => color.computeLuminance()).toList()
    ..sort();
  final middle = values.length ~/ 2;
  final luminance = values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
  // Choose the higher-contrast black/white text against the sampled region.
  // The text layer is fully transparent; never paint a caption rectangle.
  final darkText = (luminance + .05) / .05 >= 1.05 / (luminance + .05);
  return CoverCaptionColors(
      darkText ? Colors.black : Colors.white, Colors.transparent);
}
