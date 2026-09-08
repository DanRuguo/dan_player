import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/artwork_image_provider.dart';
import 'package:dan_player/library/artwork_size.dart';
import 'package:dan_player/library/cover_cache.dart';
import 'package:dan_player/library/album_identity.dart';
import 'package:dan_player/library/cue_track.dart';
import 'package:dan_player/library/track_identity.dart';
import 'package:dan_player/online/custom_music_source_profile.dart';
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

  /// Changes only when searchable library contents or metadata change.
  /// Playback-side duration corrections deliberately do not invalidate the
  /// text index.
  static int searchRevision = 0;

  /// Changes only when library contents or classification metadata change.
  /// Duration-only updates can rebuild duration groups without rereading
  /// language/composer evidence from lyrics.
  static int classificationRevision = 0;

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
      await TrackIdentityRegistry.instance.initialize();
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

      final roots = indexJson['roots'];
      if (roots != null &&
          (roots is! List || roots.any((root) => root is! String))) {
        throw const FormatException('Audio index roots must be strings');
      }
      for (final folder in folders) {
        for (final audio in folder.audios) {
          audio.stableTrackId;
        }
      }
      // Publish the new library only after the durable identities exist.
      await TrackIdentityRegistry.instance.flush();
      // Online add/remove can publish while identity persistence is awaiting
      // I/O. Snapshot it in the same synchronous turn as replacing the library.
      final onlineAudios = List<Audio>.from(instance.onlineAudioCollection);
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
    searchRevision++;
    classificationRevision++;
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

      // Browsing, search and legacy Album extras share one release identity.
      final identity = audio.albumIdentity;
      albumCollection
          .putIfAbsent(
              identity.id,
              () => Album(
                    name: identity.displayTitle,
                    groupId: identity.id,
                    albumArtist: identity.displayOwner,
                  ))
          .works
          .add(audio);
    }

    /// 将艺术家和专辑链接起来
    for (Artist artist in artistCollection.values) {
      for (Audio audio in artist.works) {
        artist.albumsMap.putIfAbsent(
          audio.albumIdentity.id,
          () => albumCollection[audio.albumIdentity.id]!,
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

  /// Duration does not affect artist/album membership. Publish a lightweight
  /// revision so visible lists and duration sorts refresh without rebuilding
  /// every derived collection after a player-side correction.
  void publishDurationChanges() {
    revision++;
    changes.value = revision;
  }

  void publishArtworkChanges() {
    revision++;
    changes.value = revision;
  }

  void replaceOnlineAudios(Iterable<Audio> audios) {
    onlineAudioCollection = List<Audio>.from(audios);
    rebuildDerivedCollections();
  }

  /// Remove a local file from its owning scan folder and publish a complete
  /// derived-collection rebuild. Online library entries are never considered.
  /// Returns the number of stale/index occurrences removed.
  int removeLocalAudio(String audioPath) {
    var removed = 0;
    for (final folder in folders) {
      final before = folder.audios.length;
      folder.audios.removeWhere(
          (audio) => audio.isLocal && path_util.equals(audio.path, audioPath));
      removed += before - folder.audios.length;
    }
    if (removed > 0) rebuildDerivedCollections();
    return removed;
  }

  Future<void> saveIndex() async {
    try {
      // Materialize an immutable, sendable snapshot before crossing an async
      // boundary. JSON encoding a large library can then run without blocking
      // Flutter's UI isolate or observing a half-mutated collection.
      final snapshot = <String, Object?>{
        "version": 113,
        "roots": List<String>.of(scanRoots),
        "folders": [for (final folder in folders) folder.toMap()],
      };
      await TrackIdentityRegistry.instance.flush();
      final supportPath = (await getAppDataDir()).path;
      final indexPath = "$supportPath\\index.json";
      final contents = await Isolate.run(() => json.encode(snapshot));
      await _writeIndexAtomically(
        File(indexPath),
        contents,
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
  final String? _identityHint;
  String? _stableTrackId;

  /// Persistent local identity; editable metadata and locations are not IDs.
  /// Online tracks retain their provider-scoped URI identity.
  String get stableTrackId => isOnline
      ? path
      : _stableTrackId ??= TrackIdentityRegistry.instance.idFor(
          path,
          cue: cueTrack,
          preferredId: _identityHint,
        );
  String get trackId => stableTrackId;

  String title;

  /// 从音乐标签中读取的艺术家字符串，可能包含多个艺术家，以“、”，“/”等分隔。
  String artist;

  /// 分割[artist]得到的结果
  List<String> splitedArtists;

  String album;

  AlbumIdentity get albumIdentity => AlbumIdentity(album, albumArtist, artist);

  /// Explicit source tags; never inferred from the performer or file name.
  String? composer;
  String? albumArtist;

  /// Old indexes without these tags remain pending for incremental backfill.
  int classificationVersion;

  /// 0: 没有track
  int track;

  /// audio's duration in secs
  int duration;

  /// Version of the reader that verified [duration]. Legacy indexes use zero
  /// so the next incremental refresh can backfill them once.
  int durationVersion;

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

  final CueTrackReference? cueTrack;
  bool get isCueTrack => cueTrack != null;
  String get localFilePath => cueTrack?.sourcePath ?? path;
  bool get canEditLocalFile => isLocal && !isCueTrack;

  /// Absolute file path or the stable identity of an online/CUE track.
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

  /// Provider-declared availability for this exact result. A null value means
  /// the source did not supply a per-track answer (including legacy records).
  final bool? onlinePlayable;

  /// Optional per-track availability reported by the provider. An explicit
  /// false blocks downloading; null means the endpoint has to be tried.
  final bool? onlineDownloadAllowed;

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
    this.cueTrack,
    this.durationVersion = 1,
    this.onlineProvider,
    this.onlineId,
    this.onlineMediaId,
    this.onlineNumericId,
    this.artworkUrl,
    this.onlinePlayable,
    this.onlineDownloadAllowed,
    String? stableTrackId,
  })  : _identityHint = stableTrackId,
        splitedArtists = artist.split(
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
    bool? playable,
    bool? downloadAllowed,
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
      onlinePlayable: playable,
      onlineDownloadAllowed: downloadAllowed,
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
      playable: map["playable"] is bool ? map["playable"] as bool : null,
      downloadAllowed: map["downloadAllowed"] is bool
          ? map["downloadAllowed"] as bool
          : null,
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
  String get sourceLabel {
    final provider = onlineProvider;
    if (provider == null) return "本地";
    if (provider == "qq") return "QQ音乐";
    if (provider == "netease") return "网易云音乐";
    final profileId = CustomMusicSourceProfile.profileIdFromProvider(provider);
    if (profileId != null) {
      for (final profile in AppSettings.instance.customMusicSources.value) {
        if (profile.id == profileId) return profile.name;
      }
      return "自定义歌源";
    }
    return provider;
  }

  /// Whether a persisted remote artwork URL may be contacted right now.
  ///
  /// Built-in source switches intentionally affect new searches only, so
  /// their saved tracks keep working. Custom source switches are strict: a
  /// disabled, removed or currently unusable profile must not leak a request
  /// to the previously saved artwork host.
  bool get canFetchRemoteArtwork {
    if (!isOnline) return false;
    final provider = onlineProvider;
    if (provider == null || !provider.startsWith('custom:')) return true;
    return _currentCustomArtworkProfile != null;
  }

  CustomMusicSourceProfile? get _currentCustomArtworkProfile {
    final provider = onlineProvider;
    final profileId = CustomMusicSourceProfile.profileIdFromProvider(provider);
    if (profileId == null) return null;
    for (final profile in AppSettings.instance.customMusicSources.value) {
      if (profile.id != profileId) continue;
      return profile.enabled &&
              profile.authentication == null &&
              profile.capabilities.contains(CustomMusicSourceCapability.cover)
          ? profile
          : null;
    }
    return null;
  }

  bool _allowsRemoteArtworkUri(
    Uri artwork, {
    CustomMusicSourceProfile? customProfile,
  }) {
    final provider = onlineProvider;
    final isCustomProvider = provider?.startsWith('custom:') == true;
    if (isCustomProvider && customProfile?.providerId != provider) return false;
    if (artwork.scheme == 'https') return true;
    if (artwork.scheme != 'http') return false;
    if (!isCustomProvider) return true;
    if (customProfile == null) return false;
    final base = Uri.tryParse(customProfile.baseUrl);
    return base != null &&
        base.scheme == 'http' &&
        base.host.toLowerCase() == artwork.host.toLowerCase() &&
        base.port == artwork.port;
  }

  String get fileNameTitle =>
      isOnline || isCueTrack ? title : path_util.basenameWithoutExtension(path);

  String get displayTitle {
    if (isOnline || isCueTrack) return title;
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
    final previousPath = path;
    // A stale editor and a fresh scan may be references to the same explicitly
    // renamed file; the first reference can already have moved the registry.
    _stableTrackId ??= TrackIdentityRegistry.instance.resolvePath(previousPath);
    stableTrackId;
    if (newPath != previousPath) {
      TrackIdentityRegistry.instance.remapPaths((candidate) =>
          TrackIdentityRegistry.normalizePath(candidate) ==
                  TrackIdentityRegistry.normalizePath(previousPath)
              ? newPath
              : candidate);
    }
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
    final cue = map['cue_track'] is Map
        ? CueTrackReference.fromMap(map['cue_track'] as Map)
        : null;
    if (audioPath.startsWith('cue:') != (cue != null)) {
      throw const FormatException('CUE 分轨引用无效。');
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
      cueTrack: cue,
      durationVersion: (map['duration_version'] as num?)?.toInt() ?? 0,
      stableTrackId: map['track_id'] is String ? map['track_id'] : null,
    );
  }

  Map toMap() => {
        "track_id": stableTrackId,
        "title": title,
        "artist": artist,
        "album": album,
        "composer": composer,
        "album_artist": albumArtist,
        "classification_version": classificationVersion,
        "track": track,
        "duration": duration,
        "duration_version": durationVersion,
        "bitrate": bitrate,
        "sample_rate": sampleRate,
        "language": language,
        "file_size": fileSizeBytes,
        "modified_ns": modifiedNanos,
        "metadata_pending": metadataReadPending,
        "path": path,
        if (cueTrack != null) 'cue_track': cueTrack!.toMap(),
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
        if (onlinePlayable != null) "playable": onlinePlayable,
        if (onlineDownloadAllowed != null)
          "downloadAllowed": onlineDownloadAllowed,
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
    final isCustomProvider = onlineProvider?.startsWith('custom:') == true;
    final customProfile =
        isCustomProvider ? _currentCustomArtworkProfile : null;
    final mayFetchRemoteArtwork =
        isOnline && (!isCustomProvider || customProfile != null);
    if (mayFetchRemoteArtwork &&
        remoteArtwork != null &&
        remoteArtwork.isNotEmpty) {
      final uri = Uri.tryParse(remoteArtwork);
      if (uri != null &&
          _allowsRemoteArtworkUri(uri, customProfile: customProfile)) {
        final sizedUri = artworkUriForSize(uri, size, provider: onlineProvider);
        if (customProfile != null) {
          return ArtworkImageProvider(
            CustomOnlineArtworkImageProvider(
              sizedUri.toString(),
              expectedProfile: customProfile,
            ),
            size,
          );
        }
        return ArtworkImageProvider(NetworkImage(sizedUri.toString()), size);
      }
    }
    if (isOnline) return null;
    // Capture mutable metadata now: an edit must not make a queued request
    // read a different file and cache it under the previous file's identity.
    final requestedPath = localFilePath;
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
  final String? groupId;
  final String? albumArtist;

  /// 参与的艺术家
  Map<String, Artist> artistsMap = {};

  /// 作品
  List<Audio> works = [];

  /// 只能用在album detail page
  /// 200*200
  Future<ImageProvider?> get cover => works.first.mediumCover;

  /// Nullable identity preserves old route payloads; ambiguous legacy works
  /// are explicitly disambiguated by AlbumDetailPage.
  Album({required this.name, this.groupId, this.albumArtist});
}
