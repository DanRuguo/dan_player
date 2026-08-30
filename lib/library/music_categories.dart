import 'dart:convert';

import 'package:dan_player/app_paths.dart' as app_paths;
import 'package:dan_player/app_settings.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/statistics/library_statistics.dart';
import 'package:path/path.dart' as path;

enum MusicCategoryKind {
  artist('艺术家', '位艺术家', '未知艺术家'),
  album('专辑', '张专辑', '未知专辑'),
  composer('作曲家', '位作曲家', '未知作曲家'),
  language('语言', '种语言', '未识别'),
  format('文件格式', '种格式', '未知格式'),
  source('来源', '种来源', '未知来源');

  const MusicCategoryKind(this.label, this.countLabel, this.unknownLabel);
  final String label;
  final String countLabel;
  final String unknownLabel;

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
    required Iterable<Audio> audios,
    required Map<ClassificationEvidence, int> evidenceCounts,
  })  : audios = List.unmodifiable(audios),
        evidenceCounts = Map.unmodifiable(evidenceCounts);

  final MusicCategoryKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final bool isUnknown;
  final List<Audio> audios;
  final Map<ClassificationEvidence, int> evidenceCounts;

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

class MusicCategories {
  MusicCategories(
    Iterable<Audio> audios, {
    String? artistSplitPattern,
    MusicClassificationSnapshot? classifications,
  }) {
    final separator =
        RegExp(artistSplitPattern ?? AppSettings.instance.artistSplitPattern);
    final building = <MusicCategoryKind, Map<String, _GroupBuilder>>{
      for (final kind in MusicCategoryKind.values) kind: {},
    };
    for (final audio in audios) {
      final classification =
          (classifications ?? const MusicClassificationSnapshot.empty())
              .forAudio(audio);
      for (final kind in MusicCategoryKind.values) {
        if (kind == MusicCategoryKind.album) {
          final name = _tagName(audio.album);
          // Album artist is the release identity, NOT a per-track performer.
          // Without that tag, keep unrelated performers' releases separate.
          final owner = _tagName(audio.albumArtist) ?? _tagName(audio.artist);
          final key = jsonEncode([kind.name, name, owner]);
          building[kind]!
              .putIfAbsent(
                key,
                () => _GroupBuilder(kind, key, name ?? kind.unknownLabel,
                    owner ?? '未知专辑艺术家', name == null),
              )
              .audios
              .add(audio);
        } else if (kind == MusicCategoryKind.artist ||
            kind == MusicCategoryKind.composer) {
          final value = kind == MusicCategoryKind.artist
              ? audio.artist
              : classification.composer.value;
          final names = _personNames(value, separator);
          for (final name in names) {
            final key = jsonEncode([kind.name, name]);
            building[kind]!
                .putIfAbsent(
                  key,
                  () => _GroupBuilder(
                      kind, key, name ?? kind.unknownLabel, null, name == null),
                )
                .add(audio,
                    evidence: kind == MusicCategoryKind.composer
                        ? classification.composer.evidence
                        : null);
          }
        } else {
          final (identity, title, unknown) = switch (kind) {
            MusicCategoryKind.language =>
              _languageIdentity(classification.language),
            MusicCategoryKind.format => _formatIdentity(audio),
            MusicCategoryKind.source => (
                audio.isOnline ? 'online' : 'local',
                audio.isOnline ? '联网' : '本地',
                false,
              ),
            _ => throw StateError('Unexpected person or album category'),
          };
          final key = jsonEncode([kind.name, identity]);
          building[kind]!
              .putIfAbsent(
                key,
                () => _GroupBuilder(kind, key, title, null, unknown),
              )
              .add(audio,
                  evidence: kind == MusicCategoryKind.language
                      ? classification.languageEvidence
                      : null);
        }
      }
    }
    for (final kind in MusicCategoryKind.values) {
      final result = building[kind]!
          .values
          .map((item) => item.freeze())
          .toList()
        ..sort((a, b) {
          if (a.isUnknown != b.isUnknown) return a.isUnknown ? 1 : -1;
          final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return title != 0 ? title : a.id.compareTo(b.id);
        });
      _groups[kind] = List.unmodifiable(result);
    }
  }

  final _groups = <MusicCategoryKind, List<MusicCategoryGroup>>{};
  static final _paths = path.Context(style: path.Style.windows);
  static final _formatExtension = RegExp(r'^[A-Z0-9]{1,12}$');

  static (String, String, bool) _languageIdentity(
      SongLanguageClassification result) {
    final language = result.language;
    return (language.name, language.label, language == SongLanguage.unknown);
  }

  static String? _formatName(Audio audio) {
    // A provider identifier/stream URL does not establish the fetched container.
    if (audio.isOnline) return null;
    final extension = _paths.extension(audio.path);
    if (extension.length < 2) return null;
    final name = extension.substring(1).toUpperCase();
    return _formatExtension.hasMatch(name) ? name : null;
  }

  static (String?, String, bool) _formatIdentity(Audio audio) {
    final format = _formatName(audio);
    return (
      format,
      format ?? MusicCategoryKind.format.unknownLabel,
      format == null
    );
  }

  List<MusicCategoryGroup> groups(MusicCategoryKind kind) => _groups[kind]!;

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

class _GroupBuilder {
  _GroupBuilder(this.kind, this.id, this.title, this.subtitle, this.isUnknown);
  final MusicCategoryKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final bool isUnknown;
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
        audios: audios,
        evidenceCounts: evidenceCounts,
      );
}
