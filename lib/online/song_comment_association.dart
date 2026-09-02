import 'dart:convert';
import 'dart:io';

import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/lyric/lyric_source.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_util;

enum SongCommentAssociationMode {
  followLyric('跟随联网歌词'),
  independent('独立指定');

  const SongCommentAssociationMode(this.label);
  final String label;
}

/// A provider identity which is safe to persist. It never contains a local
/// path, an account token or a search query.
class CommentSourceIdentity {
  const CommentSourceIdentity({required this.provider, required this.songId});

  final String provider;
  final String songId;

  String get sourceLabel {
    if (provider == 'qq') return 'QQ音乐';
    if (provider == 'netease') return '网易云音乐';
    final profileId = _customProfileId(provider);
    if (profileId != null) {
      for (final profile in AppSettings.instance.customMusicSources.value) {
        if (profile.id == profileId) return profile.name;
      }
      return '自定义歌源';
    }
    return provider;
  }

  String get identity => '$provider:$songId';

  static CommentSourceIdentity? tryCreate(String? provider, Object? id) {
    final rawProvider = provider?.trim();
    final normalizedId = id?.toString().trim();
    if (rawProvider == null || normalizedId == null) {
      return null;
    }
    final builtInProvider = rawProvider.toLowerCase();
    if (const {'qq', 'netease'}.contains(builtInProvider)) {
      if (!_positiveId(normalizedId)) return null;
      return CommentSourceIdentity(
        provider: builtInProvider,
        songId: normalizedId,
      );
    }
    final customProfileId = _customProfileId(rawProvider);
    if (customProfileId == null || !_safeOpaqueSongId(normalizedId)) {
      return null;
    }
    return CommentSourceIdentity(
      provider: '$_customProviderPrefix$customProfileId',
      songId: normalizedId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CommentSourceIdentity && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

class SongCommentAssociation {
  const SongCommentAssociation({
    required this.mode,
    this.provider,
    this.songId,
    this.title,
    this.composer,
    this.album,
  });

  final SongCommentAssociationMode mode;
  final String? provider;
  final String? songId;

  /// Display-only snapshot. Composer deliberately remains distinct from the
  /// performer; a provider which does not return it is shown as unavailable.
  final String? title;
  final String? composer;
  final String? album;

  CommentSourceIdentity? get independentIdentity =>
      mode == SongCommentAssociationMode.independent
          ? CommentSourceIdentity.tryCreate(provider, songId)
          : null;

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        if (provider != null) 'provider': provider,
        if (songId != null) 'songId': songId,
        if (title != null) 'title': title,
        if (composer != null) 'composer': composer,
        if (album != null) 'album': album,
      };

  static SongCommentAssociation? fromJson(Object? value) {
    if (value is! Map) return null;
    final mode = switch (value['mode']) {
      'followLyric' => SongCommentAssociationMode.followLyric,
      'independent' => SongCommentAssociationMode.independent,
      _ => null,
    };
    if (mode == null) return null;
    final association = SongCommentAssociation(
      mode: mode,
      provider: _optionalText(value['provider']),
      songId: _optionalText(value['songId']),
      title: _optionalText(value['title']),
      composer: _optionalText(value['composer']),
      album: _optionalText(value['album']),
    );
    if (mode == SongCommentAssociationMode.independent &&
        association.independentIdentity == null) {
      return null;
    }
    return association;
  }
}

/// Persistent local-track-to-platform association used by the read-only
/// comments feature. This store is separate from lyric_source.json so choosing
/// comments can never silently change a user's lyric selection.
class SongCommentAssociationStore extends ChangeNotifier {
  SongCommentAssociationStore._();

  static final instance = SongCommentAssociationStore._();
  static const fileName = 'song_comment_associations.json';

  final Map<String, SongCommentAssociation> _items = {};
  File? _file;
  Future<void> _mutationTail = Future<void>.value();

  bool get initialized => _file != null;

  SongCommentAssociation? associationFor(Audio audio) =>
      audio.isLocal ? _items[_pathKey(audio.path)] : null;

  CommentSourceIdentity? lyricIdentityFor(Audio audio) {
    if (!audio.isLocal) return null;
    final source = LYRIC_SOURCES[audio.path];
    if (source == null) return null;
    return switch (source.source) {
      LyricSourceType.qq =>
        CommentSourceIdentity.tryCreate('qq', source.qqSongId),
      LyricSourceType.netease =>
        CommentSourceIdentity.tryCreate('netease', source.neteaseSongId),
      LyricSourceType.kugou ||
      LyricSourceType.lrclib ||
      LyricSourceType.local =>
        null,
    };
  }

  CommentSourceIdentity? identityFor(Audio audio) {
    if (audio.isOnline) {
      return CommentSourceIdentity.tryCreate(
        audio.onlineProvider,
        audio.onlineProvider == 'qq' ? audio.onlineNumericId : audio.onlineId,
      );
    }
    final association = associationFor(audio);
    if (association == null) return null;
    return association.mode == SongCommentAssociationMode.followLyric
        ? lyricIdentityFor(audio)
        : association.independentIdentity;
  }

  Future<void> initialize({Directory? directory}) async {
    final root = directory ?? await getAppDataDir();
    final target = File(path_util.join(root.path, fileName));
    _file = target;
    _items.clear();
    final decoded = await _readRootWithBackup(target);
    if (decoded != null) {
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final association = SongCommentAssociation.fromJson(entry.value);
        if (key.isEmpty || association == null) continue;
        _items[_pathKey(key)] = association;
      }
    }
    notifyListeners();
  }

  Future<void> followLyric(Audio audio) async {
    if (!audio.isLocal) {
      throw const FormatException('联网歌曲已自带平台身份，无需本地关联');
    }
    if (lyricIdentityFor(audio) == null) {
      throw const FormatException('当前歌词来源没有可用于评论的 QQ音乐或网易云歌曲 ID');
    }
    await _replace(
      audio.path,
      const SongCommentAssociation(
        mode: SongCommentAssociationMode.followLyric,
      ),
    );
  }

  Future<void> setIndependent(Audio audio, Audio candidate) async {
    if (!audio.isLocal || !candidate.isOnline) {
      throw const FormatException('只能为本地歌曲关联联网候选');
    }
    final identity = CommentSourceIdentity.tryCreate(
      candidate.onlineProvider,
      candidate.onlineProvider == 'qq'
          ? candidate.onlineNumericId
          : candidate.onlineId,
    );
    if (identity == null) {
      throw const FormatException('候选歌曲缺少可核实的安全平台歌曲 ID');
    }
    await _replace(
      audio.path,
      SongCommentAssociation(
        mode: SongCommentAssociationMode.independent,
        provider: identity.provider,
        songId: identity.songId,
        title: candidate.title,
        composer: candidate.composer,
        album: candidate.album,
      ),
    );
  }

  Future<void> remove(Audio audio) async {
    if (!audio.isLocal) return;
    await _replace(audio.path, null);
  }

  /// Keeps an app-created rename associated without guessing by title.
  Future<void> movePath(String oldPath, String newPath) async {
    await _serializeMutation(() async {
      final oldKey = _pathKey(oldPath);
      final value = _items[oldKey];
      if (value == null || oldKey == _pathKey(newPath)) return;
      final snapshot = Map<String, SongCommentAssociation>.from(_items);
      _items.remove(oldKey);
      _items[_pathKey(newPath)] = value;
      notifyListeners();
      try {
        await _save();
      } catch (_) {
        _items
          ..clear()
          ..addAll(snapshot);
        notifyListeners();
        rethrow;
      }
    });
  }

  Future<void> _replace(
      String audioPath, SongCommentAssociation? association) async {
    await _serializeMutation(() async {
      if (_file == null) await initialize();
      final snapshot = Map<String, SongCommentAssociation>.from(_items);
      final key = _pathKey(audioPath);
      if (association == null) {
        _items.remove(key);
      } else {
        _items[key] = association;
      }
      notifyListeners();
      try {
        await _save();
      } catch (_) {
        _items
          ..clear()
          ..addAll(snapshot);
        notifyListeners();
        rethrow;
      }
    });
  }

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) {
      throw StateError('Comment association store is not ready');
    }
    final payload = jsonEncode({
      'version': 1,
      'items': {
        for (final entry in _items.entries) entry.key: entry.value.toJson()
      },
    });
    await _writeAtomically(file, payload);
  }

  @visibleForTesting
  void resetForTesting() {
    _file = null;
    _items.clear();
    _mutationTail = Future<void>.value();
  }
}

