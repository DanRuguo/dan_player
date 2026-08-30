#ifndef RUNNER_WINDOW_RESIZE_POLICY_H_
#define RUNNER_WINDOW_RESIZE_POLICY_H_

#include <windows.h>

#include <optional>

namespace window_resize {

// A hidden-title-bar window is user-resizable only while the native sizing
// frame exists and the window is restored. Fullscreen and the app's size-lock
// policy both remove WS_THICKFRAME; maximized windows use their restore button
// instead of edge dragging.
constexpr bool CanHitTestResizeBorder(LONG_PTR style, bool maximized) {
  return (style & WS_THICKFRAME) != 0 && !maximized;
}

// SetWindowLong does not recalculate cached non-client geometry by itself.
// Detect the one style transition that changes resize borders so the runner can
// issue SetWindowPos(..., SWP_FRAMECHANGED) after window_manager toggles it.
constexpr bool NeedsNonClientFrameRefresh(LONG_PTR old_style,
                                          LONG_PTR new_style) {
  return ((old_style ^ new_style) & WS_THICKFRAME) != 0;
}

inline std::optional<LRESULT> HitTestResizeBorder(const RECT& window_rect,
                                                  POINT pointer,
                                                  int border_x,
                                                  int border_y) {
  if (border_x <= 0 || border_y <= 0 ||
      pointer.x < window_rect.left || pointer.x >= window_rect.right ||
      pointer.y < window_rect.top || pointer.y >= window_rect.bottom) {
    return std::nullopt;
  }

  const bool on_left = pointer.x < window_rect.left + border_x;
  const bool on_right = pointer.x >= window_rect.right - border_x;
  const bool on_top = pointer.y < window_rect.top + border_y;
  const bool on_bottom = pointer.y >= window_rect.bottom - border_y;

  if (on_top && on_left) return HTTOPLEFT;
  if (on_top && on_right) return HTTOPRIGHT;
  if (on_bottom && on_left) return HTBOTTOMLEFT;
  if (on_bottom && on_right) return HTBOTTOMRIGHT;
  if (on_left) return HTLEFT;
  if (on_right) return HTRIGHT;
  if (on_top) return HTTOP;
  if (on_bottom) return HTBOTTOM;
  return std::nullopt;
}

}  // namespace window_resize

#endif  // RUNNER_WINDOW_RESIZE_POLICY_H_
