// ignore_for_file: non_constant_identifier_names

import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/utils.dart';
import 'package:path/path.dart' as path_util;

List<Playlist> PLAYLISTS = [];
Future<void> _playlistWriteQueue = Future.value();
Future<void>? _playlistReadOperation;
bool _preservePlaylistBackup = false;
Object? _playlistReadError;
Object? _playlistSaveError;
int _playlistSaveGeneration = 0;
String? _pendingPlaylistSnapshot;
final Set<String> _migratedCollectionKeys = {};
bool _legacyCollectionsMigrated = false;

/// A failed write is kept in memory until a later save succeeds. The old
/// collection files are read-only migration sources, never a second database.
bool get playlistsHaveUnsavedChanges => _pendingPlaylistSnapshot != null;

/// A corrupt/unreadable source must be successfully reloaded before the UI
/// starts new mutations; rejected saves cannot protect an unrecorded edit.
bool get playlistsReadBlocked => _playlistReadError != null;

String? get playlistStorageWarning {
  if (_playlistReadError != null) {
    return '歌单或旧合集文件无法完整读取，已保留原文件和当前歌单。'
        '请恢复有效文件后重新读取：$_playlistReadError';
  }
  if (_playlistSaveError != null || playlistsHaveUnsavedChanges) {
    return '歌单最新更改尚未保存，当前内容仍保留在内存中，请重试保存。'
        '${_playlistSaveError == null ? '' : ' $_playlistSaveError'}';
  }
  return null;
}

/// A synchronous view over the current root list. UI owns notifications and
/// awaits [savePlaylists] after each successful mutation.
PlaylistTree get playlistTree => PlaylistTree(PLAYLISTS);

/// Load the single canonical store and, once, merge legacy collections into
/// roots. Call after the local/online libraries load so known paths can retain
/// their rich metadata. Concurrent legacy/new entry points share this read.
Future<void> readPlaylists() {
  final pending = _playlistReadOperation;
  if (pending != null) return pending;
  late final Future<void> operation;
  operation = _readPlaylists().whenComplete(() {
    if (identical(_playlistReadOperation, operation)) {
      _playlistReadOperation = null;
    }
  });
  _playlistReadOperation = operation;
  return operation;
}

Future<void> _readPlaylists() async {
  // A second save can join the queue while this read awaits an earlier one.
  // Only proceed after the latest observed queue has settled.
  while (true) {
    final writes = _playlistWriteQueue;
    await writes;
    if (identical(writes, _playlistWriteQueue)) break;
  }
  final readGeneration = _playlistSaveGeneration;
  if (!_canReplacePlaylists(readGeneration)) return;
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath = "$supportPath\\playlists.json";
    final playlistsFile = File(playlistsPath);
    final backupFile = File("$playlistsPath.bak");
    Object? firstError;
    _PlaylistStore? loaded;
    var recoveredFromBackup = false;
    var canonicalFileExists = false;
    for (final candidate in [playlistsFile, backupFile]) {
      if (!await candidate.exists()) continue;
      canonicalFileExists = true;
      try {
        final decoded = json.decode(await candidate.readAsString());
        loaded = _decodePlaylistStore(decoded);
        if (candidate.path == backupFile.path) {
          recoveredFromBackup = true;
        }
        break;
      } catch (error) {
        firstError ??= error;
      }
    }
    if (loaded == null && canonicalFileExists) {
      throw firstError ?? const FormatException("Playlists are unavailable");
    }
    loaded ??= _PlaylistStore([]);

    // Parse the entire source before appending anything. In particular, never
    // call the old collection sanitizer: missing files and repeated songs are
    // meaningful references which must survive a migration unchanged.
    var migrated = false;
    if (!loaded.legacyCollectionsMigrated) {
      final legacy = await _readLegacyCollections(supportPath);
      if (legacy != null) {
        _mergeLegacyCollections(loaded, legacy);
        migrated = true;
      }
    }

    if (!_canReplacePlaylists(readGeneration)) return;
    if (migrated) {
      await _preservePreMigrationFiles(playlistsFile, backupFile);
      if (!_canReplacePlaylists(readGeneration)) return;
    }
    PLAYLISTS
      ..clear()
      ..addAll(loaded.roots);
    _migratedCollectionKeys
      ..clear()
      ..addAll(loaded.migratedCollectionKeys);
    _legacyCollectionsMigrated = loaded.legacyCollectionsMigrated;
    _preservePlaylistBackup = recoveredFromBackup;
    _playlistReadError = null;
    _playlistSaveError = null;
    if (recoveredFromBackup) LOGGER.w("[playlists] recovered from backup");
    if (migrated) {
      try {
        // Data and the migration ledger commit in the same atomic snapshot.
        // If this fails, savePlaylists keeps the entire merged tree dirty and
        // retryable; restarting can re-import the unchanged legacy source.
        await savePlaylists();
      } catch (error, trace) {
        LOGGER.e('[playlists] 合集已合并到内存，但尚未保存；请重试保存。',
            error: error, stackTrace: trace);
      }
    }
  } catch (err, trace) {
    if (!_canReplacePlaylists(readGeneration)) return;
    // Do not let a later autosave overwrite an unreadable primary/backup with
    // an empty in-memory list. A successful read clears this protection.
    _playlistReadError = err;
    LOGGER.e(err, stackTrace: trace);
  }
}

bool _canReplacePlaylists(int readGeneration) {
  if (_pendingPlaylistSnapshot != null) {
    // This is a failed/unsettled write, not a corrupt-file read. Do not set
    // _playlistReadError: normal UI save/retry must remain available.
    LOGGER.w('[playlists] 歌单最新更改尚未保存，已保留整棵内存歌单并跳过重读；'
        '请在歌单页面重试保存，避免旧磁盘内容覆盖当前更改。');
    return false;
  }
  if (readGeneration != _playlistSaveGeneration) {
    LOGGER.w('[playlists] 读取期间歌单已更新，已忽略旧读取结果并保留当前更改。');
    return false;
  }
  return true;
}

