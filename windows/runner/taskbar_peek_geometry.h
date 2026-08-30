#ifndef RUNNER_TASKBAR_PEEK_GEOMETRY_H_
#define RUNNER_TASKBAR_PEEK_GEOMETRY_H_

#include <windows.h>

#include <cstdint>
#include <limits>

#include "taskbar_thumbnail_policy.h"

namespace taskbar_thumbnail {

inline Size PeekRectSize(const RECT& rect) {
  const auto width = static_cast<std::int64_t>(rect.right) - rect.left;
  const auto height = static_cast<std::int64_t>(rect.bottom) - rect.top;
  if (width <= 0 || height <= 0 || width > std::numeric_limits<int>::max() ||
      height > std::numeric_limits<int>::max()) return {};
  return {static_cast<int>(width), static_cast<int>(height)};
}

// Read-only HWND geometry: no ShowWindow, SetWindowPos, style mutation,
// synthetic WM_NCCALCSIZE dispatch or screenshot. The runner is PerMonitorV2,
// so these client/frame dimensions and GetDpiForWindow metrics share pixels.
class PeekClientGeometry {
 public:
  void Observe(HWND window, bool minimized_message = false) {
    if (minimized_message || !IsWindow(window) || IsIconic(window)) return;
    RECT client{};
    if (GetClientRect(window, &client)) state_.Observe(PeekRectSize(client), false);
  }

  Size Resolve(HWND window) {
    if (!IsWindow(window)) return {};
    Observe(window);
    if (const auto cached = state_.Resolve(); cached.valid()) return cached;

    // The controller may attach after the HWND was initially minimized.
    // WINDOWPLACEMENT retains its normal frame, unlike GetClientRect. Use
    // dimensions only: its workspace origin is not a screen-space position.
    WINDOWPLACEMENT placement{};
    placement.length = sizeof(placement);
    if (!GetWindowPlacement(window, &placement)) return {};
    const auto normal = PeekRectSize(placement.rcNormalPosition);
    if (!normal.valid()) return {};

    RECT frame{}, client{};
    const auto frame_size = GetWindowRect(window, &frame) ? PeekRectSize(frame) : Size{};
    const auto client_size = GetClientRect(window, &client) ? PeekRectSize(client) : Size{};
    if (frame_size.valid() && client_size.valid() &&
        client_size.width <= frame_size.width && client_size.height <= frame_size.height &&
        frame_size.width - client_size.width < normal.width &&
        frame_size.height - client_size.height < normal.height) {
      return RestoredClientSize(normal, frame_size, client_size, {-1, -1});
    }
    // Standard frames can have an empty iconic client, so use DPI-aware
    // non-client metrics if no valid custom-frame inset can be measured.
    RECT adjusted{};
    const auto style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_STYLE)) &
                       ~(WS_MINIMIZE | WS_MAXIMIZE);
    const auto ex_style = static_cast<DWORD>(GetWindowLongPtrW(window, GWL_EXSTYLE));
    const UINT window_dpi = GetDpiForWindow(window);
    Size insets{-1, -1};
    if (AdjustWindowRectExForDpi(&adjusted, style, GetMenu(window) != nullptr,
                                 ex_style, window_dpi ? window_dpi : 96)) {
      // Borderless windows legitimately have zero non-client insets.
      const auto width = static_cast<std::int64_t>(adjusted.right) - adjusted.left;
      const auto height = static_cast<std::int64_t>(adjusted.bottom) - adjusted.top;
      if (width >= 0 && height >= 0 && width <= std::numeric_limits<int>::max() &&
          height <= std::numeric_limits<int>::max()) {
        insets = {static_cast<int>(width), static_cast<int>(height)};
      }
    }
    return RestoredClientSize(normal, frame_size, client_size, insets);
  }

 private:
  PeekClientState state_;
};

}  // namespace taskbar_thumbnail

#endif  // RUNNER_TASKBAR_PEEK_GEOMETRY_H_
