/// Small, testable policy around the native initializer. No sleeps, recursive
/// retries or attempts to take over a device reported as busy are allowed.
class WasapiInitializationResult {
  const WasapiInitializationResult(this.errorCode, this.compatibleFormat);
  final int errorCode;
  final bool compatibleFormat;
  bool get succeeded => errorCode == 0;
}

/// The active decoder may temporarily use a replacement output which is still
/// being validated. A new track must inherit the last confirmed choice, not a
/// failed replacement whose asynchronous URL rollback has not finished yet.
class WasapiOutputMode {
  bool active = false;
  bool preferred = false;

  void selectBeforePlayback(bool exclusive) {
    active = exclusive;
    preferred = exclusive;
  }

  void commitStream(bool exclusive) => active = exclusive;

  void confirmActive() => preferred = active;
}

/// Flush old device samples only for an explicit seek. Ordinary pause keeps
/// its buffered tail. A rejected seek still restores the previous play state;
/// seeking a paused stream must never resume it.
void seekWasapiOutput({
  required bool wasPlaying,
  required void Function() flush,
  required void Function() move,
  required void Function() resume,
}) {
  flush();
  try {
    move();
  } finally {
    if (wasPlaying) resume();
  }
}

WasapiInitializationResult initializeWasapiOutput({
  required int Function(bool compatibleFormat) attempt,
  required void Function() resetExisting,
}) {
  var compatible = false;
  var reset = false;
  var code = -1;
  for (var attempts = 0; attempts < 3; attempts++) {
    code = attempt(compatible);
    if (code == 0) return WasapiInitializationResult(0, compatible);
    if (code == 14 && !reset) {
      // BASS_ERROR_ALREADY
      reset = true;
      resetExisting();
      continue;
    }
    if (code == 6 && !compatible) {
      // BASS_ERROR_FORMAT
      compatible = true;
      continue;
    }
    break;
  }
  return WasapiInitializationResult(code, compatible);
}
