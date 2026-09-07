import 'dart:convert';

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/audio_sort.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:path/path.dart' as path;

enum MusicCategoryKind {
  artist('艺术家', '位艺术家', '未知艺术家'),
  album('专辑', '张专辑', '未知专辑'),
  bitrate('码率', '个码率区间', '未知码率'),
  duration('时长', '个时长区间', '未知时长'),
  language('语言', '种语言', '未识别'),
  format('文件格式', '种格式', '未知格式'),
  source('来源', '种来源', '未知来源'),

  /// Legacy deep-link compatibility only. It is intentionally absent from
  /// [browsableValues] and cannot be selected from the category page any more.
  composer('作曲家', '位作曲家', '未知作曲家');

  const MusicCategoryKind(this.label, this.countLabel, this.unknownLabel);
  final String label;
  final String countLabel;
  final String unknownLabel;

  /// Public category rail order. Keep this explicit so adding a compatibility
  /// projection cannot accidentally expose it in the interface.
  static const browsableValues = [
    artist,
    album,
    bitrate,
    duration,
    language,
    format,
    source,
  ];

  static MusicCategoryKind fromName(String? name) =>
      values.where((kind) => kind.name == name).firstOrNull ?? artist;
}

/// An immutable browsing projection. The Audio references are the originals;
/// grouping and display sorting never rename files or rewrite their tags.
class MusicCategoryGroup {
  MusicCategoryGroup._({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isUnknown,
    required this.sortOrder,
    required Iterable<Audio> audios,
    required Map<ClassificationEvidence, int> evidenceCounts,
  })  : audios = List.unmodifiable(audios),
        evidenceCounts = Map.unmodifiable(evidenceCounts);

  final MusicCategoryKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final bool isUnknown;
  final int sortOrder;
  final List<Audio> audios;
  final Map<ClassificationEvidence, int> evidenceCounts;

  /// Match the first row on a freshly opened detail page. Albums open in track
  /// order; other categories retain library order. Do not mutate membership.
  late final Audio? coverAudio = audios.isEmpty
      ? null
      : kind == MusicCategoryKind.album
          ? audios.reduce((first, next) =>
              compareAudioSort(next, first, AudioSortField.track) < 0
                  ? next
                  : first)
          : audios.first;

  /// Stable persistence identity. It intentionally excludes translated labels,
  /// cover/song order and every presentation-only field.
  String get persistenceKey => categoryCoverPersistenceKey(kind, id);

  String get evidenceSummary => [
        for (final evidence in ClassificationEvidence.values)
          if ((evidenceCounts[evidence] ?? 0) > 0)
            '${evidence.label} ${evidenceCounts[evidence]}',
      ].join(' · ');

  int get localCount => audios.where((audio) => audio.isLocal).length;
  int get onlineCount => audios.length - localCount;
  String get sourceSummary => [
        if (localCount > 0) '本地 $localCount',
        if (onlineCount > 0) '联网 $onlineCount',
      ].join(' · ');

  String get location => Uri(
        path: app_paths.CATEGORY_DETAIL_PAGE,
        queryParameters: {'by': kind.name, 'group': id},
      ).toString();

  bool matches(String query) {
    final search = query.trim().toLowerCase();
    return search.isEmpty ||
        title.toLowerCase().contains(search) ||
        (subtitle?.toLowerCase().contains(search) ?? false);
  }
}

String categoryCoverPersistenceKey(MusicCategoryKind kind, String groupId) =>
    jsonEncode(<Object>[1, kind.name, groupId]);

class MusicCategories {
  MusicCategories(
    Iterable<Audio> audios, {
    String? artistSplitPattern,
    MusicClassificationSnapshot? classifications,
  })  : _audios = List.unmodifiable(audios),
        _separator = RegExp(
            artistSplitPattern ?? AppSettings.instance.artistSplitPattern),
        _classifications =
            classifications ?? const MusicClassificationSnapshot.empty();

  final List<Audio> _audios;
  final RegExp _separator;
  final MusicClassificationSnapshot _classifications;
  final _groups = <MusicCategoryKind, List<MusicCategoryGroup>>{};
  static final _paths = path.Context(style: path.Style.windows);
  static final _formatExtension = RegExp(r'^[A-Z0-9]{1,12}$');

