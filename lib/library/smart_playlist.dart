import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:path/path.dart' as p;

enum SmartPlaylistSort { name, artist, album, newest, duration }

/// Saved conditions, not a frozen list of song paths. Evaluation only uses
/// loaded library metadata; it never opens audio files or contacts a provider.
class SmartPlaylist {
  const SmartPlaylist(
      {required this.id,
      required this.name,
      this.query = '',
      this.artist = '',
      this.album = '',
      this.formats = '',
      this.minSeconds,
      this.maxSeconds,
      this.sort = SmartPlaylistSort.name});
  final String id, name, query, artist, album, formats;
  final int? minSeconds, maxSeconds;
  final SmartPlaylistSort sort;

  String? validate() {
    if (id.isEmpty ||
        id.length > 100 ||
        name.trim().isEmpty ||
        name.length > 120) {
      return '请输入 1–120 个字符的智能歌单名称。';
    }
    if ([query, artist, album, formats].any((text) => text.length > 160)) {
      return '每条筛选条件最多 160 个字符。';
    }
    if ([minSeconds, maxSeconds]
            .any((value) => value != null && (value < 0 || value > 86400)) ||
        (minSeconds != null &&
            maxSeconds != null &&
            minSeconds! > maxSeconds!)) {
      return '时长须为 0–86400 秒，最短时长不能超过最长时长。';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'query': query,
        'artist': artist,
        'album': album,
        'formats': formats,
        'minSeconds': minSeconds,
        'maxSeconds': maxSeconds,
        'sort': sort.name
      };

  static SmartPlaylist fromJson(Object? raw) {
    if (raw is! Map ||
        ['id', 'name', 'query', 'artist', 'album', 'formats']
            .any((key) => raw[key] is! String) ||
        (raw['minSeconds'] != null && raw['minSeconds'] is! int) ||
        (raw['maxSeconds'] != null && raw['maxSeconds'] is! int)) {
      throw const FormatException('Invalid smart playlist');
    }
    final value = SmartPlaylist(
        id: raw['id'],
        name: raw['name'],
        query: raw['query'],
        artist: raw['artist'],
        album: raw['album'],
        formats: raw['formats'],
        minSeconds: raw['minSeconds'],
        maxSeconds: raw['maxSeconds'],
        sort: SmartPlaylistSort.values
            .firstWhere((sort) => sort.name == raw['sort']));
    if (value.validate() != null) {
      throw const FormatException('Invalid smart playlist rules');
    }
    return value;
  }

  Future<List<Audio>> evaluate(Iterable<Audio> library,
      {bool Function()? shouldCancel}) async {
    final failure = validate();
    if (failure != null) throw FormatException(failure);
    final words = query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final performer = artist.toLowerCase().trim();
    final record = album.toLowerCase().trim();
    final extensions = formats
        .toLowerCase()
        .split(RegExp(r'[,，;；\s]+'))
        .map((value) => value.replaceFirst(RegExp(r'^\.'), ''))
        .where((s) => s.isNotEmpty)
        .toSet();
    final output = <Audio>[];
    final snapshot = List<Audio>.of(library);
    for (var index = 0; index < snapshot.length; index++) {
      if (index % 512 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (shouldCancel?.call() == true) return const [];
      }
      final audio = snapshot[index];
      if (!audio.isLocal) continue;
      if (minSeconds != null && audio.duration < minSeconds!) continue;
      if (maxSeconds != null && audio.duration > maxSeconds!) continue;
      if (performer.isNotEmpty &&
          !audio.artist.toLowerCase().contains(performer)) {
        continue;
      }
      if (record.isNotEmpty && !audio.album.toLowerCase().contains(record)) {
        continue;
      }
      if (extensions.isNotEmpty &&
          !extensions.contains(p.windows
              .extension(audio.path)
              .toLowerCase()
              .replaceFirst('.', ''))) {
        continue;
      }
      if (words.isNotEmpty) {
        final haystack =
            '${audio.title} ${audio.fileNameTitle} ${audio.artist} ${audio.album}'
                .toLowerCase();
        if (!words.every(haystack.contains)) continue;
      }
      output.add(audio);
    }
    final keys = <_SmartSortKey>[];
    for (var index = 0; index < output.length; index++) {
      if (index % 512 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (shouldCancel?.call() == true) return const [];
      }
      final audio = output[index];
      keys.add((
        index: index,
        text: switch (sort) {
          SmartPlaylistSort.name => audio.displayTitle.toLowerCase(),
          SmartPlaylistSort.artist => audio.artist.toLowerCase(),
          SmartPlaylistSort.album => audio.album.toLowerCase(),
          _ => '',
        },
        number:
            sort == SmartPlaylistSort.newest ? -audio.created : audio.duration,
        tie: audio.path.toLowerCase()
      ));
    }
    final numeric =
        sort == SmartPlaylistSort.newest || sort == SmartPlaylistSort.duration;
    // Send only immutable scalar keys, never Audio objects or their caches.
    final order = await Isolate.run(() => _sortSmartKeys(keys, numeric));
    if (shouldCancel?.call() == true) return const [];
    return List.unmodifiable([for (final index in order) output[index]]);
  }
}

typedef _SmartSortKey = ({int index, String text, int number, String tie});

List<int> _sortSmartKeys(List<_SmartSortKey> keys, bool numeric) {
  keys.sort((a, b) {
    final value =
        numeric ? a.number.compareTo(b.number) : a.text.compareTo(b.text);
    if (value != 0) return value;
    final tie = a.tie.compareTo(b.tie);
    return tie != 0 ? tie : a.index.compareTo(b.index);
  });
  return [for (final key in keys) key.index];
}

/// Serial atomic saves, with one recovery snapshot. Invalid files are never
/// silently replaced by an empty rule list. The complete app-data backup also
/// includes this JSON file through its existing recursive backup path.
class SmartPlaylistStore {
  SmartPlaylistStore(this.file);
  final File file;
  static Future<SmartPlaylistStore>? _instance;
  static Future<SmartPlaylistStore> get instance => _instance ??= _openStore();

