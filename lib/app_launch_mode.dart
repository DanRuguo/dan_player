/// Kept in sync with the Windows runner, which selects the native window before
/// Flutter starts. Only a leading flag selects the independent lyric process.
const desktopLyricLaunchArgument = '--desktop-lyric';

/// Dispatch before player initialization: the lyric process must not acquire
/// audio devices, migrate settings, register shortcuts, or create the main UI.
Future<void> dispatchAppLaunch(
  List<String> arguments, {
  required Future<void> Function() startPlayer,
  required Future<void> Function(List<String>) startDesktopLyric,
}) {
  if (arguments.isNotEmpty && arguments.first == desktopLyricLaunchArgument) {
    return startDesktopLyric(arguments.sublist(1));
  }
  return startPlayer();
}
