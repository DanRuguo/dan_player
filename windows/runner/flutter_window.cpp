#include "flutter_window.h"

#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_integration.h"
#include "installer_launcher.h"
#include "window_backdrop.h"
#include "window_resize_policy.h"
#include "window_teardown.h"
#include "windows_shell.h"
#include "../../third_party/desktop_lyric/windows/runner/window_chrome_policy.h"

namespace {

std::optional<LRESULT> HitTestNativeResizeBorder(HWND window, LPARAM lparam) {
  const LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  if (!window_resize::CanHitTestResizeBorder(style, IsZoomed(window) != FALSE)) {
    return std::nullopt;
  }

  RECT window_rect{};
  if (!GetWindowRect(window, &window_rect)) {
    return std::nullopt;
  }

  const POINT pointer = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
  if (pointer.x < window_rect.left || pointer.x >= window_rect.right ||
      pointer.y < window_rect.top || pointer.y >= window_rect.bottom) {
    return std::nullopt;
  }

  const UINT dpi = GetDpiForWindow(window);
  const int border_x = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                       GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
  const int border_y = GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
                       GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);

  return window_resize::HitTestResizeBorder(window_rect, pointer, border_x,
                                             border_y);
}

void RefreshNonClientFrameAfterResizeStyleChange(HWND window,
                                                  WPARAM wparam,
                                                  LPARAM lparam) {
  if (wparam != GWL_STYLE || lparam == 0) return;
  const auto* styles = reinterpret_cast<const STYLESTRUCT*>(lparam);
  if (!window_resize::NeedsNonClientFrameRefresh(styles->styleOld,
                                                  styles->styleNew)) {
    return;
  }
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER | SWP_NOACTIVATE);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  backdrop_controller_ = std::make_unique<WindowBackdropController>(
      GetHandle(), flutter_controller_->engine());
  desktop_controller_ = std::make_unique<DesktopIntegrationController>(
      GetHandle(), flutter_controller_->engine());
  installer_launcher_ = std::make_unique<InstallerLauncherController>(
      flutter_controller_->engine());
  windows_shell_ = std::make_unique<WindowsShellController>(
      GetHandle(), flutter_controller_->engine());

  // Dart applies restored bounds, resize policy and the backdrop before it
  // explicitly shows the HWND. Showing here on the first Flutter frame races
  // waitUntilReadyToShow and exposes the runner's temporary startup geometry.
  // Keep a frame pending so the first Dart-controlled show already has pixels.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  window_teardown::HideBeforeResources(GetHandle());
  windows_shell_.reset();
  installer_launcher_.reset();
  desktop_controller_.reset();
  backdrop_controller_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (windows_shell_) {
    if (const auto result = windows_shell_->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }
  if (message == WM_STYLECHANGED) {
    RefreshNonClientFrameAfterResizeStyleChange(hwnd, wparam, lparam);
  }
  if (desktop_controller_) {
    if (const auto result =
            desktop_controller_->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }
  if (backdrop_controller_) {
    if (const auto result =
            backdrop_controller_->HandleMessage(message, wparam, lparam)) {
      return *result;
    }
  }

  std::optional<RECT> proposed_client_rect;
  if (message == WM_NCCALCSIZE && wparam == TRUE &&
      lparam != 0) {
    proposed_client_rect =
        reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0];
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);

    if (proposed_client_rect.has_value()) {
      auto* parameters = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      // Retain native caption/sizing styles and system animation behavior.
      // WM_NCHITTEST below supplies the client-edge resize affordance.
      window_chrome::CorrectWindowManagerHiddenFrame(
          *proposed_client_rect, parameters->rgrc[0], result,
          IsZoomed(hwnd) != FALSE);
    }

    if (result) {
      return *result;
    }
  }

  // The hidden title bar now consumes non-client resize insets. Supply the
  // same DPI-aware edge/corner result on every
  // supported Windows version. The plugin already returns HTNOWHERE when size
  // lock is active; WS_THICKFRAME/IsZoomed keep fullscreen and maximized modes
  // out of this fallback as well.
  if (message == WM_NCHITTEST) {
    if (const auto hit = HitTestNativeResizeBorder(hwnd, lparam)) {
      return *hit;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
