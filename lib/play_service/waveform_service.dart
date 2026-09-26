import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/data/protected_json_store.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/src/bass/bass_waveform.dart';
import 'package:path/path.dart' as p;

typedef WaveformDecoder = Future<WaveformData?> Function(
    WaveformDecodeRequest, WaveformCancellation);

/// One decoder per process, even during rapid switching. Cache keys include
/// physical file revision and CUE boundaries, never the current playback rate.
class WaveformService {
  WaveformService(
      {File? cacheFile, WaveformDecoder? decoder, String? libraryPath})
      : _cacheFile = cacheFile,
        _decoder = decoder ?? decodeBassWaveform,
        _libraryPath = libraryPath ??
            p.join(p.dirname(Platform.resolvedExecutable), 'BASS', 'bass.dll');
  static final shared = WaveformService();
  final File? _cacheFile;
  final WaveformDecoder _decoder;
  final String _libraryPath;
  Future<void> _tail = Future.value();
  final _requests = <WaveformCancellation, (String, Future<WaveformData?>)>{};
  final _blockedPaths = <String, int>{};
  String _pathKey(String path) => p.normalize(p.absolute(path)).toLowerCase();
  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  ProtectedJsonStore? _cache;
  bool _cacheBlocked = false;
  bool _closed = false;
  Future<void>? _closeFuture;

  Future<ProtectedJsonStore?> _store() async {
    if (_cacheBlocked) return null;
    return _cache ??= ProtectedJsonStore(
        _cacheFile ??
            File(p.join((await getAppDataDir()).path, 'waveform_cache.json')),
        validate: validateCache,
        maxBytes: 2 * 1024 * 1024);
  }