  static Future<SmartPlaylistStore> _openStore() async {
    try {
      final directory = await getAppDataDir();
      return SmartPlaylistStore(
          File(p.join(directory.path, 'smart_playlists.json')));
    } catch (_) {
      // A transient data-directory failure must remain retryable in the UI.
      _instance = null;
      rethrow;
    }
  }

  static const maxPlaylists = 100;
  static const maxBytes = 512 * 1024;
  Future<void> _pending = Future.value();
  List<SmartPlaylist>? _items;
  bool _recovered = false;

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _load() async {
    if (_items != null) return;
    Object? failure;
    for (final candidate in [file, File('${file.path}.bak')]) {
      if (!await candidate.exists()) continue;
      try {
        final bytes = await candidate
            .openRead(0, maxBytes + 1)
            .fold<List<int>>([], (all, part) => all..addAll(part));
        if (bytes.length > maxBytes) {
          throw const FormatException('Smart playlist file too large');
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map ||
            json['version'] != 1 ||
            json['playlists'] is! List ||
            (json['playlists'] as List).length > maxPlaylists) {
          throw const FormatException('Invalid smart playlist file');
        }
        final next =
            (json['playlists'] as List).map(SmartPlaylist.fromJson).toList();
        if (next.map((item) => item.id).toSet().length != next.length) {
          throw const FormatException('Duplicate smart playlist IDs');
        }
        _items = next;
        _recovered = candidate.path != file.path;
        return;
      } catch (error) {
        failure = error;
      }
    }
    if (failure != null) throw failure;
    _items = [];
  }

  Future<List<SmartPlaylist>> list() => _exclusive(() async {
        await _load();
        return List.unmodifiable(_items!);
      });

  Future<void> upsert(SmartPlaylist playlist) => _exclusive(() async {
        final error = playlist.validate();
        if (error != null) throw FormatException(error);
        await _load();
        final next = List<SmartPlaylist>.of(_items!);
        final index = next.indexWhere((item) => item.id == playlist.id);
        if (index >= 0) {
          next[index] = playlist;
        } else {
          next.add(playlist);
        }
        if (next.length > maxPlaylists) {
          throw const FormatException('最多可保存 100 个智能歌单。');
        }
        await _save(next);
      });

  Future<void> remove(String id) => _exclusive(() async {
        await _load();
        await _save(_items!.where((item) => item.id != id).toList());
      });

  Future<void> _save(List<SmartPlaylist> next) async {
    final bytes = utf8.encode(jsonEncode({
      'version': 1,
      'playlists': next.map((item) => item.toJson()).toList()
    }));
    if (bytes.length > maxBytes) {
      throw const FormatException('Smart playlist file too large');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (!_recovered && await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      await temp.rename(file.path);
      _items = next;
      _recovered = false;
    } catch (_) {
      if (!await file.exists() && await backup.exists()) {
        await backup.copy(file.path);
      }
      rethrow;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}
