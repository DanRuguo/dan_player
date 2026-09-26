import 'package:dan_player/library/personal_library.dart';
import 'package:dan_player/library/audio_library.dart';
import 'package:dan_player/library/album_identity.dart';
import 'package:path/path.dart' as p;

enum SmartField {
  ratingAtLeast,
  personalTag,
  addedAfter,
  addedBefore,
  playlist,
  titleContains,
  artistContains,
  albumContains,
  folderWithin,
  formatIs,
  durationAtLeast,
  durationAtMost,
  ratingAtMost,
  unrated,
  playCountAtLeast,
  playCountAtMost,
  bitrateAtLeast,
  sampleRateAtLeast,
  composerContains,
  albumArtistContains,
  languageIs,
  fileNameContains,
  fileSizeAtLeast,
  fileSizeAtMost,
  bitrateAtMost,
  sampleRateAtMost,
  trackAtLeast,
  trackAtMost,
  missingComposer,
  missingAlbumArtist,
  missingLanguage,
  missingAlbum,
  missingArtist,
  untagged,
  cueTrack,
  metadataPending,
}

enum RuleTruth { yes, no, unknown }

const smartBooleanFields = {
  SmartField.unrated,
  SmartField.missingComposer,
  SmartField.missingAlbumArtist,
  SmartField.missingLanguage,
  SmartField.missingAlbum,
  SmartField.missingArtist,
  SmartField.untagged,
  SmartField.cueTrack,
  SmartField.metadataPending,
};

class SmartCondition {
  const SmartCondition.group(this.children, {this.any = false})
      : field = null,
        value = '',
        exclude = false;
  const SmartCondition.term(this.field, this.value, {this.exclude = false})
      : children = const [],
        any = false;
  final SmartField? field;
  final String value;
  final bool any, exclude;
  final List<SmartCondition> children;
  bool get isGroup => field == null;
  bool get usesPersonalData => isGroup
      ? children.any((child) => child.usesPersonalData)
      : const {
          SmartField.ratingAtLeast,
          SmartField.ratingAtMost,
          SmartField.unrated,
          SmartField.personalTag,
          SmartField.addedAfter,
          SmartField.addedBefore,
          SmartField.untagged,
        }.contains(field);
  bool get usesPlaybackHistory => isGroup
      ? children.any((child) => child.usesPlaybackHistory)
      : field == SmartField.playCountAtLeast ||
          field == SmartField.playCountAtMost;
  int get leaves => isGroup ? children.fold(0, (n, c) => n + c.leaves) : 1;
  Map<String, Object?> toJson() => isGroup
      ? {
          'group': any ? 'any' : 'all',
          'children': children.map((c) => c.toJson()).toList()
        }
      : {'field': field!.name, 'value': value, 'exclude': exclude};
  static SmartCondition fromJson(Object? raw, [int depth = 0]) {
    if (raw is! Map) throw const FormatException('Invalid condition');
    if (raw.containsKey('group')) {
      if (depth >= 2 ||
          !['any', 'all'].contains(raw['group']) ||
          raw['children'] is! List ||
          (raw['children'] as List).length > 32) {
        throw const FormatException('Invalid condition group');
      }
      final result = SmartCondition.group(
          (raw['children'] as List).map((c) => fromJson(c, depth + 1)).toList(),
          any: raw['group'] == 'any');
      if (result.leaves > 32) {
        throw const FormatException('At most 32 conditions');
      }
      return result;
    }
    final field =
        SmartField.values.where((f) => f.name == raw['field']).firstOrNull;
    final value = raw['value'];
    if (field == null ||
        value is! String ||
        value.trim().isEmpty ||
        value.length > 160 ||
        (raw['exclude'] != null && raw['exclude'] is! bool)) {
      throw const FormatException('Invalid condition value');
    }
    if ((field == SmartField.ratingAtLeast ||
            field == SmartField.ratingAtMost) &&
        !['1', '2', '3', '4', '5'].contains(value)) {
      throw const FormatException('Invalid rating');
    }
    if (smartBooleanFields.contains(field) && value != 'true') {
      throw const FormatException('Invalid boolean condition');
    }
    final numericMaximum = switch (field) {
      SmartField.durationAtLeast || SmartField.durationAtMost => 86400,
      SmartField.playCountAtLeast || SmartField.playCountAtMost => 1000000000,
      SmartField.bitrateAtLeast || SmartField.bitrateAtMost => 100000,
      SmartField.sampleRateAtLeast || SmartField.sampleRateAtMost => 10000000,
      SmartField.trackAtLeast || SmartField.trackAtMost => 100000,
      SmartField.fileSizeAtLeast ||
      SmartField.fileSizeAtMost =>
        1000000000000000,
      _ => null,
    };
    if (numericMaximum != null &&
        (int.tryParse(value) == null ||
            int.parse(value) < 0 ||
            int.parse(value) > numericMaximum)) {
      throw const FormatException('Invalid numeric condition');
    }
    if (field == SmartField.folderWithin &&
        !p.windows.isAbsolute(value.trim())) {
      throw const FormatException('Use an absolute folder path');
    }
    if (field == SmartField.formatIs &&
        !RegExp(r'^\.?[a-zA-Z0-9]{1,16}$').hasMatch(value.trim())) {
      throw const FormatException('Use one file extension');
    }
    if ((field == SmartField.addedAfter || field == SmartField.addedBefore) &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            DateTime.tryParse(value) == null ||
            DateTime.parse(value).toIso8601String().substring(0, 10) !=
                value)) {
      throw const FormatException('Use yyyy-mm-dd');
    }
    return SmartCondition.term(field, value, exclude: raw['exclude'] == true);
  }

  PreparedSmartCondition prepare() => PreparedSmartCondition._(this);

  RuleTruth evaluate(String track, PersonalTrack? data,
          Map<String, Set<String>> memberships,
          {Audio? audio, int? playCount}) =>
      prepare().evaluate(track, data, memberships,
          audio: audio, playCount: playCount);
}

