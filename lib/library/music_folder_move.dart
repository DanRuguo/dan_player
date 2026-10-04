import 'dart:io';
import 'package:dan_player/app_settings.dart'
    show hasPendingAppDataDirectoryChange;

import 'package:dan_player/data/folder_move_transaction.dart';
import 'package:dan_player/library/library_data_migration.dart';
import 'package:path/path.dart' as p;

class MusicFolderMove {
  MusicFolderMove(this.dataDirectory,
      {bool forceCopy = false,
      this.pendingDataChange = hasPendingAppDataDirectoryChange})
      : transaction = FolderMoveTransaction(
            File(p.join(dataDirectory.path, 'music_folder_move.json')),
            forceCopy: forceCopy);
  final Directory dataDirectory;
  final FolderMoveTransaction transaction;
  final Future<bool> Function() pendingDataChange;
  Future<bool> get pending => transaction.pending;

  Future<void> schedule(Directory source, Directory destination) async {
    if (await pendingDataChange()) {
      throw StateError('Complete the pending data restore or move first');
    }
    if (p.equals(source.path, dataDirectory.path) ||
        p.isWithin(source.path, dataDirectory.path) ||
        p.isWithin(dataDirectory.path, source.path) ||
        p.equals(destination.path, dataDirectory.path) ||
        p.isWithin(dataDirectory.path, destination.path)) {
      throw const FileSystemException(
          'Music and player data must remain separate');
    }
    final migration = LibraryDataMigration(dataDirectory);
    if (await migration.hasPending) {
      throw StateError('Complete the pending library migration first');
    }
    await transaction.schedule(source, destination);
  }

  Future<void> recover() async {
    if (!await pending) return;
    await transaction.recover(commit: (from, to) async {
      final migration = LibraryDataMigration(dataDirectory);
      if (await migration.hasPending) {
        await migration.recover();
      }
      // The recovered batch may belong to another relocation left by an older
      // build. Always ensure this cut's mapping too; already committed own
      // mappings are an idempotent no-op, including selected empty roots.
      final mapping = LibraryPathMapping(from, to);
      await migration.scheduleFolderMove(mapping);
      await migration.recover();
    });
    await transaction.finish();
  }
}
