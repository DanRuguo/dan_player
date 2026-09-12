import 'package:path/path.dart' as path;

/// Stable, independently selectable parts of a player backup.
enum BackupComponent { library, playlists, statistics, settings, resources }

class BackupSelection {
  const BackupSelection({
    this.components = const {...BackupComponent.values},
    this.includeMusic = false,
    this.musicFolders,
  });

  final Set<BackupComponent> components;
  final bool includeMusic;

  /// Null selects every available folder; empty selects none.
  final Set<String>? musicFolders;
  bool get isEmpty =>
      components.isEmpty && (!includeMusic || (musicFolders?.isEmpty ?? false));
  bool includesFolder(String id) =>
      includeMusic && (musicFolders == null || musicFolders!.contains(id));

  Map<String, Object?> toMap() => {
        'components': components.map((value) => value.name).toList(),
        'includeMusic': includeMusic,
        'musicFolders': musicFolders?.toList(),
      };

  factory BackupSelection.fromMap(Map<String, Object?> value) =>
      BackupSelection(
        components: {
          for (final component in BackupComponent.values)
            if ((value['components'] as List).contains(component.name))
              component,
        },
        includeMusic: value['includeMusic'] == true,
        musicFolders: value['musicFolders'] == null
            ? null
            : Set<String>.from(value['musicFolders'] as List),
      );
}

class BackupMusicFolder {
  const BackupMusicFolder(
      {required this.id,
      required this.name,
      required this.songCount,
      required this.bytes});
  final String id;
  final String name;
  final int songCount;
  final int bytes;
}

class BackupContents {
  const BackupContents(
      {required this.components,
      required this.musicFolders,
      this.encrypted = false,
      this.legacy = false,
      this.createdAt});
  final Set<BackupComponent> components;
  final List<BackupMusicFolder> musicFolders;
  final bool encrypted;
  final bool legacy;
  final DateTime? createdAt;
  int get musicCount =>
      musicFolders.fold(0, (sum, folder) => sum + folder.songCount);
  int get musicBytes =>
      musicFolders.fold(0, (sum, folder) => sum + folder.bytes);
}

class BackupProgress {
  const BackupProgress(this.phase, this.completed, this.total);
  final String phase;
  final int completed;
  final int total;
}

/// Cancelling leaves the existing backup and active app data untouched.
class BackupOperation {
  BackupOperation({this.onProgress});
  final void Function(BackupProgress)? onProgress;
  bool _cancelled = false;
  Future<void> Function()? cancelWorker;
  bool get isCancelled => _cancelled;
  Future<void> cancel() async {
    _cancelled = true;
    await cancelWorker?.call();
  }
}

BackupComponent backupComponentForPath(String relative) {
  final normalized = relative.replaceAll('\\', '/').toLowerCase();
  final name = normalized.split('/').last.replaceFirst(RegExp(r'\.bak$'), '');
  if (name.startsWith('playback_statistics')) return BackupComponent.statistics;
  if (const {'settings.json', 'app_preference.json', 'eq_presets.json'}
      .contains(name)) return BackupComponent.settings;
  if (const {
    'playlists.json',
    'collections.json',
    'custom_audio_order.json',
    'smart_playlists.json',
    'personal_library.json',
    'named_queues.json',
    'playback_bookmarks.json'
  }.contains(name)) return BackupComponent.playlists;
  if (const {
    'index.json',
    'online_library.json',
    'track_identities.json',
    'playback_state.json',
    'track_resume.json',
    'lyric_source.json',
    'lyric_documents.json',
    'song_comment_associations.json'
  }.contains(name)) {
    return BackupComponent.library;
  }
  return BackupComponent.resources;
}

Set<String> referencedCurrentCacheAssets(Object? value, String dataRoot) {
  final result = <String>{};
  void visit(Object? item) {
    if (item is String &&
        path.isAbsolute(item) &&
        path.isWithin(dataRoot, item)) {
      final relative =
          path.relative(item, from: dataRoot).replaceAll('\\', '/');
      if (!relative.endsWith('.json') && !relative.endsWith('.json.bak')) {
        result.add(relative.toLowerCase());
      }
    } else if (item is Map) {
      final background = item['customImageId'];
      if (background is String &&
          RegExp(r'^[a-f0-9]{64}\.png$').hasMatch(background)) {
        result.add('background-images/$background');
      }
      for (final child in item.values) {
        visit(child);
      }
    } else if (item is List) {
      for (final child in item) {
        visit(child);
      }
    }
  }

  visit(value);
  return result;
}
