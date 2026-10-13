import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:flutter_test/flutter_test.dart';

LibraryRefreshSnapshot snapshot({required bool includeA, int bSize = 100}) =>
    LibraryRefreshSnapshot.fromIndex({
      'folders': [
        {
          'audios': [
            if (includeA)
              {'path': 'D:/A/song.flac', 'modified': 1, 'file_size': 100},
            {
              'path': 'E:/B/song.flac',
              'modified': 1,
              'file_size': bSize,
              'metadata_pending': true,
            },
          ],
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'committed root pruning keeps unchanged pending B cover and reloads once',
      () async {
    final before = snapshot(includeA: true);
    final after = snapshot(includeA: false);
    final invalidated = <String>[];
    var reloads = 0;
    late final LibraryRefreshTask task;
    task = LibraryRefreshTask(
      gate: LibraryMutationGate(),
      incremental: false,
      scan: () => Stream.fromIterable(const [
        IndexActionState(progress: 1, message: 'INDEX_PHASE_COMMITTING'),
        IndexActionState(progress: 1, message: 'INDEX_ROOTS_PRUNED'),
      ]),
      commit: () => completeLibraryRefresh(
        incremental: true,
        retryPending: !task.rootsOnly,
        before: before,
        readCommitted: () async => after,
        invalidateCover: (path) async => invalidated.add(path),
        clearCovers: () async => fail('root pruning must retain other covers'),
        reload: () async => reloads++,
      ),
    );
    final displayed = <IndexActionState>[];
    final listener = task.stream.listen(displayed.add);
    await task.completed;
    await listener.cancel();
    expect(task.phase, LibraryRefreshPhase.completed);
    expect(task.rootsOnly, isTrue);
    expect(task.pendingMetadata, 1,
        reason: 'B still needs a later real refresh');
    expect(invalidated, ['D:/A/song.flac']);
    expect(reloads, 1);
    expect(
        displayed.map((action) => action.message), ['INDEX_PHASE_COMMITTING'],
        reason: 'the native receipt is not user-facing progress text');
  });

  test('ordinary scans still invalidate unchanged pending metadata by default',
      () async {
    final before = snapshot(includeA: false);
    final invalidated = <String>[];
    final pending = await completeLibraryRefresh(
      incremental: true,
      before: before,
      readCommitted: () async => snapshot(includeA: false),
      invalidateCover: (path) async => invalidated.add(path),
      clearCovers: () async =>
          fail('incremental scan must not clear all covers'),
      reload: () async {},
    );
    expect(invalidated, ['E:/B/song.flac']);
    expect(pending, 1);
  });

  test(
      'skipping pending retry does not hide a changed pending file fingerprint',
      () async {
    final invalidated = <String>[];
    await completeLibraryRefresh(
      incremental: true,
      retryPending: false,
      before: snapshot(includeA: false),
      readCommitted: () async => snapshot(includeA: false, bSize: 101),
      invalidateCover: (path) async => invalidated.add(path),
      clearCovers: () async => fail('must not clear all covers'),
      reload: () async {},
    );
    expect(invalidated, ['E:/B/song.flac']);
  });

  for (final failure in <Object>[
    StateError('native atomic commit failed'),
    const LibraryScanCancelled(),
  ]) {
    test('an unsuccessful scan never acknowledges pruning: $failure', () async {
      var commits = 0;
      final task = LibraryRefreshTask(
        gate: LibraryMutationGate(),
        scan: () async* {
          // Even an unexpected marker followed by an error has no successful
          // stream receipt and must never trigger cache invalidation/reload.
          yield const IndexActionState(
              progress: 1, message: 'INDEX_ROOTS_PRUNED');
          throw failure;
        },
        commit: () async {
          commits++;
          return 0;
        },
      );
      task.start();
      await task.completed;
      expect(task.rootsOnly, isFalse);
      expect(commits, 0);
      expect(
          task.phase,
          failure is LibraryScanCancelled
              ? LibraryRefreshPhase.cancelled
              : LibraryRefreshPhase.failed);
    });
  }

  test('a successful ordinary full refresh retains its all-cover cleanup',
      () async {
    var clears = 0;
    late final LibraryRefreshTask task;
    task = LibraryRefreshTask(
      gate: LibraryMutationGate(),
      incremental: false,
      scan: () => const Stream.empty(),
      commit: () => completeLibraryRefresh(
        incremental: task.incremental,
        retryPending: !task.rootsOnly,
        before: snapshot(includeA: false),
        readCommitted: () async => snapshot(includeA: false),
        invalidateCover: (_) async =>
            fail('full refresh uses all-cover cleanup'),
        clearCovers: () async => clears++,
        reload: () async {},
      ),
    );
    task.start();
    await task.completed;
    expect(task.phase, LibraryRefreshPhase.completed);
    expect(task.rootsOnly, isFalse);
    expect(clears, 1);
  });
}