  static (String, String, bool, int) _languageIdentity(
      SongLanguageClassification result) {
    final language = result.language;
    return (
      language.name,
      language.label,
      language == SongLanguage.unknown,
      language.index,
    );
  }

  static (String, String, bool, int) _bitrateIdentity(int? bitrate) {
    if (bitrate == null || bitrate <= 0) {
      return ('unknown', MusicCategoryKind.bitrate.unknownLabel, true, 5);
    }
    if (bitrate <= 128) return ('le128', '128 kbps 及以下', false, 0);
    if (bitrate <= 192) return ('129-192', '129–192 kbps', false, 1);
    if (bitrate <= 256) return ('193-256', '193–256 kbps', false, 2);
    if (bitrate <= 320) return ('257-320', '257–320 kbps', false, 3);
    return ('gt320', '高于 320 kbps', false, 4);
  }

  static (String, String, bool, int) _durationIdentity(int duration) {
    if (duration <= 0) {
      return ('unknown', MusicCategoryKind.duration.unknownLabel, true, 5);
    }
    if (duration < 2 * 60) return ('lt2m', '少于 2 分钟', false, 0);
    if (duration < 5 * 60) return ('2-4m', '2–4 分钟', false, 1);
    if (duration < 10 * 60) return ('5-9m', '5–9 分钟', false, 2);
    if (duration < 30 * 60) return ('10-29m', '10–29 分钟', false, 3);
    return ('ge30m', '30 分钟及以上', false, 4);
  }

  static String? _formatName(Audio audio) {
    // A provider identifier/stream URL does not establish the fetched container.
    if (audio.isOnline) return null;
    final extension = _paths.extension(audio.path);
    if (extension.length < 2) return null;
    final name = extension.substring(1).toUpperCase();
    return _formatExtension.hasMatch(name) ? name : null;
  }

  static (String?, String, bool, int) _formatIdentity(Audio audio) {
    final format = _formatName(audio);
    return (
      format,
      format ?? MusicCategoryKind.format.unknownLabel,
      format == null,
      0,
    );
  }

  /// Build only the requested projection. Opening one category therefore does
  /// not pay for every other grouping (including the hidden legacy composer).
  List<MusicCategoryGroup> groups(MusicCategoryKind kind) =>
      _groups.putIfAbsent(kind, () => _buildGroups(kind));

  List<MusicCategoryGroup> _buildGroups(MusicCategoryKind kind) {
    final building = <String, _GroupBuilder>{};
    for (final audio in _audios) {
      if (kind == MusicCategoryKind.album) {
        final name = _tagName(audio.album);
        // Album artist is the release identity, NOT a per-track performer.
        // Without that tag, keep unrelated performers' releases separate.
        final owner = _tagName(audio.albumArtist) ?? _tagName(audio.artist);
        final key = jsonEncode([kind.name, name, owner]);
        building
            .putIfAbsent(
              key,
              () => _GroupBuilder(kind, key, name ?? kind.unknownLabel,
                  owner ?? '未知专辑艺术家', name == null),
            )
            .audios
            .add(audio);
        continue;
      }

      if (kind == MusicCategoryKind.artist ||
          kind == MusicCategoryKind.composer) {
        final classification = kind == MusicCategoryKind.composer
            ? _classifications.forAudio(audio)
            : null;
        final value = kind == MusicCategoryKind.artist
            ? audio.artist
            : classification!.composer.value;
        final names = _personNames(value, _separator);
        for (final name in names) {
          final key = jsonEncode([kind.name, name]);
          building
              .putIfAbsent(
                key,
                () => _GroupBuilder(
                    kind, key, name ?? kind.unknownLabel, null, name == null),
              )
              .add(audio,
                  evidence: kind == MusicCategoryKind.composer
                      ? classification!.composer.evidence
                      : null);
        }
        continue;
      }

      final language = kind == MusicCategoryKind.language
          ? _classifications.forAudio(audio)
          : null;
      final (identity, title, unknown, sortOrder) = switch (kind) {
        MusicCategoryKind.bitrate => _bitrateIdentity(audio.bitrate),
        MusicCategoryKind.duration => _durationIdentity(audio.duration),
        MusicCategoryKind.language => _languageIdentity(language!.language),
        MusicCategoryKind.format => _formatIdentity(audio),
        MusicCategoryKind.source => (
            audio.isOnline ? 'online' : 'local',
            audio.isOnline ? '联网' : '本地',
            false,
            0,
          ),
        _ => throw StateError('Unexpected person or album category'),
      };
      final key = jsonEncode([kind.name, identity]);
      building
          .putIfAbsent(
            key,
            () => _GroupBuilder(kind, key, title, null, unknown, sortOrder),
          )
          .add(audio,
              evidence: kind == MusicCategoryKind.language
                  ? language!.languageEvidence
                  : null);
    }

    final result = building.values.map((item) => item.freeze()).toList()
      ..sort((a, b) {
        if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
        final order = a.sortOrder.compareTo(b.sortOrder);
        if (order != 0) return order;
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.id.compareTo(b.id);
      });
    return List.unmodifiable(result);
  }

