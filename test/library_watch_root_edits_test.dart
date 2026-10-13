import 'dart:async';
import 'dart:io';

import 'package:dan_player/library/library_watch.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _Harness {
  final sources = <String, StreamController<FileSystemEvent>>{};
  final attachments = <String, int>{};
  int scans = 0;
  Future<bool> Function(String root)? checkRoot;
  Future<void> Function()? operation;
  late final watcher = LibraryWatch(
    watch: (root) {
      attachments.update(root, (count) => count + 1, ifAbsent: () => 1);
      final source = StreamController<FileSystemEvent>.broadcast(sync: true);
      sources[root] = source;
      return source.stream;
    },
    accessible: (root) => checkRoot?.call(root) ?? Future.value(true),
    busy: () => false,
    refresh: () async {
      scans++;
      await operation?.call();
    },
    quietPeriod: const Duration(milliseconds: 100),
  );

  void change(String root) =>
      sources[root]!.add(FileSystemCreateEvent('$root\\song.flac', false));

  void dispose() {
    unawaited(watcher.dispose().then((_) async {
      for (final source in sources.values) {
        await source.close();
      }
    }));
  }
}

void main() {
  const a = r'C:\Music A';
  const b = r'D:\Music B';

  test('removing A keeps B watch and does not request a scan of B', () {
    fakeAsync((time) {
      final h = _Harness();
      h.watcher.configure(enabled: true, roots: [a, b]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 1);
      final retained = h.sources[b]!;
      final removed = h.sources[a]!;
      h.watcher.configure(enabled: true, roots: [b]);
      time.flushMicrotasks();
      expect(removed.hasListener, isFalse);
      expect(identical(h.sources[b], retained), isTrue);
      expect(retained.hasListener, isTrue);
      expect(h.attachments[b], 1);
      removed.add(FileSystemCreateEvent('$a\\late.mp3', false));
      time.elapse(const Duration(minutes: 1));
      expect(h.scans, 1);
      h.change(b);
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 2,
          reason: 'B must still observe new songs after A removal');
      h.dispose();
      time.flushMicrotasks();
      expect(retained.hasListener, isFalse);
    });
  });

  for (final dirtyRoot in [a, b]) {
    test('pending changes keep the ownership of $dirtyRoot during A removal',
        () {
      fakeAsync((time) {
        final h = _Harness();
        h.watcher.configure(enabled: true, roots: [a, b]);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 110));
        h.change(dirtyRoot);
        time.elapse(const Duration(milliseconds: 40));
        h.watcher.configure(enabled: true, roots: [b]);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 110));
        expect(h.scans, dirtyRoot == b ? 2 : 1,
            reason:
                'removed-root work is discarded; retained-root work survives');
        h.dispose();
        time.flushMicrotasks();
      });
    });
  }

  test('a cancelled old root probe cannot detach the retained B watch', () {
    fakeAsync((time) {
      final h = _Harness();
      h.watcher.configure(enabled: true, roots: [a, b]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      final original = h.sources[b]!;
      final blocked = Completer<bool>();
      h.checkRoot = (root) => root == b ? blocked.future : Future.value(true);
      h.change(b);
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 1, reason: 'the old refresh is waiting for its probe');
      h.watcher.configure(enabled: true, roots: [b]);
      time.flushMicrotasks();
      expect(identical(h.sources[b], original), isTrue);
      expect(original.hasListener, isTrue);
      expect(h.attachments[b], 1);
      h.checkRoot = null;
      blocked.complete(true);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 2, reason: 'the observed B change still requires a scan');
      h.change(b);
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 3);
      h.dispose();
      time.flushMicrotasks();
    });
  });

  test('synchronous remove and re-add retires A session while retaining B', () {
    fakeAsync((time) {
      final h = _Harness();
      h.watcher.configure(enabled: true, roots: [a, b]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      final oldA = h.sources[a]!;
      final retainedB = h.sources[b]!;
      h.watcher.configure(enabled: true, roots: [b]);
      h.watcher.configure(enabled: true, roots: [a, b]);
      oldA.add(FileSystemCreateEvent('$a\\old-session.mp3', false));
      time.flushMicrotasks();
      expect(oldA.hasListener, isFalse);
      expect(identical(h.sources[a], oldA), isFalse);
      expect(identical(h.sources[b], retainedB), isTrue);
      expect(h.attachments, {a: 2, b: 1});
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 2,
          reason: 'only the real A attachment gap is reconciled');
      oldA.add(FileSystemCreateEvent('$a\\late-old-session.mp3', false));
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 2);
      h.change(a);
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 3);
      h.dispose();
      time.flushMicrotasks();
    });
  });

  for (final dirtyRoot in [a, b]) {
    test('failed $dirtyRoot changes retain only the still registered retry',
        () {
      fakeAsync((time) {
        final h = _Harness();
        h.watcher.configure(enabled: true, roots: [a, b]);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 110));
        h.operation = () async => throw const FileSystemException('locked');
        h.change(dirtyRoot);
        time.elapse(const Duration(milliseconds: 110));
        expect(h.scans, 2);
        final retained = h.sources[b]!;
        h.operation = null;
        h.watcher.configure(enabled: true, roots: [b]);
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 110));
        expect(h.scans, dirtyRoot == b ? 3 : 2,
            reason: 'A retry is obsolete; the failed B change must survive');
        expect(identical(h.sources[b], retained), isTrue);
        expect(h.attachments[b], 1);
        time.elapse(const Duration(minutes: 1));
        expect(h.scans, dirtyRoot == b ? 3 : 2,
            reason: 'root editing must not introduce periodic scans');
        h.dispose();
        time.flushMicrotasks();
      });
    });
  }

  test('equivalent roots retain subscriptions and adding C reconciles once',
      () {
    fakeAsync((time) {
      final h = _Harness();
      h.watcher.configure(enabled: true, roots: [a, b]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      h.watcher.configure(enabled: true, roots: [
        a.toLowerCase().replaceAll('\\', '/'),
        a,
        '$a\\Nested',
        b,
      ]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 1);
      expect(h.attachments, {a: 1, b: 1});
      const c = r'E:\Music C';
      h.watcher.configure(enabled: true, roots: [b, c]);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 110));
      expect(h.scans, 2);
      expect(h.attachments[b], 1);
      expect(h.attachments[c], 1);
      h.watcher.configure(enabled: false, roots: [b, c]);
      time.flushMicrotasks();
      expect(h.sources.values.every((source) => !source.hasListener), isTrue);
      time.elapse(const Duration(minutes: 1));
      expect(h.scans, 2);
      h.dispose();
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 0);
    });
  });
}
