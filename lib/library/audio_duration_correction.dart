import 'dart:async';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/utils.dart';

typedef DurationCorrectionDelay = Future<void> Function(Duration duration);

const _durationReaderVersion = 1;
const _maximumDurationSeconds = 0x7fffffff;

/// A finite duration already obtained from an opened native stream.
///
/// The scanner and BASS can disagree by one second because the index stores
/// whole seconds. Keep that harmless rounding difference stable; zero and
/// larger disagreements are corrected.
int? verifiedPlaybackDuration(double engineSeconds) {
  if (!engineSeconds.isFinite || engineSeconds <= 0) return null;
  final seconds = engineSeconds.floor();
  if (seconds <= 0 || seconds > _maximumDurationSeconds) return null;
  return seconds;
}

class _PendingDuration {
  _PendingDuration(Audio audio, this.verifiedSeconds)
      : path = audio.path,
        modified = audio.modified,
        modifiedNanos = audio.modifiedNanos,
        fileSizeBytes = audio.fileSizeBytes;

  final String path;
  final int modified;
  final String? modifiedNanos;
  final int? fileSizeBytes;
  final int verifiedSeconds;

  bool matches(Audio audio) =>
      audio.isLocal &&
      audio.path == path &&
      audio.modified == modified &&
      audio.modifiedNanos == modifiedNanos &&
      audio.fileSizeBytes == fileSizeBytes;
}

/// Coalesces player-verified durations and persists them without delaying
/// playback. Existing refresh/metadata operations retain exclusive ownership
/// of the index through [LibraryMutationGate].
class AudioDurationCorrectionCoordinator {
  AudioDurationCorrectionCoordinator({
    required Audio? Function(String path) lookup,
    required Future<void> Function() persist,
    required void Function() publish,
    LibraryMutationGate? gate,
    DurationCorrectionDelay? delay,
    void Function(Object error, StackTrace stackTrace)? onError,
    this.maxBusyRetries = 5,
    this.debounce = Duration.zero,
  })  : _lookup = lookup,
        _persist = persist,
        _publish = publish,
        _gate = gate ?? LibraryMutationGate.shared,
        _delay = delay ?? Future<void>.delayed,
        _onError = onError ?? _logFailure;

  final Audio? Function(String path) _lookup;
  final Future<void> Function() _persist;
  final void Function() _publish;
  final LibraryMutationGate _gate;
  final DurationCorrectionDelay _delay;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final int maxBusyRetries;
  final Duration debounce;

  final Map<String, _PendingDuration> _pending = {};
  Future<void>? _drainFuture;

  void observe(Audio audio, double engineSeconds) {
    if (!audio.isLocal) return;
    final verified = verifiedPlaybackDuration(engineSeconds);
    if (verified == null) return;
    if (audio.durationVersion >= _durationReaderVersion &&
        audio.duration > 0 &&
        (audio.duration - verified).abs() < 2) {
      return;
    }
    _pending[audio.path] = _PendingDuration(audio, verified);
    _ensureDrain();
  }

  void _ensureDrain() {
    if (_drainFuture != null) return;
    final future = Future<void>.microtask(_drain);
    _drainFuture = future;
    unawaited(future.then<void>(
      (_) => _finishDrain(future),
      onError: (Object error, StackTrace stackTrace) {
        _onError(error, stackTrace);
        _finishDrain(future);
      },
    ));
  }

  void _finishDrain(Future<void> completed) {
    if (!identical(_drainFuture, completed)) return;
    _drainFuture = null;
    if (_pending.isNotEmpty) _ensureDrain();
  }

  Future<void> _drain() async {
    if (debounce > Duration.zero) await _delay(debounce);
    var busyRetries = 0;
    while (_pending.isNotEmpty) {
      final batch = Map<String, _PendingDuration>.of(_pending);
      try {
        await _gate.run(() => _commit(batch.values));
        _removeHandled(batch);
        busyRetries = 0;
      } on LibraryMutationBusy catch (error, stackTrace) {
        if (busyRetries >= maxBusyRetries) {
          _removeHandled(batch);
          _onError(error, stackTrace);
          return;
        }
        final shift = busyRetries > 4 ? 4 : busyRetries;
        final milliseconds = 100 << shift;
        busyRetries++;
        await _delay(Duration(milliseconds: milliseconds));
      } catch (error, stackTrace) {
        _removeHandled(batch);
        _onError(error, stackTrace);
      }
    }
  }

  void _removeHandled(Map<String, _PendingDuration> batch) {
    for (final entry in batch.entries) {
      if (identical(_pending[entry.key], entry.value)) {
        _pending.remove(entry.key);
      }
    }
  }

  Future<void> _commit(Iterable<_PendingDuration> requests) async {
    final originals = <Audio, ({int duration, int version})>{};
    var durationChanged = false;
    for (final request in requests) {
      final audio = _lookup(request.path);
      if (audio == null || !request.matches(audio)) continue;
      final corrected = audio.duration <= 0 ||
              (audio.duration - request.verifiedSeconds).abs() >= 2
          ? request.verifiedSeconds
          : audio.duration;
      if (corrected == audio.duration &&
          audio.durationVersion >= _durationReaderVersion) {
        continue;
      }
      originals[audio] =
          (duration: audio.duration, version: audio.durationVersion);
      durationChanged = durationChanged || corrected != audio.duration;
      audio.duration = corrected;
      audio.durationVersion = _durationReaderVersion;
    }
    if (originals.isEmpty) return;

    try {
      await _persist();
    } catch (_) {
      for (final entry in originals.entries) {
        entry.key.duration = entry.value.duration;
        entry.key.durationVersion = entry.value.version;
      }
      rethrow;
    }
    if (durationChanged) _publish();
  }

  /// Test/shutdown observability only; normal playback never awaits disk I/O.
  Future<void> get settled async {
    while (true) {
      final current = _drainFuture;
      if (current == null) return;
      await current;
    }
  }

  static void _logFailure(Object error, StackTrace stackTrace) {
    LOGGER.w(
      '[duration correction] cache update was skipped (${error.runtimeType})',
      stackTrace: stackTrace,
    );
  }
}

final audioDurationCorrections = AudioDurationCorrectionCoordinator(
  lookup: (path) => AudioLibrary.instance.audioByPath[path],
  // A successful scan replaces the library instance. Resolve all callbacks at
  // commit time so a later duration correction cannot save an old whole index.
  persist: () => AudioLibrary.instance.saveIndex(),
  publish: () => AudioLibrary.instance.publishDurationChanges(),
  debounce: const Duration(seconds: 2),
);
