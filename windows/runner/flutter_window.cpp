#include "flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_integration.h"
#include "window_backdrop.h"
#include "window_resize_policy.h"

namespace {

// Windows 11 exposes this read-only attribute starting with build 22000. Use a
// feature probe instead of a version check so the runner remains correct even
// when built with an older Windows SDK.
constexpr DWORD kDwmwaVisibleFrameBorderThickness = 37;

// window_manager 0.5.2 keeps an eight-pixel non-client area on the restored
// window's left, right and bottom edges. On Windows 10 DWM paints that area in
// the system accent color. See leanflutter/window_manager#483.
constexpr LONG kWindowManagerResizeInset = 8;

bool HasWindows11FrameAttributes(HWND window) {
  UINT visible_border_thickness = 0;
  return SUCCEEDED(DwmGetWindowAttribute(
      window, kDwmwaVisibleFrameBorderThickness,
      &visible_border_thickness, sizeof(visible_border_thickness)));
}

bool IsWindowManagerHiddenFrameCalculation(const RECT& proposed_client_rect,
                                           const RECT& calculated_client_rect) {
  const LONG top_inset = calculated_client_rect.top - proposed_client_rect.top;
  return calculated_client_rect.left - proposed_client_rect.left ==
             kWindowManagerResizeInset &&
         proposed_client_rect.right - calculated_client_rect.right ==
             kWindowManagerResizeInset &&
         proposed_client_rect.bottom - calculated_client_rect.bottom ==
             kWindowManagerResizeInset &&
         (top_inset == 0 || top_inset == 1);
}

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

  // DWMWA_BORDER_COLOR cannot hide the visible frame on Windows 10; the
  // attribute is Windows 11-only. Leave the Windows 11 message path completely
  // untouched and enable the custom-frame fallback only on legacy DWM.
  uses_legacy_dwm_frame_ = !HasWindows11FrameAttributes(GetHandle());

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

  // Dart applies restored bounds, resize policy and the backdrop before it
  // explicitly shows the HWND. Showing here on the first Flutter frame races
  // waitUntilReadyToShow and exposes the runner's temporary startup geometry.
  // Keep a frame pending so the first Dart-controlled show already has pixels.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
  if (uses_legacy_dwm_frame_ && message == WM_NCCALCSIZE && wparam == TRUE &&
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
      if (result.has_value() && *result == 0) {
        auto* parameters = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        if (IsWindowManagerHiddenFrameCalculation(*proposed_client_rect,
                                                  parameters->rgrc[0])) {
          // Consume the standard frame. WS_THICKFRAME remains set, preserving
          // DWM shadow, maximize/snap behavior and system window animations.
          // WM_NCHITTEST below restores mouse and touch resizing.
          parameters->rgrc[0] = *proposed_client_rect;
          legacy_custom_frame_active_ = true;
          return 0;
        }
      } else if (!result.has_value()) {
        // A normal title bar lets DefWindowProc calculate the non-client area.
        legacy_custom_frame_active_ = false;
      }
    }

    if (result) {
      return *result;
    }
  }

  // window_manager's hidden title bar relies on cached non-client hit regions
  // on Windows 11. Supply the same DPI-aware edge/corner result on every
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
