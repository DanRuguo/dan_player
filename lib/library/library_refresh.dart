import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';

typedef _Stamp = ({int modified, String? nanos, int? size, bool pending});

/// Owns the native stream independently of a dialog. Losing the view does not
/// cancel Rust: this task waits for commit and reload before releasing its gate.
class LibraryRefreshTask {
  LibraryRefreshTask(
      {required this.scan, required this.commit, LibraryMutationGate? gate})
      : _gate = gate ?? LibraryMutationGate.shared;

  final Stream<IndexActionState> Function() scan;
  final Future<int> Function() commit;
  final LibraryMutationGate _gate;
  late final _progress =
      StreamController<IndexActionState>.broadcast(onListen: _start);
  final _completed = Completer<void>();
  bool _started = false;
  Object? error;
  int pendingMetadata = 0;
  Stream<IndexActionState> get stream => _progress.stream;
  Future<void> get completed => _completed.future;

  void _start() {
    if (_started) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await _gate.run(() async {
        await for (final action in scan()) {
          _progress.add(action);
        }
        pendingMetadata = await commit();
      });
    } catch (failure, stackTrace) {
      error = failure;
      LOGGER.e('[library refresh] operation failed',
          error: failure, stackTrace: stackTrace);
      if (_progress.hasListener) _progress.addError(failure, stackTrace);
    } finally {
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