/// Compile scalar rule values once per preview. It retains only rule values,
/// never mutable Audio objects, personal records or a previous library result.
class PreparedSmartCondition {
  PreparedSmartCondition._(SmartCondition condition)
      : _rule = condition,
        _children = condition.children.map((child) => child.prepare()).toList(),
        _number = int.tryParse(condition.value),
        _text = condition.value.trim().toLowerCase(),
        _folder = condition.field == SmartField.folderWithin
            ? p.windows.normalize(condition.value.trim()).toLowerCase()
            : '',
        _date = condition.field == SmartField.addedAfter ||
                condition.field == SmartField.addedBefore
            ? DateTime.parse(condition.value)
            : null;
  final SmartCondition _rule;
  final List<PreparedSmartCondition> _children;
  final int? _number;
  final String _text, _folder;
  final DateTime? _date;

  RuleTruth evaluate(
      String track, PersonalTrack? data, Map<String, Set<String>> memberships,
      {Audio? audio, int? playCount}) {
    if (_rule.isGroup) {
      var unknown = false;
      for (final child in _children) {
        final result = child.evaluate(track, data, memberships,
            audio: audio, playCount: playCount);
        if (_rule.any && result == RuleTruth.yes) return RuleTruth.yes;
        if (!_rule.any && result == RuleTruth.no) return RuleTruth.no;
        unknown |= result == RuleTruth.unknown;
      }
      if (unknown) return RuleTruth.unknown;
      return _rule.any ? RuleTruth.no : RuleTruth.yes;
    }
    final bool? match = switch (_rule.field!) {
      SmartField.ratingAtLeast =>
        data?.rating == null ? null : data!.rating! >= _number!,
      SmartField.ratingAtMost =>
        data?.rating == null ? null : data!.rating! <= _number!,
      SmartField.unrated => data?.rating == null,
      SmartField.personalTag => data?.tags.contains(_rule.value) ?? false,
      SmartField.untagged => data?.tags.isEmpty ?? true,
      SmartField.addedAfter => data?.firstAddedAtUtc == null
          ? null
          : !data!.firstAddedAtUtc!.isBefore(_date!),
      SmartField.addedBefore => data?.firstAddedAtUtc == null
          ? null
          : data!.firstAddedAtUtc!
              .isBefore(_date!.add(const Duration(days: 1))),
      SmartField.playlist => memberships[_rule.value]?.contains(track),
      // Match the loaded title tag, independently of filename display choices.
      SmartField.titleContains => _contains(audio?.title),
      SmartField.artistContains => _contains(audio?.artist),
      SmartField.albumContains => _contains(audio?.album),
      SmartField.composerContains =>
        _contains(normalizedMusicTag(audio?.composer)),
      SmartField.albumArtistContains =>
        _contains(normalizedMusicTag(audio?.albumArtist)),
      SmartField.languageIs => normalizedMusicTag(audio?.language) == null
          ? null
          : audio!.language!.trim().toLowerCase() == _text,
      SmartField.fileNameContains => audio == null || !audio.isLocal
          ? null
          : _contains(p.windows.basename(audio.localFilePath)),
      SmartField.folderWithin =>
        audio == null || !audio.isLocal ? null : _inFolder(audio.localFilePath),
      SmartField.formatIs => audio == null ||
              !audio.isLocal ||
              p.windows.extension(audio.localFilePath).isEmpty
          ? null
          : p.windows
                  .extension(audio.localFilePath)
                  .toLowerCase()
                  .replaceFirst('.', '') ==
              (_text.startsWith('.') ? _text.substring(1) : _text),
      SmartField.durationAtLeast => audio == null || audio.duration <= 0
          ? null
          : audio.duration >= _number!,
      SmartField.durationAtMost => audio == null || audio.duration <= 0
          ? null
          : audio.duration <= _number!,
      SmartField.playCountAtLeast =>
        playCount == null ? null : playCount >= _number!,
      SmartField.playCountAtMost =>
        playCount == null ? null : playCount <= _number!,
      SmartField.bitrateAtLeast =>
        audio?.bitrate == null || audio!.bitrate! <= 0
            ? null
            : audio.bitrate! >= _number!,
      SmartField.bitrateAtMost => _atMost(audio?.bitrate),
      SmartField.sampleRateAtLeast =>
        audio?.sampleRate == null || audio!.sampleRate! <= 0
            ? null
            : audio.sampleRate! >= _number!,
      SmartField.sampleRateAtMost => _atMost(audio?.sampleRate),
      SmartField.fileSizeAtLeast =>
        audio?.fileSizeBytes == null || audio!.fileSizeBytes! < 0
            ? null
            : audio.fileSizeBytes! >= _number!,
      SmartField.fileSizeAtMost =>
        audio?.fileSizeBytes == null || audio!.fileSizeBytes! < 0
            ? null
            : audio.fileSizeBytes! <= _number!,
      SmartField.trackAtLeast =>
        _atLeast(audio?.cueTrack?.number ?? audio?.track),
      SmartField.trackAtMost =>
        _atMost(audio?.cueTrack?.number ?? audio?.track),
      SmartField.missingComposer =>
        _missing(audio, audio?.composer, classification: true),
      SmartField.missingAlbumArtist =>
        _missing(audio, audio?.albumArtist, classification: true),
      SmartField.missingLanguage => _missing(audio, audio?.language),
      SmartField.missingAlbum => _missing(audio, audio?.album),
      SmartField.missingArtist => _missing(audio, audio?.artist),
      SmartField.cueTrack => audio?.isCueTrack,
      SmartField.metadataPending => audio == null
          ? null
          : audio.metadataReadPending || !audio.classificationTagsRead,
    };
    if (match == null) return RuleTruth.unknown;
    return match != _rule.exclude ? RuleTruth.yes : RuleTruth.no;
  }

  bool? _atLeast(int? value) =>
      value == null || value <= 0 ? null : value >= _number!;
  bool? _atMost(int? value) =>
      value == null || value <= 0 ? null : value <= _number!;
  bool? _missing(Audio? audio, String? text, {bool classification = false}) =>
      audio == null ||
              audio.metadataReadPending ||
              (classification && !audio.classificationTagsRead)
          ? null
          : normalizedMusicTag(text) == null;
  bool? _contains(String? text) => text == null || text.trim().isEmpty
      ? null
      : text.toLowerCase().contains(_text);

  bool _inFolder(String file) {
    final directory =
        p.windows.normalize(p.windows.dirname(file)).toLowerCase();
    return p.windows.equals(directory, _folder) ||
        p.windows.isWithin(_folder, directory);
  }
}