Future<void> savePlaylists() {
  late final String contents;
  try {
    if (_playlistReadError != null) {
      throw StateError('歌单或旧合集文件无法完整读取，已保护原文件。请恢复有效文件后重新读取。');
    }
    playlistTree.validate();
    // Capture the requested state before joining the write queue. A rapid
    // second edit must not change the first save's backup snapshot.
    contents = json.encode({
      'version': 3,
      'playlists': PLAYLISTS.map((item) => item._toMap()).toList(),
      'migratedCollectionKeys': _migratedCollectionKeys.toList(),
      'legacyCollectionsMigrated': _legacyCollectionsMigrated,
    });
  } catch (error, trace) {
    return Future<void>.error(error, trace);
  }
  final generation = ++_playlistSaveGeneration;
  _pendingPlaylistSnapshot = contents;
  final result = _playlistWriteQueue.then((_) async {
    try {
      await _savePlaylistContents(contents);
      // An older successful write must not mark a newer failed/pending snapshot
      // clean. Failure leaves the newest snapshot and the live tree available.
      if (generation == _playlistSaveGeneration) {
        _pendingPlaylistSnapshot = null;
        _playlistSaveError = null;
      }
    } catch (error) {
      if (generation == _playlistSaveGeneration) _playlistSaveError = error;
      rethrow;
    }
  });
  _playlistWriteQueue = result.then<void>((_) {}, onError: (_, __) {});
  return result;
}

