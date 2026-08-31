import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/src/rust/api/tag_reader.dart';
import 'package:dan_player/utils.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path_util;

/// from index.json
class AudioLibrary {
  List<AudioFolder> folders;

  AudioLibrary._(this.folders);

  List<String>? _scanRoots;

  /// Selected roots, including empty roots. Legacy indexes retain their
  /// recorded folders until a full scan records the explicitly selected roots.
  List<String> get scanRoots => List.unmodifiable(
      _scanRoots ?? folders.map((folder) => folder.path).toSet());

  /// 所有音乐
  List<Audio> audioCollection = [];

  /// 用户加入总乐库的联网音乐。它们独立于本地文件夹索引持久化，避免本地
  /// 扫描器把没有实体文件的条目当作失效文件删除。
  List<Audio> onlineAudioCollection = [];

  Map<String, Artist> artistCollection = {};

  Map<String, Album> albumCollection = {};

  Map<String, Audio>? _audioByPath;

  Map<String, Audio> get audioByPath =>
      _audioByPath ??= {for (final audio in audioCollection) audio.path: audio};

  static int revision = 0;

  /// Published only after all local/online derived collections are complete.
  static final changes = ValueNotifier<int>(0);

  /// must call [initFromIndex]
  static AudioLibrary get instance {
    _instance ??= AudioLibrary._([]);
    return _instance!;
  }

  static AudioLibrary? _instance;

  static Future<Map> _readIndexMap(File indexFile) async {
    Object? targetError;
    final backupFile = File("${indexFile.path}.bak");
    for (final candidate in [indexFile, backupFile]) {
      try {
        if (!await candidate.exists()) continue;
        final decoded = json.decode(await candidate.readAsString());
        if (decoded is! Map) {
          throw const FormatException("Audio index root must be an object");
        }
        if (candidate.path == backupFile.path) {
          LOGGER.w("[audio library] loaded backup index");
        }
        return decoded;
      } catch (error) {
        targetError ??= error;
      }
    }
    throw targetError ?? const FormatException("Audio index is unavailable");
  }

  static Future<void> _writeIndexAtomically(
    File target,
    String contents,
  ) async {
    await target.parent.create(recursive: true);
    final temporary = File("${target.path}.tmp");
    final backup = File("${target.path}.bak");
    await temporary.writeAsString(contents, flush: true);

    try {
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      await temporary.rename(target.path);
    } catch (_) {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
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

  /// 目前 index 结构：
  /// ```json
  /// {
  ///     "folders": [
  ///         {
  ///             "audios": [
  ///                 {...},
  ///                 ...
  ///             ],
  ///             ...
  ///         },
  ///         ...
  ///     ],
  ///     "version": 112
  /// }
  /// ```
  static Future<void> initFromIndex() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final indexPath = "$supportPath\\index.json";
      final indexFile = File(indexPath);
      if (!await indexFile.exists() && !await File("$indexPath.bak").exists()) {
        _instance ??= AudioLibrary._([]);
        return;
      }

      final indexJson = await _readIndexMap(indexFile);
      final foldersValue = indexJson["folders"];
      if (foldersValue is! List) {
        throw const FormatException("Audio index folders must be a list");
      }
      final List<AudioFolder> folders = [];

      for (final folderValue in foldersValue) {
        if (folderValue is! Map) continue;
        final audiosValue = folderValue["audios"];
        if (audiosValue is! List) continue;
        final List<Audio> audios = [];
        for (final audioValue in audiosValue) {
          if (audioValue is! Map) continue;
          try {
            audios.add(Audio.fromMap(audioValue));
          } catch (error) {
            LOGGER.w("[audio library] skipped invalid audio entry: $error");
          }
        }
        try {
          folders.add(AudioFolder.fromMap(folderValue, audios));
        } catch (error) {
          LOGGER.w("[audio library] skipped invalid folder entry: $error");
        }
      }

      final onlineAudios = List<Audio>.from(instance.onlineAudioCollection);
      final roots = indexJson['roots'];
      if (roots != null &&
          (roots is! List || roots.any((root) => root is! String))) {
        throw const FormatException('Audio index roots must be strings');
      }
      _instance = AudioLibrary._(folders)
        .._scanRoots = roots == null ? null : List<String>.from(roots)
        ..onlineAudioCollection = onlineAudios;

      instance.artistCollection.clear();
      instance.albumCollection.clear();
      instance._buildCollections();
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      rethrow;
    }
  }

