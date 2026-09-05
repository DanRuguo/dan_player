#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

class WindowBackdropController;
class DesktopIntegrationController;
class InstallerLauncherController;
class WindowsShellController;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Declared after the engine so the MethodChannel is destroyed before its
  // messenger, including on partially initialized window teardown.
  std::unique_ptr<WindowBackdropController> backdrop_controller_;
  std::unique_ptr<DesktopIntegrationController> desktop_controller_;
  std::unique_ptr<InstallerLauncherController> installer_launcher_;
  std::unique_ptr<WindowsShellController> windows_shell_;

  // Windows 10 paints the non-client resize insets kept by window_manager's
  // hidden title-bar implementation with the user's accent color. These flags
  // let the runner replace those insets with client area while keeping native
  // resize hit testing. Windows 11 never enables this compatibility path.
  bool uses_legacy_dwm_frame_ = false;
  bool legacy_custom_frame_active_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