Future<void> _preservePreMigrationFiles(File primary, File backup) async {
  for (final pair in [
    (
      primary,
      File('${primary.parent.path}\\playlists.before-collection-merge.json.bak')
    ),
    (
      backup,
      File(
          '${primary.parent.path}\\playlists.before-collection-merge.previous.bak')
    ),
  ]) {
    if (await pair.$1.exists() && !await pair.$2.exists()) {
      // A terminated copy must not leave a partial file under the immutable
      // backup name, which a retry would otherwise mistake for a good copy.
      final temporary = File('${pair.$2.path}.${_newPlaylistId('tmp_')}');
      try {
        await temporary.writeAsBytes(await pair.$1.readAsBytes(), flush: true);
        // Never overwrite a previously preserved original during a retry.
        if (!await pair.$2.exists()) await temporary.rename(pair.$2.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }
}

Future<void> _savePlaylistContents(String contents) async {
  try {
    final supportPath = (await getAppDataDir()).path;
    final playlistsPath = "$supportPath\\playlists.json";

    final target = File(playlistsPath);
    final temporary = File("$playlistsPath.tmp");
    final backup = File("$playlistsPath.bak");
    await target.parent.create(recursive: true);
    try {
      await temporary.writeAsString(contents, flush: true);
      if (!_preservePlaylistBackup) {
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      _preservePlaylistBackup = false;
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.copy(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  } catch (err, trace) {
    LOGGER.e(err, stackTrace: trace);
    rethrow;
  }
}

final Random _playlistIdRandom = Random.secure();

String _newPlaylistId(String prefix) => '$prefix${List.generate(16, (_) {
      return _playlistIdRandom.nextInt(256).toRadixString(16).padLeft(2, '0');
    }).join()}';

sealed class PlaylistEntry {
  const PlaylistEntry._(this.id);

  final String id;
  Audio? get audio => null;
  Playlist? get childPlaylist => null;
}

final class PlaylistAudioEntry extends PlaylistEntry {
  PlaylistAudioEntry._(super.id, Audio audio)
      : _audio = audio,
        _path = audio.path,
        super._();

  Audio _audio;

  // Metadata editing mutates Audio in place before updating playlists. Keep
  // the original map key until replaceAudio explicitly refreshes it.
  String _path;

  @override
  Audio get audio => _audio;

  void _replace(Audio value) {
    _audio = value;
    _path = value.path;
  }
}

final class PlaylistChildEntry extends PlaylistEntry {
  PlaylistChildEntry._(this.childPlaylist) : super._(childPlaylist.id);

  @override
  final Playlist childPlaylist;
}

class PlaylistAudioOccurrence {
  const PlaylistAudioOccurrence({
    required this.entryId,
    required this.audio,
    required this.playlist,
  });

  final String entryId;
  final Audio audio;
  final Playlist playlist;
}

class Playlist {
  Playlist(this.name, Map<String, Audio> audios, {this.imagePath})
      : id = _newPlaylistId('pl_'),
        createdAt = DateTime.now().millisecondsSinceEpoch,
        legacyCollectionId = null,
        legacyCollectionKey = null {
    modifiedAt = createdAt;
    this.audios = audios;
  }

  Playlist._(
    this.id,
    this.name, {
    this.imagePath,
    this.createdAt = 0,
    this.modifiedAt = 0,
    this.legacyCollectionId,
    this.legacyCollectionKey,
  });

  final String id;
  String name;
  String? imagePath;
  int createdAt;
  int modifiedAt = 0;

  /// Original identity, not a name-based deduplication key. Two legacy records
  /// may have the same ID/name; their migration keys and node IDs stay distinct.
  final String? legacyCollectionId;
  final String? legacyCollectionKey;
  Playlist? _parent;
  final List<PlaylistEntry> _entries = [];
  late final List<PlaylistEntry> _entryView = UnmodifiableListView(_entries);
  late final Map<String, Audio> _audioView = _PlaylistAudioMap(this);

  Playlist? get parent => _parent;
  List<PlaylistEntry> get entries => _entryView;
  Playlist get root => pathFromRoot.first;

  List<Playlist> get pathFromRoot {
    final path = <Playlist>[];
    final visited = HashSet<Playlist>.identity();
    for (Playlist? current = this; current != null; current = current.parent) {
      if (!visited.add(current) || path.length >= PlaylistTree.maxDepth) {
        throw const FormatException('歌单父级关系包含循环或超过 32 层');
      }
      path.add(current);
    }
    return List.unmodifiable(path.reversed);
  }

  /// A writable compatibility view of only this playlist's direct songs.
  /// Children are deliberately absent: playback must use [flattenAudios].
  Map<String, Audio> get audios => _audioView;

  /// Replace direct songs without discarding interleaved children. Existing
  /// songs retain their occurrence IDs/positions, including repeated legacy
  /// occurrences; new paths append in map order. A deselected path removes all
  /// its direct occurrences, never those in a child playlist.
  set audios(Map<String, Audio> value) {
    final pending = Map<String, Audio>.from(value);
    for (final item in pending.entries) {
      _checkAudioKey(item.key, item.value);
    }
    final updated = <PlaylistEntry>[];
    final retainedPaths = <String>{};
    var changed = false;
    for (final entry in _entries) {
      if (entry is PlaylistChildEntry) {
        updated.add(entry);
        continue;
      }
      final track = entry as PlaylistAudioEntry;
      final replacement = pending[track._path];
      if (replacement != null) {
        retainedPaths.add(track._path);
        changed |= !identical(track.audio, replacement);
        track._replace(replacement);
        updated.add(track);
      } else {
        changed = true;
      }
    }
    final added =
        pending.values.where((audio) => !retainedPaths.contains(audio.path));
    updated.addAll(added.map(
      (audio) => PlaylistAudioEntry._(_newPlaylistId('pe_'), audio),
    ));
    changed |= updated.length != _entries.length;
    if (!changed) return;
    _entries
      ..clear()
      ..addAll(updated);
    _touch();
  }

  List<PlaylistAudioOccurrence> flattenEntries() {
    PlaylistTree([root]).validate();
    final result = <PlaylistAudioOccurrence>[];
    void append(Playlist playlist) {
      for (final entry in playlist._entries) {
        if (entry is PlaylistAudioEntry) {
          result.add(PlaylistAudioOccurrence(
            entryId: entry.id,
            audio: entry.audio,
            playlist: playlist,
          ));
        } else {
          append((entry as PlaylistChildEntry).childPlaylist);
        }
      }
    }

    append(this);
    return result;
  }

  List<Audio> flattenAudios() =>
      flattenEntries().map((entry) => entry.audio).toList();

  /// Finds the first depth-first song without validating or materializing the
  /// full subtree. Persisted trees are validated when read and mutations are
  /// validated at their boundary; the guards here keep this display-only read
  /// finite even if an in-memory tree is unexpectedly damaged.
  Audio? get firstAudioOrNull {
    final visited = HashSet<Playlist>.identity();

    Audio? find(Playlist playlist, int depth) {
      if (depth > PlaylistTree.maxDepth || !visited.add(playlist)) return null;
      for (final entry in playlist._entries) {
        if (entry is PlaylistAudioEntry) return entry.audio;
        final found = find(
          (entry as PlaylistChildEntry).childPlaylist,
          depth + 1,
        );
        if (found != null) return found;
      }
      return null;
    }

    return find(this, 1);
  }

  int flattenedIndexOf(String entryId) =>
      flattenEntries().indexWhere((entry) => entry.entryId == entryId);

  /// Refresh every matching direct occurrence after metadata/path changes.
  /// This does not reorder children, regenerate IDs or collapse repeated songs.
  /// A path rename may create aliases; both user-selected occurrences survive.
  bool replaceAudio(String oldPath, Audio replacement) {
    final matches = _entries.whereType<PlaylistAudioEntry>().where((entry) {
      return entry._path == oldPath ||
          entry.audio.path == oldPath ||
          identical(entry.audio, replacement);
    }).toList();
    if (matches.isEmpty) return false;
    for (final entry in matches) {
      entry._replace(replacement);
    }
    _touch();
    return true;
  }

  void _touch() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final playlist in pathFromRoot) {
      playlist.modifiedAt = now;
    }
  }

  Map<String, Object?> toMap() {
    PlaylistTree([root]).validate();
    return _toMap();
  }

  Map<String, Object?> _toMap() => {
        'version': 3,
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
        if (legacyCollectionId != null)
          'legacyCollectionId': legacyCollectionId,
        if (legacyCollectionKey != null)
          'legacyCollectionKey': legacyCollectionKey,
        'entries': [
          for (final entry in _entries)
            if (entry is PlaylistAudioEntry)
              {
                'type': 'audio',
                'id': entry.id,
                'audio': _audioToMap(entry.audio),
              }
            else
              {
                'type': 'playlist',
                'id': entry.id,
                'playlist':
                    (entry as PlaylistChildEntry).childPlaylist._toMap(),
              },
        ],
      };

  factory Playlist.fromMap(Map map) => decodePlaylists([map]).single;
}

void _checkAudioKey(String key, Audio audio) {
  if (key.isEmpty || key != audio.path) {
    throw ArgumentError('曲目键必须与曲目路径一致');
  }
}

class _PlaylistAudioMap extends MapBase<String, Audio> {
  _PlaylistAudioMap(this.playlist);
  final Playlist playlist;

  @override
  Iterable<String> get keys => playlist._entries
      .whereType<PlaylistAudioEntry>()
      .map((entry) => entry._path)
      .toSet();

  @override
  Audio? operator [](Object? key) {
    for (final entry in playlist._entries.whereType<PlaylistAudioEntry>()) {
      if (entry._path == key) return entry.audio;
    }
    return null;
  }

  @override
  void operator []=(String key, Audio value) {
    _checkAudioKey(key, value);
    var found = false;
    var changed = false;
    for (final entry in playlist._entries.whereType<PlaylistAudioEntry>()) {
      if (entry._path == key) {
        found = true;
        changed |= !identical(entry.audio, value);
        entry._replace(value);
      }
    }
    if (!found) {
      playlist._entries.add(PlaylistAudioEntry._(_newPlaylistId('pe_'), value));
      changed = true;
    }
    if (changed) playlist._touch();
  }

  @override
  Audio? remove(Object? key) {
    final removed = this[key];
    if (removed == null) return null;
    playlist._entries.removeWhere(
      (entry) => entry is PlaylistAudioEntry && entry._path == key,
    );
    playlist._touch();
    return removed;
  }

  @override
  void clear() {
    final before = playlist._entries.length;
    playlist._entries.removeWhere((entry) => entry is PlaylistAudioEntry);
    if (playlist._entries.length != before) playlist._touch();
  }
}

class PlaylistTree {
  PlaylistTree(this.roots) {
    validate();
  }

  /// Includes the root level, so at most 32 playlists lie on any one path.
  static const int maxDepth = 32;

  /// Mutable backing list, normally [PLAYLISTS]. Mutate through this tree to
  /// retain parent links and validate the entire operation before committing.
  final List<Playlist> roots;

  List<Playlist> get allPlaylists => List.unmodifiable(_validatedPlaylists());

  String? get _readOnlyReason =>
      identical(roots, PLAYLISTS) && playlistsReadBlocked
          ? '歌单文件尚未完整读取，当前歌单为只读状态。请恢复有效文件并重新读取后再修改。'
          : null;

  void _requireEditable() {
    final reason = _readOnlyReason;
    if (reason != null) throw StateError(reason);
  }

  void validate() => _validatedPlaylists();

  List<Playlist> _validatedPlaylists() {
    final visited = HashSet<Playlist>.identity();
    final ids = <String>{};
    final sourceKeys = <String>{};
    final ordered = <Playlist>[];
    void visit(Playlist playlist, Playlist? parent, int depth) {
      if (depth > maxDepth) {
        throw const FormatException('歌单嵌套不能超过 32 层');
      }
      if (!visited.add(playlist)) {
        throw const FormatException('歌单包含循环或多个父级链接');
      }
      if (!identical(playlist.parent, parent)) {
        throw const FormatException('歌单父级关系不一致');
      }
      if (playlist.id.isEmpty || !ids.add(playlist.id)) {
        throw const FormatException('歌单或曲目条目标识重复');
      }
      final sourceKey = playlist.legacyCollectionKey;
      if (sourceKey != null &&
          (sourceKey.isEmpty || !sourceKeys.add(sourceKey))) {
        throw const FormatException('旧合集来源标识缺失或重复');
      }
      ordered.add(playlist);
      for (final entry in playlist._entries) {
        if (entry is PlaylistAudioEntry) {
          if (entry.id.isEmpty || !ids.add(entry.id)) {
            throw const FormatException('歌单或曲目条目标识重复');
          }
          if (entry._path.isEmpty) {
            throw const FormatException('歌曲路径不能为空');
          }
        } else {
          final child = (entry as PlaylistChildEntry).childPlaylist;
          if (entry.id != child.id) {
            throw const FormatException('子歌单链接标识不一致');
          }
          visit(child, playlist, depth + 1);
        }
      }
    }

    for (final root in roots) {
      visit(root, null, 1);
    }
    return ordered;
  }

  Playlist? findPlaylist(String id) {
    for (final playlist in allPlaylists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Playlist? findByLegacyCollectionId(String id, {int occurrence = 0}) {
    if (occurrence < 0) return null;
    final key = _collectionKey(['id', id], occurrence);
    var matched = 0;
    for (final playlist in allPlaylists) {
      if (playlist.legacyCollectionKey == key) {
        return playlist;
      }
      if (playlist.legacyCollectionKey == null &&
          playlist.legacyCollectionId == id &&
          matched++ == occurrence) {
        return playlist;
      }
    }
    return null;
  }

  void _requireMember(Playlist playlist) {
    if (!allPlaylists.any((item) => identical(item, playlist))) {
      throw ArgumentError('目标歌单已移除或不属于当前歌单树');
    }
  }

  Playlist createPlaylist(String name,
      {Playlist? parent, int? index, String? imagePath}) {
    _requireEditable();
    validate();
    final trimmed = _checkedName(name);
    if (parent != null) {
      _requireMember(parent);
      if (parent.pathFromRoot.length >= maxDepth) {
        throw ArgumentError('歌单嵌套不能超过 32 层');
      }
    }
    final length = parent?._entries.length ?? roots.length;
    final position = _checkedIndex(index ?? length, length);
    final playlist = Playlist(trimmed, {}, imagePath: imagePath);
    if (parent == null) {
      roots.insert(position, playlist);
    } else {
      parent._entries.insert(position, PlaylistChildEntry._(playlist));
      playlist._parent = parent;
      parent._touch();
    }
    return playlist;
  }

  /// Capture a playback queue as a new playlist, retaining repeated tracks.
  /// Validate all entries before attaching the new node to the existing tree.
  Playlist createPlaylistFromAudios(String name, Iterable<Audio> audios) {
    _requireEditable();
    validate();
    final checkedName = _checkedName(name);
    final entries = <PlaylistAudioEntry>[];
    for (final audio in audios) {
      _checkAudioKey(audio.path, audio);
      entries.add(PlaylistAudioEntry._(_newPlaylistId('pe_'), audio));
    }
    final created = Playlist(checkedName, {}).._entries.addAll(entries);
    roots.add(created);
    return created;
  }

  PlaylistAudioEntry addAudio(Playlist parent, Audio audio, {int? index}) {
    _requireEditable();
    _requireMember(parent);
    final position =
        _checkedIndex(index ?? parent._entries.length, parent._entries.length);
    for (final entry in parent._entries.whereType<PlaylistAudioEntry>()) {
      if (entry._path == audio.path || entry.audio.path == audio.path) {
        return entry;
      }
    }
    _checkAudioKey(audio.path, audio);
    final entry = PlaylistAudioEntry._(_newPlaylistId('pe_'), audio);
    parent._entries.insert(position, entry);
    parent._touch();
    return entry;
  }

  /// Add a selection in one validated transaction. Returns only newly inserted
  /// occurrences; existing paths and repeated input paths retain their entries.
  /// Unlike repeatedly calling addAudio, a large library selection is O(n).
  List<PlaylistAudioEntry> addAudios(
    Playlist parent,
    Iterable<Audio> audios, {
    int? index,
  }) {
    _requireEditable();
    _requireMember(parent);
    final position =
        _checkedIndex(index ?? parent._entries.length, parent._entries.length);
    final paths = <String>{
      for (final entry in parent._entries.whereType<PlaylistAudioEntry>())
        entry._path,
      for (final entry in parent._entries.whereType<PlaylistAudioEntry>())
        entry.audio.path,
    };
    final added = <PlaylistAudioEntry>[];
    for (final audio in audios) {
      _checkAudioKey(audio.path, audio);
      if (paths.add(audio.path)) {
        added.add(PlaylistAudioEntry._(_newPlaylistId('pe_'), audio));
      }
    }
    parent._entries.insertAll(position, added);
    if (added.isNotEmpty) parent._touch();
    return added;
  }

  /// Edit the direct-song selection without removing children or collapsing
  /// retained repeated occurrences imported from a legacy collection.
  void setDirectAudios(Playlist playlist, Iterable<Audio> audios) {
    _requireEditable();
    _requireMember(playlist);
    final selected = <String, Audio>{};
    for (final audio in audios) {
      _checkAudioKey(audio.path, audio);
      selected[audio.path] = audio;
    }
    playlist.audios = selected;
  }

  void setImagePath(Playlist playlist, String? imagePath) {
    _requireEditable();
    _requireMember(playlist);
    if (playlist.imagePath == imagePath) return;
    playlist.imagePath = imagePath;
    playlist._touch();
  }

  void rename(Playlist playlist, String name) {
    _requireEditable();
    _requireMember(playlist);
    final checked = _checkedName(name);
    if (playlist.name == checked) return;
    playlist.name = checked;
    playlist._touch();
  }

  static String _checkedName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('歌单名称不能为空');
    return trimmed;
  }

  static int _checkedIndex(int index, int maximum) {
    if (index < 0 || index > maximum) throw ArgumentError('歌单插入位置已失效');
    return index;
  }

  _PlaylistLocation _locate(Playlist? parent, String entryId) {
    if (parent == null) {
      final index = roots.indexWhere((playlist) => playlist.id == entryId);
      if (index < 0) throw ArgumentError('源歌单已移除或已移动');
      return _PlaylistLocation(index, PlaylistChildEntry._(roots[index]));
    }
    _requireMember(parent);
    final index = parent._entries.indexWhere((entry) => entry.id == entryId);
    if (index < 0) throw ArgumentError('源条目已移除或已移动');
    return _PlaylistLocation(index, parent._entries[index]);
  }

  void removeEntry({required Playlist? parent, required String entryId}) {
    _requireEditable();
    removeEntries(parent: parent, entryIds: [entryId]);
  }

  /// Remove every persisted reference to one local file, including repeated
  /// legacy occurrences and references nested under child playlists.
  ///
  /// This deliberately operates on the file identity rather than [Audio]
  /// object identity: metadata refreshes may have replaced the in-memory
  /// object while a menu is still open. The physical file and the library are
  /// owned by the deletion coordinator; this method only updates playlists.
  int removeAudioReferences(String audioPath, {bool prevalidated = false}) {
    _requireEditable();
    if (!prevalidated) validate();
    var removed = 0;
    for (final playlist in allPlaylists) {
      final before = playlist._entries.length;
      playlist._entries.removeWhere((entry) =>
          entry is PlaylistAudioEntry &&
          (path_util.equals(entry._path, audioPath) ||
              path_util.equals(entry.audio.path, audioPath)));
      final count = before - playlist._entries.length;
      if (count == 0) continue;
      removed += count;
      playlist._touch();
    }
    return removed;
  }

  /// Remove only relationships at one level, validating the whole selection
  /// before removing any of it. Descendant files/library entries are untouched.
  void removeEntries({
    required Playlist? parent,
    required Iterable<String> entryIds,
  }) {
    _requireEditable();
    validate();
    if (parent != null) _requireMember(parent);
    final requested = entryIds.toSet();
    final currentIds = parent == null
        ? roots.map((playlist) => playlist.id).toSet()
        : parent._entries.map((entry) => entry.id).toSet();
    if (!currentIds.containsAll(requested)) {
      throw ArgumentError('选择中有已移除、已移动或不在本层的条目');
    }
    if (requested.isEmpty) return;
    final detached = parent == null
        ? roots.where((playlist) => requested.contains(playlist.id)).toList()
        : parent._entries
            .whereType<PlaylistChildEntry>()
            .where((entry) => requested.contains(entry.id))
            .map((entry) => entry.childPlaylist)
            .toList();
    if (parent == null) {
      roots.removeWhere((playlist) => requested.contains(playlist.id));
    } else {
      parent._entries.removeWhere((entry) => requested.contains(entry.id));
    }
    for (final playlist in detached) {
      playlist._parent = null;
    }
    parent?._touch();
  }

  /// Null means the complete move is valid. This is safe for drag-hover checks:
  /// it never removes, reparents, reorders or serializes any data.
  String? moveError({
    required Playlist? sourceParent,
    required String entryId,
    required Playlist? targetParent,
    int? index,
  }) {
    final readOnlyReason = _readOnlyReason;
    if (readOnlyReason != null) return readOnlyReason;
    try {
      validate();
      final source = _locate(sourceParent, entryId);
      if (targetParent != null) _requireMember(targetParent);
      final length = targetParent?._entries.length ?? roots.length;
      final finalLength =
          length - (identical(sourceParent, targetParent) ? 1 : 0);
      _checkedIndex(index ?? finalLength, finalLength);
      final child = source.entry.childPlaylist;
      if (child == null) {
        if (targetParent == null) return '歌曲只能移动到歌单内部';
        final track = source.entry as PlaylistAudioEntry;
        if (!identical(sourceParent, targetParent) &&
            targetParent._entries.whereType<PlaylistAudioEntry>().any(
                  (other) =>
                      !identical(other, track) && other._path == track._path,
                )) {
          return '目标歌单已包含这首歌曲';
        }
      } else {
        if (identical(child, targetParent)) return '不能把歌单移入自身';
        if (targetParent?.pathFromRoot.contains(child) == true) {
          return '不能把歌单移入自己的子歌单';
        }
        final targetDepth = (targetParent?.pathFromRoot.length ?? 0) + 1;
        if (targetDepth + _subtreeHeight(child) - 1 > maxDepth) {
          return '移动后歌单嵌套将超过 32 层';
        }
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    } on ArgumentError catch (error) {
      return error.message?.toString() ?? '无法移动该条目';
    }
  }

  /// [index] is the final insertion position *after* removing the source.
  /// A null destination parent means the root playlist list, never loose songs.
  void moveEntry({
    required Playlist? sourceParent,
    required String entryId,
    required Playlist? targetParent,
    int? index,
  }) {
    _requireEditable();
    final error = moveError(
      sourceParent: sourceParent,
      entryId: entryId,
      targetParent: targetParent,
      index: index,
    );
    if (error != null) throw ArgumentError(error);
    final source = _locate(sourceParent, entryId);
    final length = targetParent?._entries.length ?? roots.length;
    final position =
        index ?? length - (identical(sourceParent, targetParent) ? 1 : 0);
    if (identical(sourceParent, targetParent) && position == source.index) {
      return;
    }
    _removeAt(sourceParent, source.index);
    try {
      if (targetParent == null) {
        roots.insert(position, source.entry.childPlaylist!);
      } else {
        targetParent._entries.insert(position, source.entry);
      }
    } catch (_) {
      // A caller may have supplied a fixed/unmodifiable root list. If its
      // insertion fails, put the source relationship back before reporting it.
      if (sourceParent == null) {
        roots.insert(source.index, source.entry.childPlaylist!);
      } else {
        sourceParent._entries.insert(source.index, source.entry);
      }
      rethrow;
    }
    source.entry.childPlaylist?._parent = targetParent;
    sourceParent?._touch();
    targetParent?._touch();
    source.entry.childPlaylist?._touch();
  }

  void _removeAt(Playlist? parent, int index) {
    if (parent == null) {
      roots.removeAt(index);
    } else {
      parent._entries.removeAt(index);
    }
  }

  /// Uses Flutter ReorderableListView's old-list [newIndex] convention.
  void reorder(
      {required Playlist? parent,
      required int oldIndex,
      required int newIndex}) {
    _requireEditable();
    validate();
    if (parent != null) _requireMember(parent);
    final length = parent?._entries.length ?? roots.length;
    if (oldIndex < 0 || oldIndex >= length) throw ArgumentError('源条目位置已失效');
    _checkedIndex(newIndex, length);
    final entryId =
        parent == null ? roots[oldIndex].id : parent._entries[oldIndex].id;
    moveEntry(
      sourceParent: parent,
      entryId: entryId,
      targetParent: parent,
      index: newIndex > oldIndex ? newIndex - 1 : newIndex,
    );
  }

  /// Apply a sort or keyboard-generated order without repeated full-tree
  /// moves. IDs must be an exact permutation of this level: no omissions,
  /// duplicates, new members or implicit reparenting are permitted.
  void setOrder({required Playlist? parent, required List<String> entryIds}) {
    _requireEditable();
    validate();
    if (parent != null) _requireMember(parent);
    final current = <String, Object>{
      if (parent == null)
        for (final playlist in roots) playlist.id: playlist
      else
        for (final entry in parent._entries) entry.id: entry,
    };
    if (entryIds.length != current.length ||
        entryIds.toSet().length != current.length ||
        entryIds.any((id) => !current.containsKey(id))) {
      throw ArgumentError('排序必须完整保留本层所有条目，且不能有重复条目');
    }
    if (parent == null) {
      final reordered = entryIds.map((id) => current[id]! as Playlist).toList();
      roots.setAll(0, reordered);
    } else {
      final reordered =
          entryIds.map((id) => current[id]! as PlaylistEntry).toList();
      parent._entries.setAll(0, reordered);
      parent._touch();
    }
  }

  static int _subtreeHeight(Playlist playlist) {
    var result = 1;
    for (final entry in playlist._entries.whereType<PlaylistChildEntry>()) {
      result = max(result, 1 + _subtreeHeight(entry.childPlaylist));
    }
    return result;
  }
}

class _PlaylistLocation {
  const _PlaylistLocation(this.index, this.entry);
  final int index;
  final PlaylistEntry entry;
}

Map<Object?, Object?> _audioToMap(Audio audio) => audio.isOnline
    ? {'kind': 'online', 'path': audio.path, ...audio.toOnlineMap()}
    : {'kind': 'local', ...audio.toMap()};

class _PlaylistStore {
  _PlaylistStore(
    this.roots, {
    Set<String>? migratedCollectionKeys,
    this.legacyCollectionsMigrated = false,
  }) : migratedCollectionKeys = migratedCollectionKeys ?? <String>{};

  final List<Playlist> roots;
  final Set<String> migratedCollectionKeys;
  bool legacyCollectionsMigrated;
}

_PlaylistStore _decodePlaylistStore(Object? value) {
  Object? nodes = value;
  final migratedKeys = <String>{};
  var migrated = false;
  if (value is Map) {
    if (value['version'] != 3) {
      throw const FormatException('无法读取此版本的统一歌单文件');
    }
    nodes = value['playlists'];
    final keys = value['migratedCollectionKeys'] ?? const [];
    if (keys is! List || keys.any((key) => key is! String || key.isEmpty)) {
      throw const FormatException('歌单迁移记录无效');
    }
    for (final key in keys) {
      if (!migratedKeys.add(key as String)) {
        throw const FormatException('歌单迁移记录重复');
      }
    }
    final completed = value['legacyCollectionsMigrated'] ?? false;
    if (completed is! bool) {
      throw const FormatException('歌单迁移状态无效');
    }
    migrated = completed;
  }
  if (nodes is! List) throw const FormatException('歌单文件根节点必须是列表');
  final decoder = _PlaylistDecoder();
  final roots = <Playlist>[];
  for (final item in nodes) {
    if (item is! Map) throw const FormatException('歌单节点必须是对象');
    roots.add(decoder.decode(item, null, 1));
  }
  final tree = PlaylistTree(roots);
  for (final playlist in tree.allPlaylists) {
    final sourceKey = playlist.legacyCollectionKey;
    if (sourceKey != null) migratedKeys.add(sourceKey);
  }
  return _PlaylistStore(roots,
      migratedCollectionKeys: migratedKeys,
      legacyCollectionsMigrated: migrated);
}

class _LegacyCollection {
  const _LegacyCollection({
    required this.id,
    required this.key,
    required this.name,
    required this.audios,
    required this.imagePath,
    required this.createdAt,
    required this.modifiedAt,
  });

  final String? id;
  final String key;
  final String name;
  final List<Audio> audios;
  final String? imagePath;
  final int createdAt;
  final int modifiedAt;
}

String _collectionKey(Object identity, int occurrence) =>
    'collection-v1:${sha256.convert(utf8.encode(json.encode([
          identity,
          occurrence
        ])))}';

