/// A result selection must never seek/start a newer playback session. The
/// validity predicate is checked again after every asynchronous boundary and
/// after seek (which can synchronously dispatch events). A newer transport
/// pause can keep the opened/positioned source without starting its output.
Future<bool> guardedPlaybackSeek({
  required bool Function() isCurrent,
  required Future<bool> Function() open,
  required void Function() seek,
  required void Function() start,
  bool Function()? shouldStart,
}) async {
  if (!isCurrent()) return false;
  if (!await open() || !isCurrent()) return false;
  seek();
  if (!isCurrent() || shouldStart?.call() == false) return false;
  start();
  return true;
}

/// A manual seek must have a live decoder, and only a successful native seek
/// may change practice, resume, lyric or playback-state intent. Keep the
/// duration read lazy while a newer source is still opening.
bool guardedManualPlaybackSeek({
  required bool queueEditable,
  required bool buffering,
  required bool hasSource,
  required bool hasTrack,
  required double Function() duration,
  required double target,
  required double Function(double) seekAndRead,
  required void Function(double) commit,
}) {
  if (!queueEditable || buffering || !hasSource || !hasTrack) return false;
  final length = duration();
  if (!length.isFinite ||
      length <= 0 ||
      !target.isFinite ||
      target < 0 ||
      target > length) {
    return false;
  }
  commit(seekAndRead(target));
  return true;
}
