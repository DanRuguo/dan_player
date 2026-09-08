import 'dart:async';
import 'dart:io';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/category_cover_store.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/music_categories.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum CoverRepairStatus {
  ready,
  success,
  noArtwork,
  unreadable,
  failed,
  cancelled
}

class CoverRepairTarget {
  CoverRepairTarget.audio(this.audio)
      : group = null,
        title = audio!.displayTitle,
        source = audio.localFilePath;
  CoverRepairTarget.group(this.group)
      : audio = null,
        title = group!.title,
        source = '自定义专辑封面';
  final Audio? audio;
  final MusicCategoryGroup? group;
  final String title, source;
  CoverRepairStatus status = CoverRepairStatus.ready;
  String reason = '';
  bool get retryable =>
      status == CoverRepairStatus.failed ||
      status == CoverRepairStatus.unreadable;
}

class CoverRepair extends ChangeNotifier {
  CoverRepair(Iterable<Audio> audios,
      {MusicCategoryGroup? album,
      CategoryCoverStore? covers,
      Future<CoverRepairStatus> Function(CoverRepairTarget)? repair})
      : _covers = covers ?? CategoryCoverStore.shared,
        _repair = repair {
    final seen = <String>{};
    targets = List.unmodifiable([
      if (album != null && _covers.hasCover(album))
        CoverRepairTarget.group(album),
      for (final audio in audios)
        if (seen.add(TrackIdentityRegistry.normalizePath(audio.localFilePath)))
          CoverRepairTarget.audio(audio),
    ]);
  }
  late final List<CoverRepairTarget> targets;
  final CategoryCoverStore _covers;
  final Future<CoverRepairStatus> Function(CoverRepairTarget)? _repair;
  bool busy = false, started = false, cancellationRequested = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    cancellationRequested = true;
    _disposed = true;
    super.dispose();
  }

  int count(CoverRepairStatus status) =>
      targets.where((target) => target.status == status).length;
  void cancel() {
    cancellationRequested = true;
    notifyListeners();
  }

  Future<void> run({bool retryOnly = false}) async {
    if (busy) return;
    busy = true;
    started = true;
    cancellationRequested = false;
    notifyListeners();
    try {
      // Serial scope processing also bounds remote/manual decodes; embedded
      // extraction continues through CoverCache's existing shared limiter.
      for (final target in targets) {
        if (retryOnly
            ? !target.retryable
            : target.status != CoverRepairStatus.ready) {
          continue;
        }
        if (cancellationRequested) {
          target.status = CoverRepairStatus.cancelled;
          continue;
        }
        try {
          target.reason = '';
          target.status = await (_repair?.call(target) ?? _reread(target));
        } catch (error) {
          target.status = CoverRepairStatus.failed;
          target.reason = error.toString();
        }
        notifyListeners();
      }
    } finally {
      busy = false;
      if (_repair == null) AudioLibrary.instance.publishArtworkChanges();
      notifyListeners();
    }
  }

  Future<CoverRepairStatus> _reread(CoverRepairTarget target) async {
    ImageProvider? image;
    if (target.group != null) {
      image = await _covers.reread(target.group!);
      if (image == null) return CoverRepairStatus.unreadable;
    } else {
      final audio = target.audio!;
      if (audio.localFilePath != target.source) {
        return CoverRepairStatus.unreadable;
      }
      if (audio.isLocal) {
        try {
          if ((await File(audio.localFilePath)
                      .stat()
                      .timeout(const Duration(seconds: 3)))
                  .type !=
              FileSystemEntityType.file) {
            return CoverRepairStatus.unreadable;
          }
        } on FileSystemException {
          return CoverRepairStatus.unreadable;
        }
      } else {
        // Explicitly reread the already selected URL; no search or rematching.
        await (await audio.mediumCover)?.evict();
      }
      await CoverCache.instance.invalidate(audio.localFilePath);
      image = await audio
          .coverForDisplay(size: 200, devicePixelRatio: 1)
          .timeout(const Duration(seconds: 15));
      if (image == null) return CoverRepairStatus.noArtwork;
    }
    final bounded = ArtworkImageProvider(image, const ArtworkSize(256, 256));
    await bounded.evict();
    return await _decode(bounded)
        ? CoverRepairStatus.success
        : CoverRepairStatus.failed;
  }

  static Future<bool> _decode(ImageProvider image) async {
    final completer = Completer<bool>();
    final stream = image.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      info.dispose();
      if (!completer.isCompleted) completer.complete(true);
    }, onError: (Object error, StackTrace? trace) {
      if (!completer.isCompleted) completer.complete(false);
    });
    stream.addListener(listener);
    try {
      return await completer.future
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
    } finally {
      stream.removeListener(listener);
    }
  }
}
