#ifndef RUNNER_WINDOW_BACKDROP_H_
#define RUNNER_WINDOW_BACKDROP_H_

#include <windows.h>

#include <memory>
#include <optional>

namespace flutter {
class FlutterEngine;
}

// Owns only this top-level window's DWM/Accent policy. It never captures screen
// contents or changes Windows personalization/accessibility preferences.
// Destroy before the Flutter engine that owns the channel's messenger.
class WindowBackdropController {
 public:
  WindowBackdropController(HWND window, flutter::FlutterEngine* engine);
  ~WindowBackdropController();

  WindowBackdropController(const WindowBackdropController&) = delete;
  WindowBackdropController& operator=(const WindowBackdropController&) = delete;

  // Observe before plugin dispatch, so a plugin consuming a theme/frame message
  // cannot hide the notification. Only our private refresh and background erase
  // messages are consumed; input, styles and resize hit testing are untouched.
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_WINDOW_BACKDROP_H_
