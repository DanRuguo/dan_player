import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/audio_trim.dart';
import 'package:dan_player/library/audio_trim_commit.dart';
import 'package:dan_player/library/ffmpeg_module_install.dart';
import 'package:dan_player/library/ffmpeg_runtime.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/library/library_refresh.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/taskbar_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'support/metadata_test_audio.dart';

void main() {
  final progress = TaskbarProgress.instance;
  setUp(() => expect(progress.value, isNull));
  tearDown(() => expect(progress.value, isNull));

  test('scan progress survives a detached view and awaits index commit',
      () async {
    final source = StreamController<IndexActionState>();
    final committed = Completer<int>();
    final task = LibraryRefreshTask(
        gate: LibraryMutationGate(),
        scan: () => source.stream,
        commit: () => committed.future);
    final view = task.stream.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.indeterminate);
    source.add(const IndexActionState(progress: .375, message: 'reading'));
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.fraction(.375));
    await view.cancel();
    source.add(const IndexActionState(progress: .75, message: 'reading'));
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.fraction(.75));
    await source.close();
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.indeterminate);
    committed.complete(0);
    await task.completed;
    expect(progress.value, isNull);
  });

  test('scan cancellation remains loading until native exit and cleanup',
      () async {
    final source = StreamController<IndexActionState>();
    final released = Completer<void>();
    final task = LibraryRefreshTask(
        gate: LibraryMutationGate(),
        scan: () => source.stream,
        cancelNative: () => 'cancelling',
        releaseNative: () => released.future,
        commit: () async => throw StateError('cancel must not commit'));
    task.start();
    source.add(const IndexActionState(progress: .6, message: 'reading'));
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.fraction(.6));
    await task.requestCancel();
    expect(progress.value, TaskbarProgressValue.indeterminate);
    source.addError(const LibraryScanCancelled());
    await source.close();
    await Future<void>.delayed(Duration.zero);
    expect(progress.value, TaskbarProgressValue.indeterminate);
    released.complete();
    await task.completed;
    expect(progress.value, isNull);
  });

  test('failed scan restores an older running operation', () async {
    final older = progress.begin()..update(.25);
    final task = LibraryRefreshTask(
        gate: LibraryMutationGate(),
        scan: () => Stream.error(StateError('scan fixture failed')),
        commit: () async => throw StateError('must not commit'));
    task.start();
    await task.completed;
    expect(progress.value, TaskbarProgressValue.fraction(.25));
    older.dispose();
  });

  test(
      'backup reports worker progress without capturing main-isolate listeners',
      () async {
    final scratchRoot = await Directory('build/taskbar-operation-tests')
        .create(recursive: true);
    final scratch = await scratchRoot.createTemp('backup-');
    final port = ReceivePort();
    var notifications = 0;
    void listener() {
      // ReceivePort cannot cross isolates. The real Shell adapter also owns
      // main-isolate state, which must stay outside the backup worker closure.
      port.sendPort.send(null);
      notifications++;
    }

    progress.addListener(listener);
    try {
      final source =
          await Directory(path.join(scratch.path, 'source')).create();
      await File(path.join(source.path, 'settings.json'))
          .writeAsString(jsonEncode({'theme': 'isolated fixture'}));
      await File(path.join(source.path, 'index.json'))
          .writeAsString(jsonEncode({'folders': []}));
      var reports = 0;
      final operation = BackupOperation(onProgress: (value) {
        reports++;
        expect(progress.value, isNotNull);
        expect(
            progress.value,
            value.total > 0
                ? TaskbarProgressValue.fraction(value.completed / value.total)
                : TaskbarProgressValue.indeterminate);
      });
      const service = CacheBackupService();
      final backup = File(path.join(scratch.path, 'test.bak'));
      await service.exportBackup(
          source: source, destination: backup, operation: operation);
      expect(reports, greaterThan(0));
      expect(notifications, greaterThan(1));
      expect(progress.value, isNull);
      await service.inspectBackup(backup: backup);
      expect(progress.value, isNull);
      final current =
          await Directory(path.join(scratch.path, 'current')).create();
      final activationStarted = Completer<void>();
      final activate = Completer<void>();
      final restoring = service.restoreBackup(
          backup: backup,
          destination: Directory(path.join(scratch.path, 'restored')),
          currentData: current,
          activateLocation: (_, __) async {
            activationStarted.complete();
            await activate.future;
          });
      await activationStarted.future;
      expect(progress.value, TaskbarProgressValue.indeterminate);
      activate.complete();
      await restoring;
      expect(progress.value, isNull);
      await expectLater(
          service.restoreBackup(
              backup: backup,
              destination: Directory(path.join(scratch.path, 'failed-restore')),
              currentData: current,
              activateLocation: (_, __) async {
                throw StateError('activation fixture failed');
              }),
          throwsA(isA<CacheBackupException>().having(
              (error) => error.message,
              'message',
              'Cache location was not changed: Bad state: activation fixture failed')));
      expect(progress.value, isNull);
      final cancelled = BackupOperation()..cancel();
      await expectLater(
          service.exportBackup(
              source: source,
              destination: File(path.join(scratch.path, 'cancelled.bak')),
              operation: cancelled),
          throwsA(isA<CacheBackupCancelled>()));
      expect(progress.value, isNull);
      await expectLater(
          service.inspectBackup(
              backup: File(path.join(scratch.path, 'missing.bak'))),
          throwsA(isA<FileSystemException>()));
      expect(progress.value, isNull);
    } finally {
      progress.removeListener(listener);
      port.close();
      expect(path.isWithin(scratchRoot.absolute.path, scratch.absolute.path),
          isTrue);
      await scratch.delete(recursive: true);
    }
  });

  test('trim cancelled before work releases its taskbar claim', () async {
    final cancel = AudioTrimCancellation()..cancel();
    await expectLater(
        performAudioTrim(
            MetadataTestAudio()..path = path.absolute('fixture.mp3'),
            AudioTrimRequest(
                destinationPath: path.absolute('fixture-copy.mp3'),
                startSeconds: 0,
                endSeconds: 1),
            cancellation: cancel),
        throwsA(isA<AudioTrimException>()));
    expect(progress.value, isNull);
  });

  test('FFmpeg setup failure clears loading without starting a download',
      () async {
    final scratchRoot = await Directory('build/taskbar-operation-tests')
        .create(recursive: true);
    final scratch = await scratchRoot.createTemp('ffmpeg-');
    try {
      final blocked = File(path.join(scratch.path, 'not-a-directory'));
      await blocked.writeAsString('fixture');
      final installer = FfmpegModuleInstaller();
      await expectLater(
          installer.install(
              progress: (_) {},
              runtime: FfmpegRuntime(
                  installRoot: Directory(path.join(blocked.path, 'ffmpeg')))),
          throwsA(isA<FileSystemException>()));
      expect(progress.value, isNull);
    } finally {
      expect(path.isWithin(scratchRoot.absolute.path, scratch.absolute.path),
          isTrue);
      await scratch.delete(recursive: true);
    }
  });
}