  void _buildCollections() {
    _audioByPath = null;
    revision++;
    for (var f in folders) {
      audioCollection.addAll(f.audios);
    }
    audioCollection.addAll(onlineAudioCollection);

    for (Audio audio in audioCollection) {
      for (String artistName in audio.splitedArtists) {
        /// 如果artistCollection中有artistName指向的artist，putIfAbsent会返回该artist。
        /// 随后往这个artist里添加该audio。
        ///
        /// 如果没有，创建一个名字为artistName的空艺术家，并将artistName与之相连。
        /// 随后往这个artist里添加该audio。
        artistCollection
            .putIfAbsent(artistName, () => Artist(name: artistName))
            .works
            .add(audio);
      }

      /// 如果albumCollection中有audio.album指向的album，putIfAbsent会返回该album。
      /// 随后往这个album里添加该audio。
      ///
      /// 如果没有，创建一个名字为audio.album的空艺术家，并将audio.album与之相连。
      /// 随后往这个album里添加该audio。
      albumCollection
          .putIfAbsent(audio.album, () => Album(name: audio.album))
          .works
          .add(audio);
    }

    /// 将艺术家和专辑链接起来
    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.album,
          () => albumCollection[audio.album]!,
        );
      }
    }

    /// 将专辑和艺术家链接起来
    for (Album album in albumCollection.values) {
      for (Audio audio in album.works) {
        for (String artistName in audio.splitedArtists) {
          album.artistsMap.putIfAbsent(
            artistName,
            () => artistCollection[artistName]!,
          );
        }
      }
    }
    changes.value = revision;
  }

  void rebuildDerivedCollections() {
    audioCollection.clear();
    artistCollection.clear();
    albumCollection.clear();
    _audioByPath = null;
    _buildCollections();
  }

  void replaceOnlineAudios(Iterable<Audio> audios) {
    onlineAudioCollection = List<Audio>.from(audios);
    rebuildDerivedCollections();
  }

  Future<void> saveIndex() async {
    try {
      final supportPath = (await getAppDataDir()).path;
      final indexPath = "$supportPath\\index.json";
      await _writeIndexAtomically(
        File(indexPath),
        json.encode({
          "version": 113,
          "roots": scanRoots,
          "folders": folders.map((item) => item.toMap()).toList(),
        }),
      );
    } catch (err, trace) {
      LOGGER.e(err, stackTrace: trace);
      rethrow;
    }
  }

  @override
  String toString() {
    return folders.toString();
  }
}

class AudioFolder {
  List<Audio> audios;

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int latest;

  AudioFolder(this.audios, this.path, this.modified, this.latest);

  factory AudioFolder.fromMap(Map map, List<Audio> audios) {
    final folderPath = map["path"];
    if (folderPath is! String || folderPath.isEmpty) {
      throw const FormatException("Invalid audio folder path");
    }
    return AudioFolder(
      audios,
      folderPath,
      (map["modified"] as num?)?.toInt() ?? 0,
      (map["latest"] as num?)?.toInt() ?? 0,
    );
  }

  Map toMap() => {
        "audios": audios.map((audio) => audio.toMap()).toList(),
        "path": path,
        "modified": modified,
        "latest": latest,
      };

  @override
  String toString() {
    return {
      "audios": audios.toString(),
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
    }.toString();
  }
}

class Audio {
  String title;

  /// 从音乐标签中读取的艺术家字符串，可能包含多个艺术家，以“、”，“/”等分隔。
  String artist;

  /// 分割[artist]得到的结果
  List<String> splitedArtists;

  String album;

  /// Explicit source tags; never inferred from the performer or file name.
  String? composer;
  String? albumArtist;

  /// Old indexes without these tags remain pending for incremental backfill.
  int classificationVersion;

  /// 0: 没有track
  int track;

  /// audio's duration in secs
  int duration;

  /// kbps
  int? bitrate;

  int? sampleRate;

  /// 原始语言标签；没有标签时不根据文件名填充。
  String? language;

  /// 扫描索引时的字节数快照。统计页会重新核实文件，不能当作现存占用。
  int? fileSizeBytes;

  /// Native nanosecond mtime is a decimal string to avoid JSON precision loss.
  String? modifiedNanos;
  bool metadataReadPending;

  String? get coverFingerprint =>
      modifiedNanos == null ? null : '${modifiedNanos}_s${fileSizeBytes ?? 0}';

  /// absolute path
  String path;

  /// secs since UNIX EPOCH
  int modified;

  /// secs since UNIX EPOCH
  int created;

  /// 标签来源（Lofty、Windows、null）
  String? by;

  /// 联网曲目的来源与服务端标识。本地曲目这些字段都为空。
  final String? onlineProvider;
  final String? onlineId;
  final String? onlineMediaId;
  final int? onlineNumericId;
  final String? artworkUrl;

