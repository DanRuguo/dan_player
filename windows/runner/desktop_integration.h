#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <memory>
#include <optional>

// Owns Shell resources and optional DWM iconic-preview pixels for the existing
// HWND. It never changes the window frame, DWM backdrop, playback engine or
// application settings.
class DesktopIntegrationController {
 public:
  DesktopIntegrationController(HWND window, flutter::FlutterEngine* engine);
  ~DesktopIntegrationController();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam,
                                       LPARAM lparam);

 private:
  struct Impl;
  // A native popup runs a nested message loop. A temporary shared owner keeps
  // its state alive if the window is destroyed before TrackPopupMenu returns.
  std::shared_ptr<Impl> impl_;
};

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
