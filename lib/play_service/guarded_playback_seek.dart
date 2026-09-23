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
