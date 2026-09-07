#ifndef DAN_PLAYER_DESKTOP_ENTRY_POLICY_H_
#define DAN_PLAYER_DESKTOP_ENTRY_POLICY_H_

#include <string>
#include <vector>

namespace desktop_entry {

enum class Role { player, desktop_lyric, invalid_desktop_lyric };

// Only the dedicated first argument selects the child role. A filename or
// shell action containing these characters must keep normal player routing.
inline Role SelectRole(const std::vector<std::string>& arguments) {
  if (arguments.empty() || arguments.front() != "--desktop-lyric") {
    return Role::player;
  }
  // JSON parsing belongs to Dart's existing InitArgsMessage decoder. Reject
  // missing, empty or extra payloads before creating any engine/window.
  return arguments.size() == 2 && !arguments[1].empty()
      ? Role::desktop_lyric : Role::invalid_desktop_lyric;
}

inline bool CanStartDesktopLyric(Role role, bool stdin_is_pipe,
                                 bool stdout_is_pipe) {
  // Parent death is detected by stdin EOF; stdout carries only protocol JSON.
  // An unowned, manually launched child must not leave an orphan overlay.
  return role == Role::desktop_lyric && stdin_is_pipe && stdout_is_pipe;
}

}  // namespace desktop_entry

#endif  // DAN_PLAYER_DESKTOP_ENTRY_POLICY_H_
