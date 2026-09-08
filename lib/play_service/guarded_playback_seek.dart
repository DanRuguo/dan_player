/// A result selection must never seek/start a newer playback session. The
/// validity predicate is checked again after every asynchronous boundary and
/// after seek (which can synchronously dispatch events).
Future<bool> guardedPlaybackSeek({
  required bool Function() isCurrent,
  required Future<bool> Function() open,
  required void Function() seek,
  required void Function() start,
}) async {
  if (!isCurrent()) return false;
  if (!await open() || !isCurrent()) return false;
  seek();
  if (!isCurrent()) return false;
  start();
  return true;
}
