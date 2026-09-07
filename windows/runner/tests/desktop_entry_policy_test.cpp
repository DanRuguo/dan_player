#include "../desktop_entry_policy.h"

#include <iostream>

int main() {
  using desktop_entry::CanStartDesktopLyric;
  using desktop_entry::Role;
  using desktop_entry::SelectRole;
  int failures = 0;
  const auto check = [&](bool condition, const char* message) {
    if (!condition) {
      std::cerr << message << '\n';
      ++failures;
    }
  };
  check(SelectRole({}) == Role::player, "normal launch keeps player lease");
  check(SelectRole({"--shell-action=play-pause"}) == Role::player,
        "jump-list actions keep player routing");
  check(SelectRole({"C:\\Music\\--desktop-lyric.flac"}) == Role::player,
        "music filenames cannot select child mode");
  check(SelectRole({"--desktop-lyric", "{\"title\":\"test\"}"}) ==
            Role::desktop_lyric,
        "dedicated child launch selects isolated native window");
  check(SelectRole({"--desktop-lyric"}) == Role::invalid_desktop_lyric,
        "missing payload must not fall through to player");
  check(SelectRole({"--desktop-lyric", ""}) == Role::invalid_desktop_lyric,
        "empty payload must not start an engine");
  check(SelectRole({"--desktop-lyric", "{}", "extra"}) ==
            Role::invalid_desktop_lyric,
        "extra payload must not fall through to player");
  check(CanStartDesktopLyric(Role::desktop_lyric, true, true),
        "owned pipe launch is accepted");
  check(!CanStartDesktopLyric(Role::desktop_lyric, false, true),
        "child requires parent stdin for EOF ownership");
  check(!CanStartDesktopLyric(Role::desktop_lyric, true, false),
        "child requires protocol output pipe");
  check(!CanStartDesktopLyric(Role::player, true, true) &&
            !CanStartDesktopLyric(Role::invalid_desktop_lyric, true, true),
        "pipes alone cannot change a role");
  if (failures == 0) std::cout << "desktop entry policy: 11 checks passed\n";
  return failures == 0 ? 0 : 1;
}
