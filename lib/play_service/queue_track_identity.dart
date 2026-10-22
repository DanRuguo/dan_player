import 'package:dan_player/library/audio_library.dart';
import 'package:path/path.dart' as p;

/// Each queue slot owns an identity independent of its track, path and index.
/// Even the same Audio object inserted twice receives two distinct tokens.
class QueueOccurrence<T> {
  QueueOccurrence(this.item) : id = ++_nextId;
  const QueueOccurrence._(this.id, this.item);
  static int _nextId = 0;
  final int id;
  final T item;
  QueueOccurrence<T> withItem(T value) => QueueOccurrence._(id, value);
  @override
  bool operator ==(Object other) =>
      other is QueueOccurrence<T> && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Metadata-only identity: never resolves symlinks, scans or opens music files.
/// CUE slices retain their own identity even when sharing a physical source.
Object queueTrackIdentity(Audio audio) {
  if (audio.isOnline) {
    return ('online', audio.onlineProvider, audio.onlineId);
  }
  final cue = audio.cueTrack;
  if (cue != null) {
    // Reimporting an edited sheet can retain its path/track number while
    // referring to a different source or segment. Match the stable identity
    // registry's segment contract without loading or mutating that registry.
    return (
      'cue',
      cue.identity,
      p.windows.normalize(cue.sourcePath.replaceAll('/', r'\')).toLowerCase(),
      cue.startFrame,
      cue.endFrame,
    );
  }
  final path = audio.path;
  if (p.windows.isAbsolute(path)) {
    return (
      'file-windows',
      p.windows.normalize(path.replaceAll('/', r'\')).toLowerCase()
    );
  }
  return ('file', p.normalize(path));
}
