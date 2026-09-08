import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';

typedef _Stamp = ({int modified, String? nanos, int? size, bool pending});

enum LibraryRefreshPhase {
  scanning,
  cancelling,
  committing,
  cancelled,
  completed,
  failed
}

class LibraryScanCancelled implements Exception {
  const LibraryScanCancelled();
  @override
  String toString() => 'INDEX_SCAN_CANCELLED';
}

/// The task owns the native stream and mutation gate, not the progress view.
/// Cancellation is acknowledged only after native discovery exits safely.
class LibraryRefreshTask extends ChangeNotifier {
  LibraryRefreshTask(
      {required this.scan,
      required this.commit,
      this.cancelNative,
      this.releaseNative,
      this.incremental = true,
      LibraryMutationGate? gate})
      : _gate = gate ?? LibraryMutationGate.shared;

  factory LibraryRefreshTask.native({
    required List<String> folders,
    required Directory indexPath,
    required bool incremental,
    required Future<int> Function() commit,
    LibraryMutationGate? gate,
  }) {
    final selected = List<String>.unmodifiable(folders);
    String? id;
    return LibraryRefreshTask(
      incremental: incremental,
      gate: gate,
      scan: () {
        id = createIndexScanTask();
        return incremental
            ? updateIndex(indexPath: indexPath.path, taskId: id)
            : buildIndexFromFoldersRecursively(
                folders: selected, indexPath: indexPath.path, taskId: id);
      },
      commit: commit,
      cancelNative: () =>
          id == null ? 'cancelling' : cancelIndexScanTask(taskId: id!),
      releaseNative: () {
        if (id != null) releaseIndexScanTask(taskId: id!);
      },
    );
  }

  static final active = ValueNotifier<LibraryRefreshTask?>(null);

  final Stream<IndexActionState> Function() scan;
  final Future<int> Function() commit;
  final FutureOr<String> Function()? cancelNative;
  final FutureOr<void> Function()? releaseNative;
  final bool incremental;
  final LibraryMutationGate _gate;
  late final _progress =
      StreamController<IndexActionState>.broadcast(onListen: _start);
  final _completed = Completer<void>();
  bool _started = false;
  bool _cancelRequested = false;
  bool _completionNoticeTaken = false;
  LibraryRefreshPhase phase = LibraryRefreshPhase.scanning;
  IndexActionState? lastAction;
  Object? error;
  int pendingMetadata = 0;
  Stream<IndexActionState> get stream => _progress.stream;
  Future<void> get completed => _completed.future;
  bool get isTerminal => switch (phase) {
        LibraryRefreshPhase.cancelled ||
        LibraryRefreshPhase.completed ||
        LibraryRefreshPhase.failed =>
          true,
        _ => false,
      };
  bool get canCancel =>
      cancelNative != null && phase == LibraryRefreshPhase.scanning;

  bool takeCompletionNotice() {
    if (!isTerminal || _completionNoticeTaken) return false;
    _completionNoticeTaken = true;
    return true;
  }

  void start() => _start();

  void _setPhase(LibraryRefreshPhase value) {
    if (phase == value) return;
    phase = value;
    notifyListeners();
  }

  Future<void> requestCancel() async {
    if (!canCancel) return;
    _cancelRequested = true;
    _setPhase(LibraryRefreshPhase.cancelling);
    try {
      final response = await cancelNative!();
      if (isTerminal) return;
      if (response == 'committing' || response == 'finished') {
        // A completed native commit may still be waiting for Dart reload.
        _cancelRequested = false;
        _setPhase(LibraryRefreshPhase.committing);
      }
    } catch (failure, trace) {
      // A bridge failure is not confirmation of cancellation.
      _cancelRequested = false;
      if (!isTerminal && phase != LibraryRefreshPhase.committing) {
        _setPhase(LibraryRefreshPhase.scanning);
      }
      LOGGER.w('[library cancellation] $failure', stackTrace: trace);
    }
  }

