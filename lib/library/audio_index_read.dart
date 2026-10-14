import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

const audioIndexSupportedVersion = 113;
const audioIndexInlineCharacterLimit = 1024 * 1024;

/// Keep small indexes on the existing cheap path. Large JSON shaping belongs
/// off the UI isolate; identity and library relation publication stay with it.
Future<Map> decodeAudioIndex(String contents) =>
    contents.length < audioIndexInlineCharacterLimit
        ? Future.sync(() => _decode(contents))
        : Isolate.run(() => _decode(contents), debugName: 'audio-index-decode');

Map _decode(String contents) {
  final decoded = json.decode(contents);
  if (decoded is! Map) {
    throw const FormatException('Audio index root must be an object');
  }
  validateAudioIndexConsumerShape(decoded);
  return decoded;
}

void validateAudioIndexConsumerShape(Map index) {
  final version = index['version'];
  // Future primary schemas must not silently downgrade to an older backup.
  if (version is int && version > audioIndexSupportedVersion) return;
  if (index['folders'] is! List) {
    throw const FormatException('Audio index folders must be a list');
  }
  final roots = index['roots'];
  if (roots != null &&
      (roots is! List || roots.any((root) => root is! String))) {
    throw const FormatException('Audio index roots must be strings');
  }
}

/// Every candidate is decoded/validated independently. A bad primary still
/// tries the backup; the caller retains logging and durable recovery policy.
Future<({Map index, bool recovered})> readAudioIndex(File primary) async {
  Object? targetError;
  final backup = File('${primary.path}.bak');
  for (final candidate in [primary, backup]) {
    try {
      if (!await candidate.exists()) continue;
      final index = await decodeAudioIndex(await candidate.readAsString());
      return (index: index, recovered: candidate.path == backup.path);
    } catch (error) {
      targetError ??= error;
    }
  }
  throw targetError ?? const FormatException('Audio index is unavailable');
}
