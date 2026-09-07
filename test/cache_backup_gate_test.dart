import 'dart:async';
import 'dart:io';

import 'package:dan_player/data/cache_backup_service.dart';
import 'package:dan_player/library/library_mutation_gate.dart';
import 'package:dan_player/page/settings_page/cache_backup_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _Backup extends CacheBackupService {
  _Backup(this.create);
  final Future<CacheBackupResult> Function() create;
  @override
  Future<CacheBackupResult> exportBackup(
          {required Directory source, required File destination}) =>
      create();
}

void main() {
  const result = CacheBackupResult(fileCount: 3, songCount: 2);
  test('backup gate spans flushing and archiving, blocking scanner commits',
      () async {
    final gate = LibraryMutationGate();
    final flushStarted = Completer<void>(), releaseFlush = Completer<void>();
    final exportStarted = Completer<void>(), releaseExport = Completer<void>();
    final service = _Backup(() async {
      exportStarted.complete();
      await releaseExport.future;
      return result;
    });
    final backup = exportLibraryCacheBackup(
        service: service,
        destination: File('synthetic.bak'),
        gate: gate,
        dataDirectory: () async => Directory('synthetic-data'),
        flush: () async {
          flushStarted.complete();
          await releaseFlush.future;
        });
    await flushStarted.future;
    await expectLater(
        gate.run(() async {}), throwsA(isA<LibraryMutationBusy>()));
    releaseFlush.complete();
    await exportStarted.future;
    await expectLater(
        gate.run(() async {}), throwsA(isA<LibraryMutationBusy>()));
    releaseExport.complete();
    expect(await backup, same(result));
    expect(gate.isBusy, isFalse);
    await gate.run(() async {});
  });

  test('busy or failed backup cannot flush old state and remains retryable',
      () async {
    final gate = LibraryMutationGate();
    final releaseScan = Completer<void>();
    final scan = gate.run(() => releaseScan.future);
    var flushes = 0, exports = 0;
    var fail = true;
    final service = _Backup(() async {
      exports++;
      if (fail) throw const FileSystemException('synthetic export failure');
      return result;
    });
    Future<CacheBackupResult> backup() => exportLibraryCacheBackup(
        service: service,
        destination: File('synthetic.bak'),
        gate: gate,
        dataDirectory: () async => Directory('synthetic-data'),
        flush: () async {
          flushes++;
        });
    await expectLater(backup(), throwsA(isA<LibraryMutationBusy>()));
    expect(flushes, 0);
    expect(exports, 0);
    releaseScan.complete();
    await scan;
    await expectLater(backup(), throwsA(isA<FileSystemException>()));
    expect(gate.isBusy, isFalse);
    fail = false;
    expect(await backup(), same(result));
    expect(flushes, 2);
    expect(exports, 2);
    expect(gate.isBusy, isFalse);
  });
}