  void _start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await _gate.run(() async {
        active.value = this;
        if (_cancelRequested) throw const LibraryScanCancelled();
        await for (final action in scan()) {
          lastAction = action;
          if (action.message == 'INDEX_PHASE_COMMITTING') {
            _cancelRequested = false;
            _setPhase(LibraryRefreshPhase.committing);
          }
          _progress.add(action);
          notifyListeners();
        }
        // A successful native stream means its atomic commit finished. Do
        // not discard that result because a cancellation reply arrived late.
        _setPhase(LibraryRefreshPhase.committing);
        pendingMetadata = await commit();
        _setPhase(LibraryRefreshPhase.completed);
      });
    } catch (failure, stackTrace) {
      if (failure is LibraryScanCancelled ||
          '$failure'.contains('INDEX_SCAN_CANCELLED')) {
        _setPhase(LibraryRefreshPhase.cancelled);
        if (_progress.hasListener) {
          _progress.addError(const LibraryScanCancelled(), stackTrace);
        }
      } else {
        error = failure;
        _setPhase(LibraryRefreshPhase.failed);
        LOGGER.e('[library refresh] operation failed',
            error: failure, stackTrace: stackTrace);
        if (_progress.hasListener) _progress.addError(failure, stackTrace);
      }
    } finally {
      try {
        await releaseNative?.call();
      } catch (failure) {
        LOGGER.w('[library scan cleanup] $failure');
      }
      if (identical(active.value, this)) active.value = null;
      unawaited(_progress.close());
      _completed.complete();
    }
  }
}

/// Frozen before a scan; never holds mutable Audio references. Local entries
/// only, so an index refresh cannot evict online-library artwork.
class LibraryRefreshSnapshot {
  LibraryRefreshSnapshot._(this._entries);
  final Map<String, _Stamp> _entries;

  int get pendingCount =>
      _entries.values.where((stamp) => stamp.pending).length;

  factory LibraryRefreshSnapshot.capture(Iterable<Audio> audios) =>
      LibraryRefreshSnapshot._({
        for (final audio in audios)
          if (audio.isLocal)
            audio.path: (
              modified: audio.modified,
              nanos: audio.modifiedNanos,
              size: audio.fileSizeBytes,
              pending: audio.metadataReadPending
            ),
      });

  factory LibraryRefreshSnapshot.fromIndex(Map index) {
    final entries = <String, _Stamp>{};
    final folders = index['folders'];
    if (folders is! List) {
      throw const FormatException('Invalid library folders');
    }
    for (final folder in folders) {
      if (folder is! Map || folder['audios'] is! List) {
        throw const FormatException('Invalid library folder');
      }
      for (final audio in folder['audios'] as List) {
        if (audio is! Map || audio['path'] is! String) {
          throw const FormatException('Invalid library audio');
        }
        entries[audio['path'] as String] = (
          modified: (audio['modified'] as num?)?.toInt() ?? 0,
          nanos: audio['modified_ns'] as String?,
          size: (audio['file_size'] as num?)?.toInt(),
          pending: audio['metadata_pending'] == true,
        );
      }
    }
    return LibraryRefreshSnapshot._(entries);
  }

  static Future<LibraryRefreshSnapshot> read(File file) async =>
      LibraryRefreshSnapshot.fromIndex(
          jsonDecode(await file.readAsString()) as Map);

  Set<String> changedPaths(LibraryRefreshSnapshot next) => {
        for (final path in {..._entries.keys, ...next._entries.keys})
          if (_entries[path] != next._entries[path] ||
              next._entries[path]?.pending == true)
            path,
      };
}

/// Invoke only after the scanner completed successfully. Validation happens
/// before cache changes; native scan errors never reach this completion path.
Future<int> completeLibraryRefresh({
  required bool incremental,
  required LibraryRefreshSnapshot before,
  required Future<LibraryRefreshSnapshot> Function() readCommitted,
  required Future<void> Function(String path) invalidateCover,
  required Future<void> Function() clearCovers,
  required Future<void> Function() reload,
}) async {
  final after = await readCommitted();
  if (incremental) {
    for (final path in before.changedPaths(after)) {
      await invalidateCover(path);
    }
  } else {
    await clearCovers();
  }
  await reload();
  return after.pendingCount;
}