  /// 以“、”和“/”分割艺术家，会把名称中带有这些符号的艺术家分割。
  /// 暂时想不到别的方法。
  Audio(
    this.title,
    this.artist,
    this.album,
    this.track,
    this.duration,
    this.bitrate,
    this.sampleRate,
    this.path,
    this.modified,
    this.created,
    this.by, {
    this.composer,
    this.albumArtist,
    this.classificationVersion = 1,
    this.language,
    this.fileSizeBytes,
    this.modifiedNanos,
    this.metadataReadPending = false,
    this.onlineProvider,
    this.onlineId,
    this.onlineMediaId,
    this.onlineNumericId,
    this.artworkUrl,
  }) : splitedArtists = artist.split(
          RegExp(AppSettings.instance.artistSplitPattern),
        );

  factory Audio.online({
    required String provider,
    required String id,
    required String title,
    required String artist,
    required String album,
    required int duration,
    String? mediaId,
    int? numericId,
    String? artworkUrl,
    int? bitrate,
    int? created,
    String? language,
    String? composer,
    String? albumArtist,
    int classificationVersion = 1,
  }) {
    final safeProvider = Uri.encodeComponent(provider);
    final safeId = Uri.encodeComponent(id);
    return Audio(
      title,
      artist.trim().isEmpty ? "UNKNOWN" : artist,
      album.trim().isEmpty ? "UNKNOWN" : album,
      0,
      duration,
      bitrate,
      null,
      "online://$safeProvider/$safeId",
      0,
      created ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "Online/$provider",
      composer: composer,
      albumArtist: albumArtist,
      classificationVersion: classificationVersion,
      language: language,
      onlineProvider: provider,
      onlineId: id,
      onlineMediaId: mediaId,
      onlineNumericId: numericId,
      artworkUrl: artworkUrl,
    );
  }

  factory Audio.fromOnlineMap(Map map) {
    final provider = map["provider"]?.toString();
    final id = map["id"]?.toString();
    if (provider == null || provider.isEmpty || id == null || id.isEmpty) {
      throw const FormatException("Invalid online audio identity");
    }
    return Audio.online(
      provider: provider,
      id: id,
      title: map["title"]?.toString() ?? "UNKNOWN",
      artist: map["artist"]?.toString() ?? "UNKNOWN",
      album: map["album"]?.toString() ?? "UNKNOWN",
      duration: (map["duration"] as num?)?.toInt() ?? 0,
      mediaId: map["mediaId"]?.toString(),
      numericId: (map["numericId"] as num?)?.toInt(),
      artworkUrl: map["artworkUrl"]?.toString(),
      bitrate: (map["bitrate"] as num?)?.toInt(),
      created: (map["created"] as num?)?.toInt(),
      language: map["language"] is String ? map["language"] : null,
      composer: _optionalTag(map["composer"]),
      albumArtist: _optionalTag(map["albumArtist"] ?? map["album_artist"]),
      classificationVersion: _readClassificationVersion(
          map["classificationVersion"] ?? map["classification_version"]),
    );
  }

  bool get isOnline => onlineProvider != null && onlineId != null;
  bool get classificationTagsRead => classificationVersion >= 1;
  bool get isLocal => !isOnline;
  String get sourceLabel => switch (onlineProvider) {
        "qq" => "QQ音乐",
        "netease" => "网易云音乐",
        final String provider => provider,
        null => "本地",
      };

  String get fileNameTitle =>
      isOnline ? title : path_util.basenameWithoutExtension(path);

  String get displayTitle {
    if (isOnline) return title;
    final name = fileNameTitle.trim();
    return name.isEmpty ? title : name;
  }

  void applyEditedMetadata({
    required String newPath,
    required String newTitle,
    required String newArtist,
    required String newAlbum,
    required int newModified,
  }) {
    path = newPath;
    title = newTitle;
    artist = newArtist;
    album = newAlbum;
    modified = newModified;
    // The edit result provides seconds only. Re-establish the exact native
    // fingerprint on the next refresh instead of trusting the previous stamp.
    modifiedNanos = null;
    splitedArtists = artist.split(
      RegExp(AppSettings.instance.artistSplitPattern),
    );
  }

