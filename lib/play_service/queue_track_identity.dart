import 'package:dan_player/library/audio_library.dart';
import 'package:path/path.dart' as p;

/// Metadata-only identity: never resolves symlinks, scans or opens music files.
/// CUE slices retain their own identity even when sharing a physical source.
Object queueTrackIdentity(Audio audio) {
  if (audio.isOnline) {
    return ('online', audio.onlineProvider, audio.onlineId);
  }
  if (audio.cueTrack != null) return ('cue', audio.cueTrack!.identity);
  final path = audio.path;
  if (p.windows.isAbsolute(path)) {
    return (
      'file-windows',
      p.windows.normalize(path.replaceAll('/', r'\')).toLowerCase()
    );
  }
  return ('file', p.normalize(path));
}
