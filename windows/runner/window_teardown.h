#ifndef RUNNER_WINDOW_TEARDOWN_H_
#define RUNNER_WINDOW_TEARDOWN_H_

#include <windows.h>

namespace window_teardown {

// Plugins supply the hidden non-client frame while Flutter is alive. Hide the
// parent before removing their handlers/resources, otherwise WS_CAPTION can
// briefly paint native caption buttons during destruction. SW_HIDE never
// activates/shows the window; its return value is the *previous* visibility.
inline void HideBeforeResources(HWND window,
                                decltype(&ShowWindow) show = &ShowWindow,
                                decltype(&IsWindow) valid = &IsWindow) {
  if (window && valid(window)) show(window, SW_HIDE);
}

}  // namespace window_teardown

#endif  // RUNNER_WINDOW_TEARDOWN_H_