Future<Map?> _readRootWithBackup(File target) async {
  Object? firstError;
  for (final candidate in [target, File('${target.path}.bak')]) {
    try {
      if (!await candidate.exists()) continue;
      final decoded = jsonDecode(await candidate.readAsString());
      if (decoded is! Map) {
        throw const FormatException('Root must be an object');
      }
      final items = decoded['items'];
      if (items is! Map) throw const FormatException('Items must be an object');
      return items;
    } catch (error, trace) {
      firstError ??= error;
      LOGGER.w('[song comments] skipped invalid association file: $error',
          stackTrace: trace);
    }
  }
  if (firstError != null) {
    LOGGER.w('[song comments] no valid association backup was available');
  }
  return null;
}

Future<void> _writeAtomically(File target, String contents) async {
  await target.parent.create(recursive: true);
  final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
  final temporary = File('${target.path}.$suffix.tmp');
  final backup = File('${target.path}.bak');
  await temporary.writeAsString(contents, flush: true);
  var movedTarget = false;
  try {
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) {
      await target.rename(backup.path);
      movedTarget = true;
    }
    await temporary.rename(target.path);
  } catch (_) {
    if (movedTarget && !await target.exists() && await backup.exists()) {
      try {
        await backup.rename(target.path);
      } catch (restoreError, trace) {
        LOGGER.e('[song comments] association restore failed: $restoreError',
            stackTrace: trace);
      }
    }
    rethrow;
  } finally {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {}
    }
  }
}

String _pathKey(String value) =>
    path_util.normalize(value.trim()).replaceAll('/', r'\').toLowerCase();

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _positiveId(String value) =>
    RegExp(r'^[0-9]{1,20}$').hasMatch(value) &&
    BigInt.parse(value) > BigInt.zero;

const _customProviderPrefix = 'custom:';

String? _customProfileId(String provider) {
  if (!provider.startsWith(_customProviderPrefix)) return null;
  final profileId = provider.substring(_customProviderPrefix.length);
  return profileId.length <= 96 &&
          RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(profileId)
      ? profileId
      : null;
}

/// Keep the persisted remote identifier opaque: it may be a hash or UUID, but
/// never a path, URL, query, control text or whitespace-bearing search term.
bool _safeOpaqueSongId(String value) =>
    value.length <= 256 &&
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._~-]*$').hasMatch(value);