int _readPlaylistTimestamp(Object? value) {
  if (value == null) return 0;
  if (value is! int) throw const FormatException('歌单时间戳必须是整数');
  return value;
}

String? _readPlaylistOptionalString(Object? value) {
  if (value == null || value is String) return value as String?;
  throw const FormatException('歌单封面或来源标识必须是字符串');
}

List<_LegacyCollection> _decodeLegacyCollections(Object? value) {
  if (value is! Map ||
      (value['version'] != null && value['version'] != 1) ||
      value['collections'] is! List) {
    throw const FormatException('旧合集文件格式无效，原文件已保留');
  }
  final result = <_LegacyCollection>[];
  final occurrences = <String, int>{};
  final decoder = _PlaylistDecoder();
  for (final item in value['collections'] as List) {
    if (item is! Map) throw const FormatException('旧合集条目必须是对象');
    final paths = item['audioPaths'];
    if (paths is! List ||
        paths.any((path) => path is! String || path.isEmpty)) {
      throw const FormatException('旧合集歌曲路径无效，未跳过或删除任何条目');
    }
    final id = item['id']?.toString();
    final name = item['name']?.toString() ?? '未命名歌单';
    final imagePath = _readPlaylistOptionalString(item['imagePath']);
    final createdAt = _readPlaylistTimestamp(item['createdAt']);
    final modifiedAt = _readPlaylistTimestamp(item['modifiedAt']);
    // Missing IDs get a content-derived identity, never a random ID or a
    // name-only key. An occurrence ordinal keeps even identical records apart.
    final identity = id == null
        ? ['missing-id', name, imagePath, createdAt, modifiedAt, paths]
        : ['id', id];
    final identityText = json.encode(identity);
    final occurrence = occurrences.update(identityText, (value) => value + 1,
        ifAbsent: () => 0);
    result.add(_LegacyCollection(
      id: id,
      key: _collectionKey(identity, occurrence),
      name: name,
      // Validate online identities here too, so a semantically broken primary
      // falls back to its whole good backup instead of failing after selection.
      audios: [
        for (final path in paths)
          decoder._decodeAudio({'path': path, 'created': 0}, strict: true)!,
      ],
      imagePath: imagePath,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
    ));
  }
  return result;
}

