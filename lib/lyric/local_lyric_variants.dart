import 'dart:io';

import 'package:dan_player/library/audio_library.dart';
import 'package:path/path.dart' as p;

const localLyricSidecarExtensions = [
  '.qrc',
  '.yrc',
  '.krc',
  '.ttml',
  '.elrc',
  '.lrc'
];
final _languageTagPattern = RegExp(r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$');

/// A filename declares a language, not the role of that language in a song.
/// A variant is selected as a complete main lyric; it is never merged with a
/// different language or chosen from the application's display language.
class LocalLyricVariant {
  const LocalLyricVariant._(this.path, this.languageTag, this.extension);

  final String path;
  final String languageTag;
  final String extension;
  String get filename => p.basename(path);

  static LocalLyricVariant? fromPath(Audio audio, String filename) {
    if (!audio.isLocal || audio.isCueTrack) return null;
    final audioPath = p.normalize(p.absolute(audio.localFilePath));
    final candidatePath = p.normalize(p.absolute(filename));
    if (!p.equals(p.dirname(audioPath), p.dirname(candidatePath))) {
      return null;
    }
    final stem = p.basenameWithoutExtension(audioPath);
    final name = p.basename(candidatePath);
    final extension = p.extension(name).toLowerCase();
    if (!localLyricSidecarExtensions.contains(extension)) return null;
    final prefix = '$stem.';
    final matchingName = Platform.isWindows ? name.toLowerCase() : name;
    final matchingPrefix = Platform.isWindows ? prefix.toLowerCase() : prefix;
    if (!matchingName.startsWith(matchingPrefix) ||
        name.length <= prefix.length + extension.length) {
      return null;
    }
    final tag = name.substring(prefix.length, name.length - extension.length);
    // Common BCP-47 language/script/region/variant tags. Companion roles and
    // arbitrary suffixes (translation, romanization, live, etc.) are excluded.
    if (!_languageTagPattern.hasMatch(tag)) {
      return null;
    }
    return LocalLyricVariant._(candidatePath, tag, extension);
  }
}

class LocalLyricVariants {
  const LocalLyricVariants(this.candidates, {this.truncated = false});
  final List<LocalLyricVariant> candidates;
  final bool truncated;
}

/// Scans only on a user source-selection/refresh action, never on a clock tick.
/// Links are not followed and both directory work and retained items are capped.
Future<LocalLyricVariants> findLocalLyricVariants(Audio audio,
    {bool Function()? stillCurrent}) async {
  bool active() => stillCurrent?.call() ?? true;
  if (!audio.isLocal || audio.isCueTrack || !active()) {
    return const LocalLyricVariants([]);
  }
  final candidates = <LocalLyricVariant>[];
  var scanned = 0;
  var truncated = false;
  await for (final entity
      in Directory(p.dirname(audio.localFilePath)).list(followLinks: false)) {
    if (!active()) return const LocalLyricVariants([]);
    if (++scanned > 4096) {
      truncated = true;
      break;
    }
    if (entity is! File) continue;
    final candidate = LocalLyricVariant.fromPath(audio, entity.path);
    if (candidate == null) continue;
    if (candidates.length == 32) {
      truncated = true;
      break;
    }
    candidates.add(candidate);
  }
  candidates.sort((a, b) {
    final language =
        a.languageTag.toLowerCase().compareTo(b.languageTag.toLowerCase());
    if (language != 0) return language;
    final format = localLyricSidecarExtensions
        .indexOf(a.extension)
        .compareTo(localLyricSidecarExtensions.indexOf(b.extension));
    return format != 0 ? format : a.filename.compareTo(b.filename);
  });
  return active()
      ? LocalLyricVariants(List.unmodifiable(candidates), truncated: truncated)
      : const LocalLyricVariants([]);
}