  static void validateCache(Map<String, dynamic> root) {
    final entries = root['entries'];
    if (root['version'] != 1 || (entries != null && entries is! Map)) {
      throw const FormatException('Invalid waveform cache');
    }
    if (entries == null) return;
    if ((entries as Map).length > 128) {
      throw const FormatException('Waveform cache capacity');
    }
    for (final entry in entries.entries) {
      final data = entry.value;
      if (entry.key is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key as String) ||
          data is! Map ||
          data['duration'] is! num ||
          !(data['duration'] as num).isFinite ||
          data['duration'] <= 0 ||
          data['duration'] > 7200 ||
          data['peaks'] is! List ||
          (data['peaks'] as List).length != 512 ||
          (data['peaks'] as List).any((value) =>
              value is! num || !value.isFinite || value < 0 || value > 1)) {
        throw const FormatException('Invalid waveform data');
      }
      for (final field in ['sourceKey', 'trackKey', 'sourceRevision']) {
        final value = data[field];
        if (value != null &&
            (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value))) {
          throw const FormatException('Invalid waveform binding');
        }
      }
    }
  }

  Future<WaveformData?> load(Audio audio, WaveformCancellation cancellation) {
    if (_closed) return Future.value(null);
    late final Future<WaveformData?> next;
    next = _tail.then((_) => _load(audio, cancellation)).whenComplete(() {
      _requests.remove(cancellation);
    });
    _requests[cancellation] = (audio.localFilePath, next);
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  /// Drain before BASS unloads codec plugins, which also own decoding streams.
  Future<void> close() => _closeFuture ??= (() async {
        _closed = true;
        final pending = _requests.entries.toList();
        for (final entry in pending) {
          entry.key.cancel();
        }
        await Future.wait(pending.map((entry) => entry.value.$2
            .then<void>((_) {}, onError: (Object _, StackTrace __) {})));
      })();

  /// Deletion, replacement and tag writes must wait for our read handle too.
  /// Path matching includes every CUE segment of the same physical source.
  Future<void> cancelForPath(String path) async {
    final normalized = _pathKey(path);
    final affected = _requests.entries
        .where((entry) => _pathKey(entry.value.$1) == normalized)
        .toList();
    for (final entry in affected) {
      entry.key.cancel();
    }
    await Future.wait(affected.map((entry) => entry.value.$2
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})));
  }

  /// A successful deletion/replacement retires every CUE envelope belonging
  /// to this source. Optional cache failures never undo a completed mutation.
  Future<void> invalidatePath(String path) async {
    if (_cacheBlocked) return;
    try {
      final file = _cacheFile ??
          File(p.join((await getAppDataDir()).path, 'waveform_cache.json'));
      if (!await file.exists()) return;
      final store = await _store();
      final sourceKey = _hash(_pathKey(path));
      final entries = (await store?.snapshot())?['entries'] as Map?;
      if (entries == null ||
          !entries.values.any(
              (value) => value is Map && value['sourceKey'] == sourceKey)) {
        return;
      }
      await store?.update((root) {
        final current =
            Map<String, dynamic>.from((root['entries'] as Map?) ?? {});
        current.removeWhere(
            (_, value) => value is Map && value['sourceKey'] == sourceKey);
        root['entries'] = current;
      });
    } catch (_) {
      _cacheBlocked = true;
    }
  }

  Future<T> withSourceReleased<T>(
      String path, Future<T> Function() action) async {
    final key = _pathKey(path);
    _blockedPaths[key] = (_blockedPaths[key] ?? 0) + 1;
    try {
      await cancelForPath(path);
      return await action();
    } finally {
      final remaining = _blockedPaths[key]! - 1;
      if (remaining == 0) {
        _blockedPaths.remove(key);
      } else {
        _blockedPaths[key] = remaining;
      }
    }
  }

  Future<WaveformData?> _load(
      Audio audio, WaveformCancellation cancellation) async {
    if (cancellation.cancelled) return null;
    if (_blockedPaths.containsKey(_pathKey(audio.localFilePath))) return null;
    if (audio.isOnline) {
      throw const WaveformUnavailable(WaveformFailure.online);
    }
    if (audio.duration > 7200) {
      throw const WaveformUnavailable(WaveformFailure.tooLong);
    }
    final file = File(audio.localFilePath);
    final before = await file.stat();
    if (cancellation.cancelled) return null;
    if (_blockedPaths.containsKey(_pathKey(audio.localFilePath))) return null;
    if (before.type != FileSystemEntityType.file) {
      throw const WaveformUnavailable(WaveformFailure.missing);
    }
    final cue = audio.cueTrack;
    final request = WaveformDecodeRequest(_libraryPath, file.absolute.path,
        start: cue?.startSeconds ?? 0, end: cue?.endSeconds);
    final sourceKey = _hash(_pathKey(file.path));
    final trackKey = _hash(audio.stableTrackId);
    final sourceRevision = _hash([
      before.size,
      before.modified.microsecondsSinceEpoch,
    ]);
    final key = _hash([
      'amplitude-rms-peak-v3-bound-prescan',
      sourceKey,
      trackKey,
      before.size,
      before.modified.microsecondsSinceEpoch,
      request.start,
      request.end,
    ]);
    ProtectedJsonStore? store;
    try {
      store = await _store();
      final cached = (await store?.snapshot())?['entries'] as Map?;
      final hit = cached?[key] as Map?;
      if (hit != null && !cancellation.cancelled) {
        final current = await file.stat();
        if (current.type != before.type ||
            current.size != before.size ||
            current.modified != before.modified) {
          throw const WaveformUnavailable(WaveformFailure.changed);
        }
        if (cancellation.cancelled) return null;
        return WaveformData((hit['duration'] as num).toDouble(),
            (hit['peaks'] as List).map((value) => (value as num).toDouble()));
      }
    } on WaveformUnavailable {
      rethrow;
    } catch (_) {
      // Optional cache failures do not prevent waveform display. Unknown
      // versions and malformed files remain untouched; no silent overwrite.
      _cacheBlocked = true;
      store = null;
    }
    if (cancellation.cancelled) return null;
    final data = await _decoder(request, cancellation);
    if (data == null || cancellation.cancelled) return null;
    validateCache({
      'version': 1,
      'entries': {
        key: {
          'duration': data.duration,
          'peaks': data.peaks,
        }
      }
    });
    final after = await file.stat();
    if (cancellation.cancelled) return null;
    if (after.type != before.type ||
        after.size != before.size ||
        after.modified != before.modified) {
      throw const WaveformUnavailable(WaveformFailure.changed);
    }
    try {
      await store?.update((root) {
        final entries =
            Map<String, dynamic>.from((root['entries'] as Map?) ?? {});
        entries.removeWhere((_, value) =>
            value is Map &&
            value['sourceKey'] == sourceKey &&
            value['sourceRevision'] != sourceRevision);
        entries.remove(key);
        while (entries.length >= 128) {
          entries.remove(entries.keys.first);
        }
        entries[key] = {
          'duration': data.duration,
          'peaks': data.peaks,
          'sourceKey': sourceKey,
          'trackKey': trackKey,
          'sourceRevision': sourceRevision,
        };
        root['entries'] = entries;
      });
    } catch (_) {
      // Display the completed analysis even if persistence is unavailable.
    }
    return cancellation.cancelled ? null : data;
  }
}
