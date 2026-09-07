import 'dart:async';
import 'dart:io';
import 'package:fake_async/fake_async.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/library_watch.dart';
import 'package:dan_player/library/playlist.dart';
import 'package:flutter_test/flutter_test.dart';

class Harness {
  final sources = <String, StreamController<FileSystemEvent>>{};
  final unavailable = <String>{};
  final errors = <Object>[];
  bool busy = false;
  int scans = 0;
  Future<void> Function()? operation;
  late final watch = LibraryWatch(
    watch: (root) {
      final stream = StreamController<FileSystemEvent>.broadcast(sync: true);
      sources[root] = stream;
      return stream.stream;
    },
    accessible: (root) async => !unavailable.contains(root),
    busy: () => busy,
    refresh: () async {
      scans++;
      final action = operation;
      if (action != null) await action();
    },
    onError: (error, _) => errors.add(error),
    quietPeriod: const Duration(milliseconds: 200),
    maximumDelay: const Duration(seconds: 1),
    recoveryPeriod: const Duration(seconds: 3),
  );
  void change([String name = 'a.flac']) => sources[r'C:\Music']!
      .add(FileSystemCreateEvent('C:\\Music\\$name', false));
  Future<void> close() async {
    await watch.dispose();
    for (final source in sources.values) {
      unawaited(source.close());
    }
  }
}

void scenario(String name, void Function(FakeAsync) body) =>
    test(name, () => fakeAsync(body));

