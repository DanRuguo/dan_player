#ifndef DAN_PLAYER_WINDOW_CHROME_POLICY_H_
#define DAN_PLAYER_WINDOW_CHROME_POLICY_H_

#include <windows.h>
#include <optional>

namespace window_chrome {

// window_manager 0.5.2's hidden title bar keeps eight physical pixels on the
// restored window's sides/bottom and zero or one on top. These exposed insets
// can be painted separately from Flutter on both Windows 10 and 11. Consume
// only this exact plugin calculation, without changing WS_CAPTION or native
// window capabilities. Maximized work-area and fullscreen calculations stay
// owned by the plugin; a normal title bar does not return a handled zero.
inline bool CorrectWindowManagerHiddenFrame(
    const RECT& proposed, RECT& calculated,
    std::optional<LRESULT> plugin_result, bool maximized) {
  if (!plugin_result.has_value() || *plugin_result != 0 || maximized) {
    return false;
  }
  const LONG top_inset = calculated.top - proposed.top;
  if (calculated.left - proposed.left != 8 ||
      proposed.right - calculated.right != 8 ||
      proposed.bottom - calculated.bottom != 8 ||
      (top_inset != 0 && top_inset != 1)) {
    return false;
  }
  calculated = proposed;
  return true;
}

}  // namespace window_chrome

#endif  // DAN_PLAYER_WINDOW_CHROME_POLICY_H_
