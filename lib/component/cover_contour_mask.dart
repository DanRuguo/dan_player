import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dan_player/library/artwork_animation_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// This is a preview of visible contours, not a full resolution segmentation.
/// The worker receives at most 384² pixels and never reads files or providers.
const coverContourMaximumSide = 384;

/// The source may already supply a display-sized decode hint. Replace that
/// hint at the decoder boundary rather than nesting ResizeImage around it.
/// FirstFrameArtworkProvider also bounds animated inputs to a single frame.
class _ContourFrameProvider extends ImageProvider<_ContourFrameKey> {
  const _ContourFrameProvider(this.source);
  final ImageProvider source;
  @override
  Future<_ContourFrameKey> obtainKey(ImageConfiguration configuration) async =>
      _ContourFrameKey(
          await FirstFrameArtworkProvider(source).obtainKey(configuration));
  @override
  ImageStreamCompleter loadImage(
          _ContourFrameKey key, ImageDecoderCallback decode) =>
      FirstFrameArtworkProvider(source).loadImage(
          key.source,
          (buffer, {getTargetSize}) =>
              decode(buffer, getTargetSize: (width, height) {
                final scale = math.min(
                    1.0, coverContourMaximumSide / math.max(width, height));
                return ui.TargetImageSize(
                    width: math.max(1, (width * scale).round()),
                    height: math.max(1, (height * scale).round()));
              }));
  @override
  bool operator ==(Object other) =>
      other is _ContourFrameProvider && source == other.source;
  @override
  int get hashCode => Object.hash(_ContourFrameProvider, source);
}

@immutable
class _ContourFrameKey {
  const _ContourFrameKey(this.source);
  final FirstFrameArtworkKey source;
  @override
  bool operator ==(Object other) =>
      other is _ContourFrameKey && source == other.source;
  @override
  int get hashCode => Object.hash(_ContourFrameKey, source);
}

@immutable
class CoverContourPixels {
  const CoverContourPixels(this.rgba, this.width, this.height);
  final Uint8List rgba;
  final int width;
  final int height;
}

/// A small Gaussian prefilter suppresses compression grain before Sobel edges.
/// Alpha is retained so transparent cover margins cannot become glowing boxes.
Uint8List extractCoverContours(CoverContourPixels input) {
  final width = input.width;
  final height = input.height;
  if (width < 1 ||
      height < 1 ||
      width > coverContourMaximumSide ||
      height > coverContourMaximumSide ||
      input.rgba.length != width * height * 4) {
    return Uint8List(0);
  }
  final count = width * height;
  final gray = Uint8List(count);
  final smooth = Uint8List(count);
  final output = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    final at = i * 4;
    gray[i] = ((input.rgba[at] * 77 +
                input.rgba[at + 1] * 150 +
                input.rgba[at + 2] * 29) >>
            8) *
        input.rgba[at + 3] ~/
        255;
  }
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      smooth[i] = (gray[i - width - 1] +
              2 * gray[i - width] +
              gray[i - width + 1] +
              2 * gray[i - 1] +
              4 * gray[i] +
              2 * gray[i + 1] +
              gray[i + width - 1] +
              2 * gray[i + width] +
              gray[i + width + 1]) >>
          4;
    }
  }
  // Leave two pixels of margin: the prefilter's uncomputed border is not art.
  for (var y = 2; y < height - 2; y++) {
    for (var x = 2; x < width - 2; x++) {
      final i = y * width + x;
      final gx = -smooth[i - width - 1] +
          smooth[i - width + 1] -
          2 * smooth[i - 1] +
          2 * smooth[i + 1] -
          smooth[i + width - 1] +
          smooth[i + width + 1];
      final gy = -smooth[i - width - 1] -
          2 * smooth[i - width] -
          smooth[i - width + 1] +
          smooth[i + width - 1] +
          2 * smooth[i + width] +
          smooth[i + width + 1];
      final strength = math.sqrt((gx * gx + gy * gy).toDouble()) / 4;
      final alpha = ((strength - 7) * 3.2).round().clamp(0, 220) *
          input.rgba[i * 4 + 3] ~/
          255;
      if (alpha == 0) continue;
      final at = i * 4;
      // PixelFormat.rgba8888 requires premultiplied channels.
      output[at] = output[at + 1] = output[at + 2] = alpha;
      output[at + 3] = alpha;
    }
  }
  return output;
}

/// The caller owns a clone. Closing a pending lease cancels work when it has
/// no visible consumers; completed masks remain in the bounded shared LRU.
class CoverContourLease {
  CoverContourLease._(this._entry) {
    _entry.references++;
    image =
        _entry.result.future.then((image) => _closed ? null : image?.clone());
  }
  final _MaskEntry _entry;
  late final Future<ui.Image?> image;
  bool _closed = false;
  void dispose() {
    if (_closed) return;
    _closed = true;
    _entry.references--;
    if (_entry.references == 0 && _entry.retired) {
      _entry.mask?.dispose();
      _entry.mask = null;
    }
    if (_entry.references == 0 && !_entry.result.isCompleted) {
      CoverContourCache._retire(_entry);
    }
  }
}

