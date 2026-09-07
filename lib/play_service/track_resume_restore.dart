import 'dart:async';
import 'package:dan_player/library/cue_track.dart';
import 'package:path/path.dart' as p;

/// A legacy session retains CUE frame coordinates even before stable IDs.
/// Duration equality cannot prove two slices of the same file are the same.
bool sameCueResumeSegment(
        CueTrackReference? saved, CueTrackReference current) =>
    saved != null &&
    saved.number == current.number &&
    saved.startFrame == current.startFrame &&
    saved.endFrame == current.endFrame &&
    p.windows.equals(saved.sourcePath, current.sourcePath);

/// A disk lookup can outlive source loading, a newer track choice, or a manual
/// seek. Recheck the request at the point of applying its position.
Future<double?> restoreRememberedTrackPosition({
  required Future<double?> Function() read,
  required bool Function() canApply,
  required void Function(double) seek,
}) async {
  if (!canApply()) return null;
  double? position;
  try {
    position = await read().timeout(const Duration(milliseconds: 500));
  } on TimeoutException {
    return null;
  }
  if (position == null || !canApply()) return null;
  seek(position);
  return position;
}