  MusicCategoryGroup? find(MusicCategoryKind kind, String id) =>
      groups(kind).where((group) => group.id == id).firstOrNull;

  /// Used by old song menus too, so their album links cannot fall back to the
  /// legacy album-title-only map. Includes an unindexed source when necessary.
  static MusicCategoryGroup albumGroupFor(
      Audio audio, Iterable<Audio> library) {
    final name = _tagName(audio.album);
    final owner = _tagName(audio.albumArtist) ?? _tagName(audio.artist);
    final tracks = library
        .where((item) =>
            _tagName(item.album) == name &&
            (_tagName(item.albumArtist) ?? _tagName(item.artist)) == owner)
        .toList();
    if (!tracks.any((item) => item.path == audio.path)) tracks.add(audio);
    return MusicCategories(tracks).groups(MusicCategoryKind.album).single;
  }

  static String? _tagName(String? value) {
    final name = value?.trim();
    if (name == null || name.isEmpty || name.toUpperCase() == 'UNKNOWN') {
      return null;
    }
    return name;
  }

  static List<String?> _personNames(String? value, Pattern separator) {
    final names = <String>{};
    for (final part in value?.split(separator) ?? const <String>[]) {
      final name = _tagName(part);
      if (name != null) names.add(name);
    }
    // Respect the same user-configured separator as the artist field. In
    // particular, do not invent a comma split for names such as "Sakamoto, R".
    return names.isEmpty ? const [null] : names.toList();
  }
}

/// Shared artist/album projection for the live library.
///
/// Player-side duration corrections mutate [Audio.duration] and publish the
/// general library revision, but they cannot change artist or release
/// membership. Keeping this snapshot on [AudioLibrary.classificationRevision]
/// lets visible song rows repaint their corrected duration without making
/// every artist, album and playlist surface regroup the complete library.
class LibraryMusicCategories {
  LibraryMusicCategories._();

  static int _revision = -1;
  static MusicCategories? _snapshot;

  static MusicCategories get _current {
    final revision = AudioLibrary.classificationRevision;
    if (_snapshot == null || _revision != revision) {
      _revision = revision;
      _snapshot = MusicCategories(AudioLibrary.instance.audioCollection);
    }
    return _snapshot!;
  }

  static List<MusicCategoryGroup> groups(MusicCategoryKind kind) {
    if (kind != MusicCategoryKind.artist && kind != MusicCategoryKind.album) {
      throw ArgumentError.value(
          kind, 'kind', 'Only artist and album groups are shared');
    }
    return _current.groups(kind);
  }

  static MusicCategoryGroup? find(MusicCategoryKind kind, String id) =>
      groups(kind).where((group) => group.id == id).firstOrNull;

  static int get albumCount => groups(MusicCategoryKind.album).length;
}

class _GroupBuilder {
  _GroupBuilder(this.kind, this.id, this.title, this.subtitle, this.isUnknown,
      [this.sortOrder = 0]);
  final MusicCategoryKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final bool isUnknown;
  final int sortOrder;
  final audios = <Audio>[];
  final evidenceCounts = <ClassificationEvidence, int>{};

  void add(Audio audio, {ClassificationEvidence? evidence}) {
    audios.add(audio);
    if (evidence != null) {
      evidenceCounts.update(evidence, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  MusicCategoryGroup freeze() => MusicCategoryGroup._(
        kind: kind,
        id: id,
        title: title,
        subtitle: subtitle,
        isUnknown: isUnknown,
        sortOrder: sortOrder,
        audios: audios,
        evidenceCounts: evidenceCounts,
      );
}