void main() {
  scenario('a locked file gets one delayed retry; new events can try again',
      (time) {
    final h = Harness()
      ..operation = () async {
        throw const FileSystemException('locked');
      };
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 1);
    time.elapse(const Duration(seconds: 4));
    expect(h.scans, 2);
    time.elapse(const Duration(minutes: 2));
    expect(h.scans, 2,
        reason: 'A broken file must not create periodic full traversal.');
    h.operation = null;
    h.change();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 3);
    h.close();
    time.flushMicrotasks();
  });
  scenario('cancel failures cannot poison later configurations', (time) {
    final errors = <Object>[];
    final sources = <StreamController<FileSystemEvent>>[];
    final attached = <String>[];
    final watch = LibraryWatch(
      watch: (root) {
        attached.add(root);
        final stream = StreamController<FileSystemEvent>(onCancel: () async {
          if (root == r'C:\Music') throw StateError('cancel failed');
        });
        sources.add(stream);
        return stream.stream;
      },
      accessible: (_) async => true,
      busy: () => false,
      refresh: () async {},
      onError: (error, _) => errors.add(error),
    );
    watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    watch.configure(enabled: true, roots: [r'D:\New']);
    time.flushMicrotasks();
    expect(attached, [r'C:\Music', r'D:\New']);
    expect(errors, hasLength(1));
    var stopped = false;
    watch.dispose().then((_) => stopped = true);
    time.flushMicrotasks();
    expect(stopped, isTrue);
    for (final source in sources) {
      unawaited(source.close());
    }
    time.flushMicrotasks();
  });

  scenario(
      'hanging root checks time out and shutdown cancels probe waiting immediately',
      (time) {
    var scans = 0;
    final unreachable = Completer<bool>();
    final watch = LibraryWatch(
      watch: (_) => const Stream.empty(),
      accessible: (_) => unreachable.future,
      refresh: () async {
        scans++;
      },
      quietPeriod: const Duration(milliseconds: 100),
      checkTimeout: const Duration(milliseconds: 200),
    );
    var configured = false;
    watch.configure(
        enabled: true, roots: [r'C:\Music']).then((_) => configured = true);
    time.flushMicrotasks();
    expect(configured, isFalse);
    time.elapse(const Duration(milliseconds: 210));
    expect(configured, isTrue);
    expect(scans, 0);
    watch.configure(enabled: true, roots: [r'D:\Other']);
    time.flushMicrotasks();
    var stopped = false;
    watch.dispose().then((_) => stopped = true);
    time.flushMicrotasks();
    expect(stopped, isTrue);
    expect(time.nonPeriodicTimerCount, 0);
    unreachable.complete(true);
    time.flushMicrotasks();
    expect(scans, 0);
  });

  test('Windows Directory.watch observes a real local file without polling',
      () async {
    if (!Platform.isWindows) return;
    final qaRoot =
        Directory('${Directory.current.parent.path}/tool/qa-local/2605-watch');
    await qaRoot.create(recursive: true);
    final root = await qaRoot.createTemp('events-');
    final first = Completer<void>();
    final changed = Completer<void>();
    var eventPhase = false;
    final watch = LibraryWatch(
      refresh: () async {
        if (!first.isCompleted) first.complete();
        if (eventPhase && !changed.isCompleted) changed.complete();
      },
      busy: () => false,
      quietPeriod: const Duration(milliseconds: 100),
    );
    try {
      await watch.configure(enabled: true, roots: [root.path]);
      await first.future.timeout(const Duration(seconds: 5));
      eventPhase = true;
      await File('${root.path}/synthetic.wav')
          .writeAsBytes([82, 73, 70, 70], flush: true);
      await changed.future.timeout(const Duration(seconds: 5));
    } finally {
      await watch.dispose();
      await root.delete(recursive: true);
    }
  });
  test('normalization removes overlapping roots and rejects relative paths',
      () {
    expect(
        LibraryWatch.normalizeRoots([
          r'C:\Music',
          r'c:\music\Album',
          r'C:\Music',
          r'D:\Other',
          'relative'
        ]).values,
        [r'C:\Music', r'D:\Other']);
  });

  scenario(
      'bursts coalesce; unrelated files and access-only events do not scan',
      (time) {
    final h = Harness();
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 1, reason: 'Reconcile the startup attachment gap once.');
    h.change('cover.jpg');
    h.sources[r'C:\Music']!
        .add(FileSystemModifyEvent(r'C:\Music\a.flac', false, false));
    time.elapse(const Duration(seconds: 2));
    expect(h.scans, 1);
    for (var i = 0; i < 10; i++) {
      h.change('$i.flac');
    }
    time.elapse(const Duration(milliseconds: 190));
    expect(h.scans, 1);
    time.elapse(const Duration(milliseconds: 20));
    expect(h.scans, 2);
    h.sources[r'C:\Music']!.add(FileSystemMoveEvent(
        r'C:\Music\download.tmp', false, r'C:\Music\done.mp3'));
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 3);
    var closed = false;
    h.close().then((_) => closed = true);
    time.flushMicrotasks();
    time.flushMicrotasks();
    expect(closed, isTrue);
  });

  scenario(
      'continuous events cannot postpone work forever; changes during scan run once after',
      (time) {
    final h = Harness();
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 210));
    for (var i = 0; i < 11; i++) {
      h.change();
      time.elapse(const Duration(milliseconds: 100));
    }
    expect(h.scans, 2);
    time.elapse(const Duration(milliseconds: 210));
    final completed = Completer<void>();
    h.operation = () => completed.future;
    h.change();
    time.elapse(const Duration(milliseconds: 210));
    final during = h.scans;
    for (var i = 0; i < 5; i++) {
      h.change();
    }
    time.elapse(const Duration(seconds: 2));
    expect(h.scans, during);
    h.operation = null;
    completed.complete();
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, during + 1);
    var closed = false;
    h.close().then((_) => closed = true);
    time.flushMicrotasks();
    time.flushMicrotasks();
    expect(closed, isTrue);
  });

  scenario(
      'unavailable roots stop scanning and recover without removing the remembered root',
      (time) {
    final h = Harness()..unavailable.add(r'C:\Music');
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 0);
    time.elapse(const Duration(seconds: 3));
    expect(h.scans, 0);
    h.unavailable.clear();
    time.elapse(const Duration(seconds: 3));
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 1);
    expect(h.sources[r'C:\Music']!.hasListener, isTrue);
    h.unavailable.add(r'C:\Music');
    h.change();
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 1);
    expect(h.sources[r'C:\Music']!.hasListener, isFalse);
    var closed = false;
    h.close().then((_) => closed = true);
    time.flushMicrotasks();
    time.flushMicrotasks();
    expect(closed, isTrue);
  });

  scenario(
      'manual mutations defer scans; a gate race retries without losing events',
      (time) {
    final h = Harness()..busy = true;
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    time.elapse(const Duration(seconds: 1));
    expect(h.scans, 0);
    h.busy = false;
    var first = true;
    h.operation = () async {
      if (first) {
        first = false;
        throw const LibraryMutationBusy();
      }
    };
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 1);
    time.elapse(const Duration(milliseconds: 210));
    expect(h.scans, 2);
    expect(h.errors, isEmpty);
    var closed = false;
    h.close().then((_) => closed = true);
    time.flushMicrotasks();
    time.flushMicrotasks();
    expect(closed, isTrue);
  });

  scenario(
      'disable, root replacement, recovery errors and shutdown release subscriptions',
      (time) {
    final h = Harness();
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    final old = h.sources[r'C:\Music']!;
    h.watch.configure(enabled: false, roots: [r'C:\Music']);
    time.flushMicrotasks();
    expect(old.hasListener, isFalse);
    time.elapse(const Duration(seconds: 5));
    expect(h.scans, 0);
    h.watch.configure(enabled: true, roots: [r'D:\New']);
    time.flushMicrotasks();
    expect(h.sources[r'D:\New']!.hasListener, isTrue);
    h.watch.configure(enabled: true, roots: [r'C:\Music']);
    time.flushMicrotasks();
    expect(h.sources[r'D:\New']!.hasListener, isFalse);
    h.sources[r'C:\Music']!.addError(const FileSystemException('lost watch'));
    time.flushMicrotasks();
    expect(h.errors, hasLength(1));
    final completed = Completer<void>();
    h.operation = () => completed.future;
    time.elapse(const Duration(milliseconds: 210));
    final running = h.scans;
    expect(running, 1);
    var disposed = false;
    h.close().then((_) => disposed = true);
    time.flushMicrotasks();
    expect(disposed, isFalse);
    completed.complete();
    time.flushMicrotasks();
    expect(disposed, isTrue);
    time.elapse(const Duration(seconds: 5));
    expect(h.scans, running);
    expect(h.sources.values.every((source) => !source.hasListener), isTrue);
  });

  test(
      'metadata refresh preserves live playlist edits, repeated occurrence IDs and missing entries',
      () {
    Audio song(String path, String title) =>
        Audio.fromMap({'path': path, 'title': title, 'duration': 15});
    final tree = PlaylistTree([]);
    final parent = tree.createPlaylist('Unsaved name');
    final a = tree.addAudio(parent, song(r'C:\Music\a.flac', 'Old'));
    final child = tree.createPlaylist('Nested', parent: parent);
    final b = tree.addAudio(child, a.audio);
    final missing =
        tree.addAudio(child, song(r'C:\Music\offline.flac', 'Offline'));
    final beforeTime = parent.modifiedAt;
    final newAudio = song(a.audio.path, 'Changed');
    expect(tree.refreshAudioReferences({newAudio.path: newAudio}), 2);
    expect(parent.flattenEntries().map((entry) => entry.entryId),
        [a.id, b.id, missing.id]);
    expect(parent.flattenAudios().map((audio) => audio.title),
        ['Changed', 'Changed', 'Offline']);
    expect(parent.name, 'Unsaved name');
    expect(parent.modifiedAt, beforeTime);
    expect(identical(a.audio, newAudio), isTrue);
  });
}
