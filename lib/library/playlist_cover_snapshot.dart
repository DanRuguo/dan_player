import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/cover_image_import.dart';
import 'package:dan_player/online/online_artwork_request.dart';
import 'package:flutter/painting.dart';

/// Saves the decoded selected artwork, rather than a reference to a song that
/// may later move or be removed. Existing backup traversal follows imagePath.
Future<String> savePlaylistSongCover(Audio audio,
    {Future<Directory> Function()? dataDirectory}) async {
  if (audio.isOnline && audio.artworkUrl?.isNotEmpty == true) {
    final bytes = await OnlineArtworkRequest()
        .loadCover(audio.artworkUrl!, provider: audio.onlineProvider);
    return await savePreparedPlaylistCover(
        await CoverImageImporter.shared.fromBytes(bytes),
        dataDirectory: dataDirectory);
  }
  final provider = await audio
      .artworkForSize(const ArtworkSize(1024, 1024))
      .timeout(const Duration(seconds: 15));
  if (provider == null) throw const FormatException('这首歌曲没有可用封面。');
  final stream = provider.resolve(ImageConfiguration.empty);
  final ready = Completer<ImageInfo>();
  late ImageStreamListener listener;
  listener = ImageStreamListener((image, _) {
    if (ready.isCompleted) {
      image.dispose();
    } else {
      ready.complete(image);
    }
  }, onError: (Object error, StackTrace? stack) {
    if (!ready.isCompleted) ready.completeError(error, stack);
  });
  stream.addListener(listener);
  ImageInfo? image;
  try {
    image = await ready.future.timeout(const Duration(seconds: 15));
    final png = await image.image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw const FormatException('这首歌曲没有可用封面。');
    final bytes = png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    return await savePreparedPlaylistCover(
        await CoverImageImporter.shared.fromBytes(bytes),
        dataDirectory: dataDirectory);
  } finally {
    stream.removeListener(listener);
    image?.dispose();
  }
}
