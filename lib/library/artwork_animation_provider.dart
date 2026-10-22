import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

bool isGifArtworkBytes(List<int> bytes) =>
    bytes.length >= 6 &&
    (String.fromCharCodes(bytes.take(6)) == 'GIF87a' ||
        String.fromCharCodes(bytes.take(6)) == 'GIF89a');

/// Marks validated animation. Nonvisual consumers get only its first frame;
/// an active AnimatedArtwork explicitly unwraps [source] to play the GIF.
class AnimatedArtworkSource extends ImageProvider<FirstFrameArtworkKey> {
  const AnimatedArtworkSource(this.source);
  final ImageProvider source;
  @override
  Future<FirstFrameArtworkKey> obtainKey(ImageConfiguration configuration) =>
      FirstFrameArtworkProvider(source).obtainKey(configuration);
  @override
  ImageStreamCompleter loadImage(
          FirstFrameArtworkKey key, ImageDecoderCallback decode) =>
      FirstFrameArtworkProvider(source).loadImage(key, decode);
  @override
  bool operator ==(Object other) =>
      other is AnimatedArtworkSource && source == other.source;
  @override
  int get hashCode => source.hashCode;
}

bool mayAnimateArtwork(ImageProvider image) =>
    image is AnimatedArtworkSource ||
    (image is FileImage && image.file.path.toLowerCase().endsWith('.gif')) ||
    (image is MemoryImage && isGifArtworkBytes(image.bytes));

/// A distinct codec/cache identity that never schedules another GIF frame.
/// Used by disabled/reduced-motion surfaces and cover handoff readiness.
class FirstFrameArtworkProvider extends ImageProvider<FirstFrameArtworkKey> {
  const FirstFrameArtworkProvider(this.source);
  final ImageProvider source;
  @override
  Future<FirstFrameArtworkKey> obtainKey(
          ImageConfiguration configuration) async =>
      FirstFrameArtworkKey(await source.obtainKey(configuration));
  @override
  ImageStreamCompleter loadImage(
          FirstFrameArtworkKey key, ImageDecoderCallback decode) =>
      source.loadImage(
          key.source,
          (buffer, {getTargetSize}) async => _FirstFrameCodec(
              await decode(buffer, getTargetSize: getTargetSize)));
  @override
  bool operator ==(Object other) =>
      other is FirstFrameArtworkProvider && source == other.source;
  @override
  int get hashCode => Object.hash(FirstFrameArtworkProvider, source);
}

@immutable
class FirstFrameArtworkKey {
  const FirstFrameArtworkKey(this.source);
  final Object source;
  @override
  bool operator ==(Object other) =>
      other is FirstFrameArtworkKey && source == other.source;
  @override
  int get hashCode => Object.hash(FirstFrameArtworkKey, source);
}

class _FirstFrameCodec implements ui.Codec {
  _FirstFrameCodec(this.delegate);
  final ui.Codec delegate;
  @override
  int get frameCount => 1;
  @override
  int get repetitionCount => 0;
  @override
  Future<ui.FrameInfo> getNextFrame() => delegate.getNextFrame();
  @override
  void dispose() => delegate.dispose();
}
