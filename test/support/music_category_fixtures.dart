import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// In-memory metadata only. Never opens a local file, network or native API.
class CategoryTestAudio extends Audio {
  CategoryTestAudio(
    String id, {
    String artist = 'Artist',
    String album = 'Album',
    super.composer,
    super.albumArtist,
    super.language,
    String? path,
    int track = 0,
    int duration = 120,
    int? bitrate = 320,
    bool online = false,
    super.classificationVersion = 1,
  }) : super(
          id,
          artist,
          album,
          track,
          duration,
          bitrate,
          44100,
          path ??
              (online
                  ? 'online://qq/$id'
                  : 'D:/category-test-fixtures/$id.mp3'),
          10,
          5,
          'Test',
          onlineProvider: online ? 'qq' : null,
          onlineId: online ? id : null,
        );

  @override
  Future<ImageProvider?> artworkForSize(ArtworkSize size) =>
      SynchronousFuture<ImageProvider?>(null);
}