class _MaskEntry {
  _MaskEntry(this.provider, this.configuration);
  final ImageProvider provider;
  final ImageConfiguration configuration;
  final result = Completer<ui.Image?>();
  int references = 0;
  bool retired = false;
  VoidCallback? cancelRead;
  ui.Image? mask;
}

abstract final class CoverContourCache {
  static const maximumEntries = 6;
  static const maximumConcurrent = 2;
  static final _entries = LinkedHashMap<ImageProvider, _MaskEntry>();
  static final _queue = Queue<_MaskEntry>();
  static int _running = 0;

  static CoverContourLease? acquire(
      ImageProvider provider, ImageConfiguration configuration) {
    final previous = _entries.remove(provider);
    if (previous != null) {
      _entries[provider] = previous;
      return CoverContourLease._(previous);
    }
    if (_entries.length >= maximumEntries) {
      final candidates = _entries.values
          .where((entry) => entry.references == 0 || entry.result.isCompleted);
      if (candidates.isEmpty) return null;
      _retire(candidates.first);
    }
    final entry = _MaskEntry(provider, configuration);
    _entries[provider] = entry;
    _queue.add(entry);
    final lease = CoverContourLease._(entry);
    _drain();
    return lease;
  }

  static void _retire(_MaskEntry entry) {
    if (entry.retired) return;
    entry.retired = true;
    if (identical(_entries[entry.provider], entry))
      _entries.remove(entry.provider);
    _queue.remove(entry);
    entry.cancelRead?.call();
    if (entry.references == 0) {
      entry.mask?.dispose();
      entry.mask = null;
    }
    if (!entry.result.isCompleted) entry.result.complete(null);
  }

  static void _drain() {
    while (_running < maximumConcurrent && _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      if (entry.retired) continue;
      _running++;
      unawaited(_generate(entry).whenComplete(() {
        _running--;
        _drain();
      }));
    }
  }

  static Future<void> _generate(_MaskEntry entry) async {
    ui.Image? source;
    ui.Image? small;
    ui.Image? mask;
    try {
      source = await _firstFrame(entry);
      if (source == null || entry.retired) return;
      final scale = math.min(
          1.0, coverContourMaximumSide / math.max(source.width, source.height));
      final width = math.max(1, (source.width * scale).round());
      final height = math.max(1, (source.height * scale).round());
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
          source,
          Rect.fromLTWH(
              0, 0, source.width.toDouble(), source.height.toDouble()),
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..filterQuality = FilterQuality.medium);
      final picture = recorder.endRecording();
      try {
        small = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
      source.dispose();
      source = null;
      if (entry.retired) return;
      final rgba =
          await small.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      small.dispose();
      small = null;
      if (rgba == null || entry.retired) return;
      final pixels = await compute(extractCoverContours,
          CoverContourPixels(rgba.buffer.asUint8List(), width, height),
          debugLabel: 'cover-contours');
      if (entry.retired || pixels.isEmpty) return;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          pixels, width, height, ui.PixelFormat.rgba8888, decoded.complete);
      mask = await decoded.future;
      if (entry.retired) return;
      entry.mask = mask;
      entry.result.complete(mask);
      mask = null;
    } catch (_) {
      // Artwork stays visible even if readback or optional edge analysis fails.
    } finally {
      source?.dispose();
      small?.dispose();
      mask?.dispose();
      entry.cancelRead = null;
      if (!entry.result.isCompleted) entry.result.complete(null);
    }
  }

  static Future<ui.Image?> _firstFrame(_MaskEntry entry) {
    final ready = Completer<ui.Image?>();
    final provider = _ContourFrameProvider(entry.provider);
    final stream = provider.resolve(entry.configuration);
    late final ImageStreamListener listener;
    Timer? timeout;
    void finish(ui.Image? image) {
      if (ready.isCompleted) {
        image?.dispose();
        return;
      }
      stream.removeListener(listener);
      timeout?.cancel();
      unawaited(provider.evict(configuration: entry.configuration));
      ready.complete(image);
    }

    listener = ImageStreamListener((info, _) {
      final image = info.image.clone();
      info.dispose();
      finish(image);
    }, onError: (Object _, StackTrace? __) => finish(null));
    entry.cancelRead = () => finish(null);
    timeout = Timer(const Duration(seconds: 3), () => finish(null));
    stream.addListener(listener);
    return ready.future;
  }

  @visibleForTesting
  static int get cachedEntries => _entries.length;
  @visibleForTesting
  static int get activeJobs => _running;
  @visibleForTesting
  static void clear() {
    for (final entry in _entries.values.toList()) {
      _retire(entry);
    }
  }
}
