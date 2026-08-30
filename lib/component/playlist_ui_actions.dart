import 'package:dan_player/library/playlist.dart';
import 'package:flutter/foundation.dart';

/// UI invalidation only: the ordered tree and its rules live in playlist.dart.
final playlistUiRevision = ValueNotifier<int>(0);
final playlistUiSaveError = ValueNotifier<String?>(null);
final playlistUiSaving = ValueNotifier<bool>(false);
int _saveRequest = 0;

/// Persist after a model mutation, keeping unsaved edits visible if disk I/O
/// fails. A newer snapshot owns the error indicator so a late older write can
/// never clear a newer failure. Tests inject a save callback and touch no files.
Future<void> savePlaylistUiChanges({Future<void> Function()? persist}) async {
  final request = ++_saveRequest;
  playlistUiRevision.value++;
  playlistUiSaving.value = true;
  try {
    await (persist ?? savePlaylists)();
    if (request == _saveRequest) playlistUiSaveError.value = null;
  } catch (error) {
    if (request == _saveRequest) playlistUiSaveError.value = error.toString();
    rethrow;
  } finally {
    if (request == _saveRequest) playlistUiSaving.value = false;
  }
}