Future<List<_LegacyCollection>?> _readLegacyCollections(
    String directory) async {
  final primary = File('$directory\\collections.json');
  final backup = File('$directory\\collections.json.bak');
  Object? firstError;
  var foundFile = false;
  for (final candidate in [primary, backup]) {
    if (!await candidate.exists()) continue;
    foundFile = true;
    try {
      final collections =
          _decodeLegacyCollections(json.decode(await candidate.readAsString()));
      if (candidate.path == backup.path) {
        LOGGER.w('[playlists] 从旧合集备份恢复迁移；原主文件和备份均保留。');
      }
      return collections;
    } catch (error) {
      firstError ??= error;
    }
  }
  if (foundFile) {
    throw firstError ?? const FormatException('旧合集文件与备份均无法读取');
  }
  return null;
}

void _mergeLegacyCollections(
    _PlaylistStore store, List<_LegacyCollection> collections) {
  for (final collection in collections) {
    if (store.migratedCollectionKeys.contains(collection.key)) continue;
    final sourceHash = collection.key.substring('collection-v1:'.length);
    final playlist = Playlist._(
      'pl_collection_$sourceHash',
      collection.name,
      imagePath: collection.imagePath,
      createdAt: collection.createdAt,
      modifiedAt: collection.modifiedAt,
      legacyCollectionId: collection.id,
      legacyCollectionKey: collection.key,
    );
    for (var index = 0; index < collection.audios.length; index++) {
      final audio = collection.audios[index];
      playlist._entries.add(
          PlaylistAudioEntry._('pe_collection_${sourceHash}_$index', audio));
    }
    store.roots.add(playlist);
    store.migratedCollectionKeys.add(collection.key);
  }
  PlaylistTree(store.roots).validate();
  store.legacyCollectionsMigrated = true;
}

