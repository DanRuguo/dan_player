import 'dart:async';
import 'dart:ui' as ui;

import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
import 'package:dan_player/online/online_artwork_request.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// QQ's search descriptor stores its public 300px thumbnail. The same official
/// album endpoint also serves an 800px source; select it for large views before
/// decoding, rather than enlarging 300 decoded pixels. Unknown hosts, signed
/// URLs and non-QQ artwork remain byte-for-byte unchanged.
Uri artworkUriForSize(Uri source, ArtworkSize size, {String? provider}) {
  if (provider != 'qq' ||
      !const {'y.qq.com', 'y.gtimg.cn'}.contains(source.host) ||
      source.hasQuery ||
      source.hasFragment ||
      (size.width <= 300 && size.height <= 300)) {
    return source;
  }
  final match =
      RegExp(r'^(/music/photo_new/T002)R300x300(M000[A-Za-z0-9_]+\.jpg)$')
          .firstMatch(source.path);
  if (match == null) return source;
  return source.replace(path: '${match[1]}R800x800${match[2]}');
}

/// A bounded, profile-scoped image source for user-managed music providers.
///
/// Unlike [NetworkImage], this does not open the connection until
/// [OnlineArtworkRequest] has verified that [expectedProfile] is still the
/// exact enabled profile saved in settings. The request owns the byte, image
/// dimension and wall-clock limits; a disable, delete or edit invalidates the
/// load before its result can enter Flutter's image cache.
@immutable
class CustomOnlineArtworkImageProvider
    extends ImageProvider<CustomOnlineArtworkImageProvider> {
  const CustomOnlineArtworkImageProvider(
    this.address, {
    required this.expectedProfile,
  });

  final String address;
  final CustomMusicSourceProfile expectedProfile;

  @override
  Future<CustomOnlineArtworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) =>
      SynchronousFuture<CustomOnlineArtworkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CustomOnlineArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      MultiFrameImageStreamCompleter(
        codec: _loadAsync(key, decode),
        scale: 1,
        debugLabel:
            'CustomOnlineArtworkImageProvider(${key.expectedProfile.id})',
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<String>('profile', key.expectedProfile.id),
        ],
      );

  static Future<ui.Codec> _loadAsync(
    CustomOnlineArtworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await OnlineArtworkRequest().loadPng(
      key.address,
      provider: key.expectedProfile.providerId,
      expectedProfile: key.expectedProfile,
    );
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is CustomOnlineArtworkImageProvider &&
      address == other.address &&
      identical(expectedProfile, other.expectedProfile);

  @override
  int get hashCode => Object.hash(address, identityHashCode(expectedProfile));

  @override
  String toString() =>
      'CustomOnlineArtworkImageProvider(profile: ${expectedProfile.id})';
}

/// A cover-aware decode hint, unlike ResizeImage's contain/exact policies.
/// It asks the codec for the correct physical size once the original aspect
/// ratio is known. Original files/URLs are never replaced by low-res thumbnails.
@immutable
class ArtworkImageProvider extends ImageProvider<ArtworkImageKey> {
  const ArtworkImageProvider(this.source, this.size, {this.revision});

  final ImageProvider source;
  final ArtworkSize size;
  final Object? revision;

  @override
  Future<ArtworkImageKey> obtainKey(ImageConfiguration configuration) =>
      source.obtainKey(configuration).then(
            (key) => ArtworkImageKey(key, size, revision),
          );

  @override
  ImageStreamCompleter loadImage(
      ArtworkImageKey key, ImageDecoderCallback decode) {
    final completer = source.loadImage(key.source, (buffer, {getTargetSize}) {
      if (getTargetSize != null) {
        throw StateError('ArtworkImageProvider requires an unresized source.');
      }
      return decode(buffer, getTargetSize: (width, height) {
        final target = key.size.decodeSize(width, height);
        return ui.TargetImageSize(width: target.width, height: target.height);
      });
    });
    completer.addEphemeralErrorListener((_, __) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkImageProvider &&
      source == other.source &&
      size == other.size &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(source, size, revision);
}

@immutable
class ArtworkImageKey {
  const ArtworkImageKey(this.source, this.size, this.revision);
  final Object source;
  final ArtworkSize size;
  final Object? revision;

  @override
  bool operator ==(Object other) =>
      other is ArtworkImageKey &&
      source == other.source &&
      size == other.size &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(source, size, revision);
}