  factory Audio.fromMap(Map map) {
    final audioPath = map["path"];
    if (audioPath is! String || audioPath.isEmpty) {
      throw const FormatException("Invalid audio path");
    }
    return Audio(
      map["title"] is String ? map["title"] : path_util.basename(audioPath),
      map["artist"] is String ? map["artist"] : "UNKNOWN",
      map["album"] is String ? map["album"] : "UNKNOWN",
      (map["track"] as num?)?.toInt() ?? 0,
      (map["duration"] as num?)?.toInt() ?? 0,
      (map["bitrate"] as num?)?.toInt(),
      (map["sample_rate"] as num?)?.toInt(),
      audioPath,
      (map["modified"] as num?)?.toInt() ?? 0,
      (map["created"] as num?)?.toInt() ?? 0,
      map["by"]?.toString(),
      composer: _optionalTag(map["composer"]),
      albumArtist: _optionalTag(map["album_artist"]),
      classificationVersion:
          _readClassificationVersion(map["classification_version"]),
      language: map["language"] is String ? map["language"] : null,
      fileSizeBytes:
          map["file_size"] is num ? (map["file_size"] as num).toInt() : null,
      modifiedNanos: map['modified_ns'] is String ? map['modified_ns'] : null,
      metadataReadPending: map['metadata_pending'] == true,
    );
  }

  Map toMap() => {
        "title": title,
        "artist": artist,
        "album": album,
        "composer": composer,
        "album_artist": albumArtist,
        "classification_version": classificationVersion,
        "track": track,
        "duration": duration,
        "bitrate": bitrate,
        "sample_rate": sampleRate,
        "language": language,
        "file_size": fileSizeBytes,
        "modified_ns": modifiedNanos,
        "metadata_pending": metadataReadPending,
        "path": path,
        "modified": modified,
        "created": created,
        "by": by
      };

  Map<String, Object?> toOnlineMap() => {
        "provider": onlineProvider,
        "id": onlineId,
        "mediaId": onlineMediaId,
        "numericId": onlineNumericId,
        "title": title,
        "artist": artist,
        "album": album,
        "composer": composer,
        "albumArtist": albumArtist,
        "classificationVersion": classificationVersion,
        "duration": duration,
        "bitrate": bitrate,
        "artworkUrl": artworkUrl,
        "created": created,
        "language": language,
      };

  static String? _optionalTag(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static int _readClassificationVersion(Object? value) =>
      value is int && value >= 1 ? value : 0;

  /// Load a bounded thumbnail for a physical-pixel request. UI callers should
  /// use AudioArtwork or pass their own View DPR to [coverForDisplay].
  Future<ImageProvider?> artworkForSize(ArtworkSize size) async {
    final remoteArtwork = artworkUrl;
    if (isOnline && remoteArtwork != null && remoteArtwork.isNotEmpty) {
      final uri = Uri.tryParse(remoteArtwork);
      if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
        final sizedUri = artworkUriForSize(uri, size, provider: onlineProvider);
        return ArtworkImageProvider(NetworkImage(sizedUri.toString()), size);
      }
    }
    if (isOnline) return null;
    // Capture mutable metadata now: an edit must not make a queued request
    // read a different file and cache it under the previous file's identity.
    final requestedPath = path;
    final requestedModified = modified;
    final requestedFingerprint = coverFingerprint;
    return CoverCache.instance.imageFor(
      audioPath: requestedPath,
      modified: requestedModified,
      fingerprint: requestedFingerprint,
      width: size.width,
      height: size.height,
      produce: () => getPictureFromPath(
        path: requestedPath,
        width: size.width,
        height: size.height,
      ),
    );
  }

  Future<ImageProvider?> coverForDisplay({
    required double size,
    required double devicePixelRatio,
  }) =>
      artworkForSize(ArtworkSize.forDisplay(
        logicalWidth: size,
        logicalHeight: size,
        devicePixelRatio: devicePixelRatio,
      ));

  // Compatibility for non-widget/background consumers. Crisp foreground
  // artwork always passes the current View's DPR explicitly. No single cached
  // 48px provider can survive a transition to a higher-density monitor.
  double get _defaultDpr =>
      PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;

  Future<ImageProvider?> get cover =>
      coverForDisplay(size: 48, devicePixelRatio: _defaultDpr);
  Future<ImageProvider?> get mediumCover =>
      coverForDisplay(size: 200, devicePixelRatio: _defaultDpr);
  Future<ImageProvider?> get largeCover =>
      coverForDisplay(size: 400, devicePixelRatio: _defaultDpr);

  @override
  String toString() {
    return {
      "title": title,
      "artist": artist,
      "album": album,
      "path": path,
      "modified":
          DateTime.fromMillisecondsSinceEpoch(modified * 1000).toString(),
      "created": DateTime.fromMillisecondsSinceEpoch(created * 1000).toString(),
    }.toString();
  }
}

class Artist {
  String name;

  /// 所有专辑
  Map<String, Album> albumsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在artist detail page
  /// 200*200
  Future<ImageProvider?> get picture => works.first.mediumCover;

  Artist({required this.name});
}

class Album {
  String name;

  /// 参与的艺术家
  Map<String, Artist> artistsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在album detail page
  /// 200*200
  Future<ImageProvider?> get cover => works.first.mediumCover;

  Album({required this.name});
}
