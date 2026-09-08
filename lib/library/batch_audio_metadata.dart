import 'dart:convert';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_metadata_update.dart';
import 'package:dan_player/src/rust/api/metadata_preflight.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class MetadataFileSnapshot {
  const MetadataFileSnapshot(
      {required this.fingerprint,
      required this.title,
      required this.artist,
      required this.album,
      this.supported = true,
      this.readOnly = false,
      this.reason = '',
      this.sourceKey});
  final String? sourceKey;
  final String fingerprint, title, artist, album, reason;
  final bool supported, readOnly;

  static Future<MetadataFileSnapshot> read(String path) async {
    final map = jsonDecode(await preflightAudioMetadata(path: path)) as Map;
    return MetadataFileSnapshot(
        fingerprint: map['fingerprint'] as String,
        title: map['title'] as String? ?? '',
        artist: map['artist'] as String? ?? '',
        album: map['album'] as String? ?? '',
        supported: map['supported'] == true,
        readOnly: map['readOnly'] == true,
        reason: map['reason'] as String? ?? '',
        sourceKey: map['sourceKey'] as String?);
  }

  bool sameFile(MetadataFileSnapshot other) =>
      fingerprint == other.fingerprint &&
      sourceKey == other.sourceKey &&
      title == other.title &&
      artist == other.artist &&
      album == other.album;
}

enum BatchMetadataStatus {
  ready,
  success,
  unchanged,
  skipped,
  failed,
  pendingSync,
  cancelled
}

/// Null means leave untouched; blanks are never implicit clearing operations.
class BatchMetadataDraft {
  BatchMetadataDraft(
      {this.artist, this.album, Map<String, String> titles = const {}})
      : titles = Map.unmodifiable(titles);
  final String? artist, album;
  final Map<String, String> titles;
  String? get validationError => [artist, album, ...titles.values]
          .any((value) => value != null && value.trim().isEmpty)
      ? '要设置的标签不能为空；保留原值请关闭该字段的修改开关'
      : null;
}

class BatchMetadataTarget {
  BatchMetadataTarget(this.audio)
      : path = audio.path,
        trackId = audio.stableTrackId,
        modelFields = (audio.title, audio.artist, audio.album);
  final Audio audio;
  final String path, trackId;
  final (String, String, String) modelFields;
  bool wasInLibrary = false;
  MetadataFileSnapshot? before;
  AudioMetadataEdit? edit;
  BatchMetadataStatus status = BatchMetadataStatus.ready;
  String reason = '';
  bool get retryable =>
      status == BatchMetadataStatus.failed ||
      status == BatchMetadataStatus.pendingSync;
}

/// Owns immutable targets, no selection/list position is consulted after open.
/// Cancelling never claims that already committed media have been rolled back.
class BatchAudioMetadata extends ChangeNotifier {
  BatchAudioMetadata(
    Iterable<Audio> audios, {
    Future<MetadataFileSnapshot> Function(String)? inspect,
    Future<Audio> Function(Audio, AudioMetadataEdit)? apply,
    Audio? Function(String)? currentAudio,
  })  : _inspect = inspect ?? MetadataFileSnapshot.read,
        _apply = apply ?? applyAudioMetadataEdit,
        _current = currentAudio ??
            ((path) => AudioLibrary.instance.audioByPath[path]) {
    final seen = <String>{};
    targets = List.unmodifiable([
      for (final audio in audios)
        if (seen.add(TrackIdentityRegistry.normalizePath(
            audio.isCueTrack ? audio.path : audio.localFilePath)))
          BatchMetadataTarget(audio),
    ]);
    for (final target in targets) {
      target.wasInLibrary = _current(target.path) != null;
    }
  }
  late final List<BatchMetadataTarget> targets;
  final Future<MetadataFileSnapshot> Function(String) _inspect;
  final Future<Audio> Function(Audio, AudioMetadataEdit) _apply;
  final Audio? Function(String) _current;
  bool busy = false, previewed = false, cancellationRequested = false;
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

  String? commonValue(String Function(Audio) value) {
    if (targets.isEmpty) return '';
    final values = targets.map((entry) => value(entry.audio)).toSet();
    return values.length == 1 ? values.single : null;
  }

  void cancel() {
    cancellationRequested = true;
    notifyListeners();
  }

