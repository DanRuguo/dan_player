import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';

/// Persists remote track metadata separately from the local file index.
///
/// A remote entry only stores public metadata and a stable provider id. Signed
/// playback URLs are deliberately resolved just before playback and are never
/// written to disk because they usually expire.
class OnlineLibrary extends ChangeNotifier {
  OnlineLibrary._();

  static final OnlineLibrary instance = OnlineLibrary._();

  final List<Audio> _audios = [];
  List<Audio> get audios => List.unmodifiable(_audios);
  Future<void> _operationTail = Future.value();
  bool _preserveBackup = false;

  bool contains(Audio audio) =>
      _audios.any((item) => item.path == audio.path && item.isOnline);

  Future<void> initialize() async {
    _audios.clear();
    _preserveBackup = false;
    var recoveredFromBackup = false;
    var loaded = false;
    try {
      final supportPath = (await getAppDataDir()).path;
      final target = File("$supportPath\\online_library.json");
      final backup = File("${target.path}.bak");
      Object? targetError;
      for (final file in [target, backup]) {
        if (!await file.exists()) continue;
        try {
          final decoded = json.decode(await file.readAsString());
          if (decoded is! Map) {
            throw const FormatException(
                "Online library root must be an object");
          }
          final entries = decoded["tracks"];
          if (entries is! List) {
            throw const FormatException("Online library tracks must be a list");
          }
          final seen = <String>{};
          for (final entry in entries) {
            if (entry is! Map) continue;
            try {
              final audio = Audio.fromOnlineMap(entry);
              if (seen.add(audio.path)) _audios.add(audio);
            } catch (error) {
              LOGGER.w("[online library] skipped invalid entry: $error");
            }
          }
          recoveredFromBackup = file.path == backup.path;
          loaded = true;
          if (recoveredFromBackup) {
            LOGGER.w("[online library] recovered from backup");
          }
          break;
        } catch (error) {
          targetError ??= error;
          _audios.clear();
        }
      }
      if (!loaded && targetError != null) throw targetError;
      if (recoveredFromBackup) {
        _preserveBackup = true;
        await _save();
      }
    } catch (error, trace) {
      LOGGER.e("[online library] failed to load: $error", stackTrace: trace);
    }
    _publish();
  }

  Future<void> add(Audio audio) async {
    if (!audio.isOnline) {
      throw ArgumentError.value(audio.path, "audio", "must be an online track");
    }
    return _enqueue(() async {
      final previous = List<Audio>.from(_audios);
      final index = _audios.indexWhere((item) => item.path == audio.path);
      if (index >= 0) {
        final existing = _audios[index];
        _audios[index] = Audio.online(
          provider: audio.onlineProvider!,
          id: audio.onlineId!,
          title: audio.title,
          artist: audio.artist,
          album: audio.album,
          duration: audio.duration,
          mediaId: audio.onlineMediaId,
          numericId: audio.onlineNumericId,
          artworkUrl: audio.artworkUrl,
          playable: audio.onlinePlayable,
          downloadAllowed: audio.onlineDownloadAllowed,
          bitrate: audio.bitrate,
          created: existing.created,
          language: audio.language ?? existing.language,
          composer: audio.composer ?? existing.composer,
          albumArtist: audio.albumArtist ?? existing.albumArtist,
          classificationVersion:
              audio.classificationVersion > existing.classificationVersion
                  ? audio.classificationVersion
                  : existing.classificationVersion,
        );
      } else {
        _audios.add(audio);
      }
      try {
        await _save();
        _publish();
      } catch (_) {
        _audios
          ..clear()
          ..addAll(previous);
        _publish();
        rethrow;
      }
    });
  }

  Future<void> remove(Audio audio) async {
    return _enqueue(() async {
      final previous = List<Audio>.from(_audios);
      _audios.removeWhere((item) => item.path == audio.path);
      if (_audios.length == previous.length) return;
      try {
        await _save();
        _publish();
      } catch (_) {
        _audios
          ..clear()
          ..addAll(previous);
        _publish();
        rethrow;
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  void _publish() {
    AudioLibrary.instance.replaceOnlineAudios(_audios);
    notifyListeners();
  }

  Future<void> _save() async {
    final supportPath = (await getAppDataDir()).path;
    final target = File("$supportPath\\online_library.json");
    final temporary = File("${target.path}.tmp");
    final backup = File("${target.path}.bak");
    await target.parent.create(recursive: true);
    await temporary.writeAsString(
      const JsonEncoder.withIndent("  ").convert({
        "version": 1,
        "tracks": _audios.map((audio) => audio.toOnlineMap()).toList(),
      }),
      flush: true,
    );
    try {
      // Recovery must keep the known-good backup. The primary file is known
      // to be invalid and must never replace the only usable recovery copy.
      if (!_preserveBackup) {
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      _preserveBackup = false;
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }
}
