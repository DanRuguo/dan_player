#include "../desktop_integration_policy.h"

#include <cstring>
#include <iostream>

namespace p = desktop_integration;

int main() {
  int count = 0;
  const auto check = [&](bool condition, const char* label) {
    ++count;
    if (!condition) {
      std::cerr << "FAIL: " << label << '\n';
      std::exit(1);
    }
  };
  check(p::ContrastRatio(0, 0x00ffffff) == 21, "sRGB black-white contrast");
  const auto teal = p::RgbColor(0, 128, 128);
  const auto purple = p::RgbColor(148, 72, 189);
  check(p::TaskbarIconColor(teal, true, false, 0) !=
            p::TaskbarIconColor(purple, true, false, 0),
        "different cover accents produce different taskbar icons");
  check(p::TaskbarIconColor(teal, true, false, 0) !=
            p::TaskbarIconColor(teal, false, false, 0),
        "same cover accent adapts when Windows taskbar theme switches");
  check(p::TaskbarIconColor(teal, true, true, p::RgbColor(255, 255, 0)) ==
            p::RgbColor(255, 255, 0), "high contrast keeps exact system text color");
  check(p::TaskbarIconColor(purple, false, true, p::RgbColor(0, 255, 255)) ==
            p::RgbColor(0, 255, 255), "high contrast ignores custom accent");
  check(p::ContrastAdjustedAccent(p::RgbColor(20, 40, 80), 0x00ffffff) ==
            p::RgbColor(20, 40, 80), "already legible accent retained exactly");
  check(p::NativeThemeChanged(teal, false, purple, false),
        "accent-only configure rebuilds existing icons");
  check(p::NativeThemeChanged(teal, false, teal, true),
        "theme-only configure refreshes native visuals");
  check(!p::NativeThemeChanged(teal, true, teal, true),
        "identical configure does not rebuild icon handles");
  for (unsigned red = 0; red <= 255; red += 51) {
    for (unsigned green = 0; green <= 255; green += 51) {
      for (unsigned blue = 0; blue <= 255; blue += 51) {
        const auto accent = p::RgbColor(red, green, blue);
        for (const bool light : {false, true}) {
          const auto adjusted = p::TaskbarIconColor(accent, light, false, 0);
          check(p::ContrastRatio(adjusted, p::TaskbarReferenceBackground(light)) >= 4.5,
                "full accent lattice meets reference-surface contrast");
        }
      }
    }
  }
  p::Playback state;
  const auto playback_from_bits = [](unsigned bits) {
    p::Playback playback;
    playback.ready = (bits & 1) != 0;
    playback.has_track = (bits & 2) != 0;
    playback.has_queue = (bits & 4) != 0;
    playback.playing = (bits & 8) != 0;
    playback.buffering = (bits & 16) != 0;
    playback.desktop_lyrics = (bits & 32) != 0;
    return playback;
  };
  // Exhaust all pairs, including transient/not-ready combinations. The menu
  // refresh contract compares actual state, not only the currently enabled
  // commands; a playing or captions change must not wait for the next hover.
  for (unsigned previous = 0; previous < 64; ++previous) {
    for (unsigned next = 0; next < 64; ++next) {
      check(p::PopupPlaybackChanged(playback_from_bits(previous),
                                   playback_from_bits(next)) ==
                (previous != next),
            "all playback state changes refresh popup; duplicates stay clean");
    }
  }
  for (const auto action : {p::Action::kPrevious, p::Action::kToggle,
                            p::Action::kNext, p::Action::kDesktopLyrics}) {
    check(!p::Allows(action, state), "cold playback action is disabled");
  }
  for (const auto action : {p::Action::kRestore, p::Action::kShowMain,
                            p::Action::kShowMini, p::Action::kExit}) {
    check(p::Allows(action, state), "cold window/exit action remains available");
  }
  check(!p::Allows(p::Action::kNone, state), "unknown action rejected");
  state.ready = true;
  check(!p::Allows(p::Action::kToggle, state), "empty ready player cannot play");
  state.has_track = true;
  check(p::Allows(p::Action::kToggle, state), "loaded track can toggle");
  check(!p::Allows(p::Action::kNext, state), "empty queue cannot skip");
  state.has_queue = true;
  check(p::Allows(p::Action::kNext, state), "ready queue can skip");
  check(p::Allows(p::Action::kPrevious, state), "ready queue can go back");
  state.buffering = true;
  check(!p::Allows(p::Action::kToggle, state), "buffering blocks stale toggle");
  check(!p::Allows(p::Action::kNext, state), "buffering blocks stale next");
  check(p::Allows(p::Action::kExit, state), "exit never depends on audio state");
  check(p::Allows(p::Action::kDesktopLyrics, state), "lyrics can close while buffering");

  const auto notification = static_cast<std::uintptr_t>(p::kThumbButtonClicked) << 16;
  check(p::TaskbarAction(notification | p::kPrevious) == p::Action::kPrevious,
         "taskbar previous ID");
  check(p::TaskbarAction(notification | p::kToggle) == p::Action::kToggle,
         "taskbar toggle ID");
  check(p::TaskbarAction(notification | p::kNext) == p::Action::kNext,
         "taskbar next ID");
  check(p::TaskbarAction(p::kNext) == p::Action::kNone, "normal menu message not consumed");
  check(p::TaskbarAction((1U << 16) | p::kNext) == p::Action::kNone,
         "other notification not consumed");
  check(p::TaskbarAction(notification | 101U) == p::Action::kNone,
         "other plugin ID not consumed");
  check(p::TaskbarAction(notification | p::kExit) == p::Action::kNone,
         "taskbar cannot inject exit menu ID");
  check(p::MenuAction(0) == p::Action::kNone, "cancelled popup performs no action");
  check(p::MenuAction(p::kExit) == p::Action::kExit, "explicit exit menu maps to exit");
  check(std::strcmp(p::ActionName(p::Action::kShowMini), "showMini") == 0,
         "mini event protocol");
  check(std::strcmp(p::ActionName(p::Action::kDesktopLyrics), "desktopLyrics") == 0,
         "desktop lyrics not taskbar lyrics");

  check(p::PopupIconForAction(p::Action::kShowMain) ==
            p::PopupIcon::kShowMain,
        "main window uses the semantic window glyph");
  check(p::PopupIconForAction(p::Action::kShowMini) ==
            p::PopupIcon::kShowMini,
        "mini player uses the semantic compact-window glyph");
  check(p::PopupIconForAction(p::Action::kPrevious) ==
            p::PopupIcon::kPrevious,
        "previous command has a previous glyph");
  check(p::PopupIconForAction(p::Action::kToggle) == p::PopupIcon::kToggle,
        "toggle command owns the play/pause glyph");
  check(p::PopupIconForAction(p::Action::kNext) == p::PopupIcon::kNext,
        "next command has a next glyph");
  check(p::PopupIconForAction(p::Action::kDesktopLyrics) ==
            p::PopupIcon::kDesktopLyrics,
        "desktop lyrics use the captions glyph");
  check(p::PopupIconForAction(p::Action::kExit) == p::PopupIcon::kExit,
        "exit uses the platform power glyph");
  check(p::PopupIconForAction(p::Action::kNone) == p::PopupIcon::kNone,
        "unknown popup action has no glyph");
  check(p::PopupGlyph(p::PopupIcon::kToggle, false) !=
            p::PopupGlyph(p::PopupIcon::kToggle, true),
        "toggle glyph follows playback state");
  check(p::PopupGlyph(p::PopupIcon::kPrevious, false) !=
            p::PopupGlyph(p::PopupIcon::kNext, false),
        "previous and next are not visually conflated");
  check(p::PopupGlyph(p::PopupIcon::kShowMain, false) != L'\0' &&
            p::PopupGlyph(p::PopupIcon::kShowMini, false) != L'\0' &&
            p::PopupGlyph(p::PopupIcon::kDesktopLyrics, false) != L'\0' &&
            p::PopupGlyph(p::PopupIcon::kExit, false) != L'\0',
        "every visible tray command has an icon-font glyph");

  p::ShellState shell;
  check(!shell.ShouldAdd(true), "configure before shell ready does not add buttons");
  check(!shell.ShouldUpdate(), "no update before add");
  shell.TaskbarButtonCreated();
  check(!shell.ShouldAdd(false), "disabled initial controls are not installed");
  check(shell.ShouldAdd(true), "ready shell installs requested buttons");
  shell.buttons_added = true;
  check(!shell.ShouldAdd(true), "add once per taskbar lifetime");
  check(shell.ShouldUpdate(), "subsequent state updates reuse buttons");
  check(!shell.ShouldAdd(false) && shell.ShouldUpdate(), "disable hides existing buttons");
  shell.ExplorerRestarted();
  check(!shell.taskbar_ready && !shell.buttons_added, "restart clears Shell handles state");
  check(!shell.ShouldAdd(true), "restart waits for new window taskbar button");
  shell.TaskbarButtonCreated();
  check(shell.ShouldAdd(true), "restart reapplies exactly three controls");

  check(!p::VisualsHidden(true, false), "visible normal window draws");
  check(p::VisualsHidden(false, false), "hidden window pauses visuals");
  check(p::VisualsHidden(true, true), "minimized window pauses visuals");
  check(p::VisualsHidden(false, true), "hidden minimized window pauses visuals");
  std::cout << "PASS: " << count << " desktop policy assertions (no HWND/Shell/audio)\n";
  return 0;
}