/// Decode the whole forest together so duplicate IDs or parent links across
/// roots cannot silently become separate editable copies of the same node.
List<Playlist> decodePlaylists(Object? value) =>
    _decodePlaylistStore(value).roots;

class _PlaylistDecoder {
  final Set<String> _ids = {};
  final Set<Map> _maps = HashSet<Map>.identity();

  String _claimId(Object? id) {
    if (id is! String || id.isEmpty || id.length > 200 || !_ids.add(id)) {
      throw const FormatException('歌单或曲目条目标识缺失、重复或无效');
    }
    return id;
  }

  String _freshId(String prefix) {
    String id;
    do {
      id = _newPlaylistId(prefix);
    } while (_ids.contains(id));
    return _claimId(id);
  }

  Playlist decode(Map map, Playlist? parent, int depth) {
    if (depth > PlaylistTree.maxDepth) {
      throw const FormatException('歌单嵌套不能超过 32 层');
    }
    if (!_maps.add(map)) {
      throw const FormatException('歌单包含循环或重复父级链接');
    }
    final version = map['version'];
    if (version != null && version != 1 && version != 2 && version != 3) {
      throw const FormatException('无法读取此版本的歌单文件');
    }
    final treeFormat =
        map.containsKey('entries') || version == 2 || version == 3;
    final playlist = Playlist._(
      treeFormat ? _claimId(map['id']) : _freshId('pl_'),
      map['name']?.toString() ?? '未命名歌单',
      imagePath: _readPlaylistOptionalString(map['imagePath']),
      createdAt: _readPlaylistTimestamp(map['createdAt']),
      modifiedAt: _readPlaylistTimestamp(map['modifiedAt']),
      legacyCollectionId:
          _readPlaylistOptionalString(map['legacyCollectionId']),
      legacyCollectionKey:
          _readPlaylistOptionalString(map['legacyCollectionKey']),
    ).._parent = parent;
    if (!treeFormat) {
      final legacy = map['audios'];
      if (legacy is! List) throw const FormatException('旧歌单 audios 必须是列表');
      final audios = <String, Audio>{};
      for (final item in legacy.whereType<Map>()) {
        final audio = _decodeAudio(item, strict: false);
        if (audio != null) audios[audio.path] = audio;
      }
      playlist._entries.addAll(audios.values.map(
        (audio) => PlaylistAudioEntry._(_freshId('pe_'), audio),
      ));
      return playlist;
    }

    final entries = map['entries'];
    if (entries is! List) throw const FormatException('歌单 entries 必须是列表');
    final paths = <String>{};
    for (final item in entries) {
      if (item is! Map) throw const FormatException('歌单条目必须是对象');
      switch (item['type']) {
        case 'audio':
          final id = _claimId(item['id']);
          final descriptor = item['audio'];
          if (descriptor is! Map) throw const FormatException('歌曲描述缺失');
          final audio = _decodeAudio(descriptor, strict: true)!;
          if (!paths.add(audio.path) && version != 3) {
            throw const FormatException('同一歌单不能重复包含同一路径的曲目');
          }
          playlist._entries.add(PlaylistAudioEntry._(id, audio));
        case 'playlist':
          final childMap = item['playlist'];
          if (childMap is! Map ||
              item['id'] is! String ||
              childMap['id'] is! String ||
              item['id'] != childMap['id']) {
            throw const FormatException('子歌单链接或标识无效');
          }
          final child = decode(childMap, playlist, depth + 1);
          playlist._entries.add(PlaylistChildEntry._(child));
        default:
          throw const FormatException('未知的歌单条目类型');
      }
    }
    return playlist;
  }