  int count(BatchMetadataStatus status) =>
      targets.where((entry) => entry.status == status).length;

  Future<void> preview(BatchMetadataDraft draft) async {
    if (busy) return;
    if (draft.validationError != null) {
      throw FormatException(draft.validationError!);
    }
    busy = true;
    cancellationRequested = false;
    notifyListeners();
    try {
      final physicalSources = <String>{};
      for (final target in targets) {
        target.reason = '';
        target.edit = null;
        if (cancellationRequested) {
          target.status = BatchMetadataStatus.cancelled;
          continue;
        }
        if (target.audio.isOnline || target.audio.isCueTrack) {
          target.status = BatchMetadataStatus.skipped;
          target.reason =
              target.audio.isOnline ? '联网歌曲不能写入本地标签' : 'CUE 分轨不能修改整轨音频标签';
          continue;
        }
        try {
          final before = await _inspect(target.path);
          target.before = before;
          if (before.sourceKey != null &&
              !physicalSources.add(before.sourceKey!)) {
            target.status = BatchMetadataStatus.skipped;
            target.reason = '同一物理文件的重复引用，仅处理一次';
            continue;
          }
          if (!before.supported || before.readOnly) {
            target.status = BatchMetadataStatus.skipped;
            target.reason = before.readOnly ? '文件为只读' : before.reason;
            continue;
          }
          final edit = AudioMetadataEdit(
              fileName: p.basename(target.path),
              title: draft.titles[target.trackId]?.trim() ?? before.title,
              artist: draft.artist?.trim() ?? before.artist,
              album: draft.album?.trim() ?? before.album,
              expectedFingerprint: before.fingerprint,
              preserveEmptyValues: true);
          target.edit = edit;
          target.status = edit.title == before.title &&
                  edit.artist == before.artist &&
                  edit.album == before.album
              ? BatchMetadataStatus.unchanged
              : BatchMetadataStatus.ready;
        } catch (error) {
          target.status = BatchMetadataStatus.skipped;
          target.reason = error.toString();
        }
        notifyListeners();
      }
      previewed = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> apply({bool retryOnly = false}) async {
    if (busy || !previewed) return;
    busy = true;
    cancellationRequested = false;
    notifyListeners();
    // Pending sync must finish before another file can enter the native writer.
    final ordered = [
      ...targets
          .where((entry) => entry.status == BatchMetadataStatus.pendingSync),
      ...targets
          .where((entry) => entry.status != BatchMetadataStatus.pendingSync)
    ];
    try {
      for (final target in ordered) {
        if (retryOnly
            ? !target.retryable
            : target.status != BatchMetadataStatus.ready && !target.retryable) {
          continue;
        }
        if (cancellationRequested) {
          if (target.status != BatchMetadataStatus.pendingSync) {
            target.status = BatchMetadataStatus.cancelled;
          }
          continue;
        }
        try {
          if (target.status != BatchMetadataStatus.pendingSync) {
            final live = _current(target.path);
            final current = live ?? target.audio;
            if ((target.wasInLibrary && live == null) ||
                current.path != target.path ||
                current.stableTrackId != target.trackId ||
                (current.title, current.artist, current.album) !=
                    target.modelFields) {
              target.status = BatchMetadataStatus.skipped;
              target.reason = '预览后歌曲身份、位置或标签已改变，请重新打开预览';
              continue;
            }
            final now = await _inspect(target.path);
            if (now.readOnly ||
                !now.supported ||
                !target.before!.sameFile(now)) {
              target.status = BatchMetadataStatus.skipped;
              target.reason = '预览后文件已改变或不可写，请重新打开预览';
              continue;
            }
            if (cancellationRequested) {
              target.status = BatchMetadataStatus.cancelled;
              continue;
            }
          }
          await _apply(target.audio, target.edit!);
          target.status = BatchMetadataStatus.success;
          target.reason = '';
        } catch (error) {
          final native = AudioMetadataEditException.fromNative(error);
          target.status = native.fileWasUpdated
              ? BatchMetadataStatus.pendingSync
              : BatchMetadataStatus.failed;
          target.reason = native.userMessage;
          if (native.fileWasUpdated ||
              native.code == 'TAG_LIBRARY_SYNC_PENDING') {
            break;
          }
        } finally {
          notifyListeners();
        }
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
