#ifndef DAN_PLAYER_WINDOW_CHROME_POLICY_H_
#define DAN_PLAYER_WINDOW_CHROME_POLICY_H_

#include <windows.h>

namespace window_chrome {

// The app paints its own title bar. NCCALCSIZE alone only moves the client
// edge: DWM can still paint caption buttons over an extended acrylic frame.
// Keep sizing, system-menu and minimize/maximize capabilities, but never the
// native caption, including when a plugin restores saved fullscreen styles.
constexpr LONG_PTR CustomTitleBarStyle(LONG_PTR style) {
  return style & ~static_cast<LONG_PTR>(WS_CAPTION);
}

// Windows adds WS_CAPTION to a new overlapped HWND even when CreateWindow's
// requested style omits it. Remove it while the window is still hidden, before
// Flutter/plugins save any normal-window style for later fullscreen restore.
inline bool InitializeCustomTitleBar(HWND window) {
  SetLastError(ERROR_SUCCESS);
  const auto previous = SetWindowLongPtrW(window, GWL_STYLE,
      CustomTitleBarStyle(GetWindowLongPtrW(window, GWL_STYLE)));
  if (previous == 0 && GetLastError() != ERROR_SUCCESS) return false;
  return SetWindowPos(window, nullptr, 0, 0, 0, 0,
      SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
      SWP_NOOWNERZORDER | SWP_NOACTIVATE) != FALSE;
}

inline void KeepCustomTitleBar(WPARAM wparam, LPARAM lparam) {
  if (wparam == GWL_STYLE && lparam != 0) {
    auto* styles = reinterpret_cast<STYLESTRUCT*>(lparam);
    styles->styleNew = static_cast<DWORD>(CustomTitleBarStyle(styles->styleNew));
  }
}

}  // namespace window_chrome

#endif  // DAN_PLAYER_WINDOW_CHROME_POLICY_H_