  Audio? _decodeAudio(Map item, {required bool strict}) {
    final savedPath = item['path']?.toString();
    final online =
        item['kind'] == 'online' || savedPath?.startsWith('online://') == true;
    if (online) {
      final descriptor = Map<Object?, Object?>.from(item);
      if (descriptor['provider'] == null || descriptor['id'] == null) {
        final uri = Uri.tryParse(savedPath ?? '');
        if (uri == null ||
            uri.scheme != 'online' ||
            uri.host.isEmpty ||
            uri.pathSegments.isEmpty) {
          if (strict) throw const FormatException('联网歌曲标识无效');
          LOGGER
              .w('[playlists] skipped invalid legacy online track: $savedPath');
          return null;
        }
        descriptor['provider'] = Uri.decodeComponent(uri.host);
        descriptor['id'] = uri.pathSegments.join('/');
      }
      final restored = Audio.fromOnlineMap(descriptor);
      final cached = AudioLibrary.instance.audioByPath[restored.path];
      // Never prefer an old cached fake-local online:// object over a valid
      // online descriptor; it would re-enable local-only editing actions.
      return cached?.isOnline == true ? cached : restored;
    }
    if (savedPath == null || savedPath.isEmpty) {
      if (strict) throw const FormatException('本地歌曲路径缺失');
      return null;
    }
    return AudioLibrary.instance.audioByPath[savedPath] ?? Audio.fromMap(item);
  }
}
