#ifndef RUNNER_DESKTOP_INTEGRATION_POLICY_H_
#define RUNNER_DESKTOP_INTEGRATION_POLICY_H_

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace desktop_integration {

// Packed like Win32 COLORREF (00BBGGRR), without depending on windows.h.
using Rgb = std::uint32_t;
constexpr Rgb RgbColor(unsigned r, unsigned g, unsigned b) {
  return r | (g << 8) | (b << 16);
}

inline double RelativeLuminance(Rgb color) {
  const auto linear = [](unsigned channel) {
    const double srgb = channel / 255.0;
    return srgb <= .04045 ? srgb / 12.92
                         : std::pow((srgb + .055) / 1.055, 2.4);
  };
  return .2126 * linear(color & 0xff) + .7152 * linear((color >> 8) & 0xff) +
         .0722 * linear((color >> 16) & 0xff);
}

inline double ContrastRatio(Rgb first, Rgb second) {
  const double a = RelativeLuminance(first);
  const double b = RelativeLuminance(second);
  return (std::max(a, b) + .05) / (std::min(a, b) + .05);
}

inline Rgb ContrastAdjustedAccent(Rgb accent, Rgb background,
                                  double minimum_ratio = 4.5) {
  accent &= 0x00ffffff;
  if (ContrastRatio(accent, background) >= minimum_ratio) return accent;
  const Rgb endpoint = ContrastRatio(0, background) >=
                              ContrastRatio(0x00ffffff, background)
                          ? 0 : 0x00ffffff;
  // Tint/shade only as much as needed. Never replace all accents with a
  // system black/white glyph just because the user's cover color is pale.
  for (unsigned amount = 1; amount <= 255; ++amount) {
    const auto channel = [&](unsigned shift) {
      return ((((accent >> shift) & 0xff) * (255 - amount) +
               ((endpoint >> shift) & 0xff) * amount + 127) / 255) << shift;
    };
    const Rgb candidate = channel(0) | channel(8) | channel(16);
    if (ContrastRatio(candidate, background) >= minimum_ratio) return candidate;
  }
  return endpoint;
}

constexpr Rgb TaskbarReferenceBackground(bool light) {
  // Windows paints the real translucent surface; these conservative neutral
  // references are not sampled pixels or a promise about custom Shell themes.
  return light ? RgbColor(243, 243, 243) : RgbColor(32, 32, 32);
}

inline Rgb TaskbarIconColor(Rgb accent, bool light, bool high_contrast,
                            Rgb system_text) {
  return high_contrast ? system_text & 0x00ffffff
                       : ContrastAdjustedAccent(accent,
                             TaskbarReferenceBackground(light));
}

constexpr bool NativeThemeChanged(Rgb previous_accent, bool previous_dark,
                                  Rgb next_accent, bool next_dark) {
  return (previous_accent & 0x00ffffff) != (next_accent & 0x00ffffff) ||
         previous_dark != next_dark;
}

// Deliberately outside Flutter/plugin command IDs. Unknown WM_COMMAND messages
// must continue to the existing runner/plugin handlers.
constexpr unsigned kPrevious = 0x5101;
constexpr unsigned kToggle = 0x5102;
constexpr unsigned kNext = 0x5103;
constexpr unsigned kRestore = 0x5110;
constexpr unsigned kShowMain = 0x5111;
constexpr unsigned kShowMini = 0x5112;
constexpr unsigned kDesktopLyrics = 0x5113;
constexpr unsigned kExit = 0x5114;
constexpr unsigned kThumbButtonClicked = 0x1800;  // THBN_CLICKED

enum class Action {
  kNone,
  kRestore,
  kShowMain,
  kShowMini,
  kPrevious,
  kToggle,
  kNext,
  kDesktopLyrics,
  kExit,
};

// The native tray popup uses the Windows icon font rather than hand-drawn GDI
// primitives. Keeping this semantic mapping in the platform-independent
// policy makes every command's glyph reviewable and testable without an HWND.
enum class PopupIcon {
  kNone,
  kShowMain,
  kShowMini,
  kPrevious,
  kToggle,
  kNext,
  kDesktopLyrics,
  kExit,
};

constexpr int PopupMaterialIndex(PopupIcon icon, bool playing) {
  switch (icon) {
    case PopupIcon::kShowMain: return 0;
    case PopupIcon::kShowMini: return 1;
    case PopupIcon::kPrevious: return 2;
    case PopupIcon::kToggle: return playing ? 4 : 3;
    case PopupIcon::kNext: return 5;
    case PopupIcon::kDesktopLyrics: return 6;
    case PopupIcon::kExit: return 7;
    default: return -1;
  }
}

inline Rgb TrayIconCapsuleColor(Rgb accent, Rgb background, bool dark, bool enabled) {
  const unsigned amount = enabled ? (dark ? 58 : 32) : (dark ? 18 : 12);
  const auto channel = [&](unsigned shift) {
    return ((((accent >> shift) & 0xff) * amount +
             ((background >> shift) & 0xff) * (255 - amount) + 127) / 255) << shift;
  };
  return channel(0) | channel(8) | channel(16);
}

struct Playback {
  bool ready = false;
  bool has_track = false;
  bool has_queue = false;
  bool playing = false;
  bool buffering = false;
  bool desktop_lyrics = false;
};

// Hover only repaints affected rows. A real playback change must also refresh
// every dependent row (enabled actions, play/pause glyph, and lyrics check).
// Identical progress/status pushes must not invalidate the complete popup.
constexpr bool PopupPlaybackChanged(const Playback& previous,
                                    const Playback& next) {
  return previous.ready != next.ready ||
         previous.has_track != next.has_track ||
         previous.has_queue != next.has_queue ||
         previous.playing != next.playing ||
         previous.buffering != next.buffering ||
         previous.desktop_lyrics != next.desktop_lyrics;
}

constexpr Action MenuAction(unsigned command) {
  switch (command) {
    case kRestore: return Action::kRestore;
    case kShowMain: return Action::kShowMain;
    case kShowMini: return Action::kShowMini;
    case kPrevious: return Action::kPrevious;
    case kToggle: return Action::kToggle;
    case kNext: return Action::kNext;
    case kDesktopLyrics: return Action::kDesktopLyrics;
    case kExit: return Action::kExit;
    default: return Action::kNone;
  }
}

constexpr Action TaskbarAction(std::uintptr_t wparam) {
  if (((wparam >> 16) & 0xffff) != kThumbButtonClicked) return Action::kNone;
  const auto command = static_cast<unsigned>(wparam & 0xffff);
  return command == kPrevious || command == kToggle || command == kNext
             ? MenuAction(command)
             : Action::kNone;
}

constexpr const char* ActionName(Action action) {
  switch (action) {
    case Action::kRestore: return "restore";
    case Action::kShowMain: return "showMain";
    case Action::kShowMini: return "showMini";
    case Action::kPrevious: return "previous";
    case Action::kToggle: return "toggle";
    case Action::kNext: return "next";
    case Action::kDesktopLyrics: return "desktopLyrics";
    case Action::kExit: return "exit";
    default: return "";
  }
}

constexpr PopupIcon PopupIconForAction(Action action) {
  switch (action) {
    case Action::kRestore:
    case Action::kShowMain:
      return PopupIcon::kShowMain;
    case Action::kShowMini:
      return PopupIcon::kShowMini;
    case Action::kPrevious:
      return PopupIcon::kPrevious;
    case Action::kToggle:
      return PopupIcon::kToggle;
    case Action::kNext:
      return PopupIcon::kNext;
    case Action::kDesktopLyrics:
      return PopupIcon::kDesktopLyrics;
    case Action::kExit:
      return PopupIcon::kExit;
    default:
      return PopupIcon::kNone;
  }
}

// Segoe MDL2 Assets is available on all supported Windows 10/11 versions.
// These code points are the platform's OpenInNewWindow, ChromeRestore,
// Previous, Play/Pause, Next, ClosedCaption and PowerButton symbols.
constexpr wchar_t PopupGlyph(PopupIcon icon, bool playing) {
  switch (icon) {
    case PopupIcon::kShowMain:
      return L'\uE8A7';
    case PopupIcon::kShowMini:
      return L'\uE923';
    case PopupIcon::kPrevious:
      return L'\uE892';
    case PopupIcon::kToggle:
      return playing ? L'\uE769' : L'\uE768';
    case PopupIcon::kNext:
      return L'\uE893';
    case PopupIcon::kDesktopLyrics:
      return L'\uE7F0';
    case PopupIcon::kExit:
      return L'\uE7E8';
    default:
      return L'\0';
  }
}

constexpr bool Allows(Action action, const Playback& playback) {
  switch (action) {
    case Action::kToggle:
      return playback.ready && playback.has_track && !playback.buffering;
    case Action::kPrevious:
    case Action::kNext:
      return playback.ready && playback.has_queue && !playback.buffering;
    case Action::kDesktopLyrics:
      return playback.ready && playback.has_track;
    case Action::kNone:
      return false;
    default:
      return true;
  }
}

// Shell notification order is not guaranteed. Never add thumbnail buttons
// until TaskbarButtonCreated, and add exactly once per Shell button lifetime.
struct ShellState {
  bool taskbar_ready = false;
  bool buttons_added = false;
  void ExplorerRestarted() {
    taskbar_ready = false;
    buttons_added = false;
  }
  void TaskbarButtonCreated() {
    taskbar_ready = true;
    buttons_added = false;
  }
  bool ShouldAdd(bool enabled) const {
    return enabled && taskbar_ready && !buttons_added;
  }
  bool ShouldUpdate() const { return taskbar_ready && buttons_added; }
};

constexpr bool VisualsHidden(bool visible, bool minimized) {
  return !visible || minimized;
}

}  // namespace desktop_integration

#endif  // RUNNER_DESKTOP_INTEGRATION_POLICY_H_
