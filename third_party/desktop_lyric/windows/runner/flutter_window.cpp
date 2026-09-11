#include "flutter_window.h"

#include <optional>
#include <utility>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>

#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager/window_manager_plugin.h>

namespace desktop_lyric_runner {

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
  // The shared executable also links main-player plugins. Keep the lyric
  // process restricted to its window/screen plugins; no global hotkeys.
  auto* registry = flutter_controller_->engine();
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
  palette_manager_ = std::make_shared<PaletteWindowManager>(GetHandle(),
      flutter_controller_->engine()->messenger(), project_);
  geometry_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "dan_player/desktop_lyric_geometry",
      &flutter::StandardMethodCodec::GetInstance());
  geometry_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "autoHideInsets") {
          result->NotImplemented();
          return;
        }
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableList>(call.arguments()) : nullptr;
        if (!args || args->size() != 4) {
          result->Error("invalid_monitor", "Expected four monitor coordinates");
          return;
        }
        LONG coordinates[4];
        for (size_t i = 0; i < 4; ++i) {
          const auto* value = std::get_if<int32_t>(&(*args)[i]);
          if (!value || *value < -10000000 || *value > 10000000) {
            result->Error("invalid_monitor", "Coordinates must be int32");
            return;
          }
          coordinates[i] = *value;
        }
        if (coordinates[2] <= coordinates[0] || coordinates[3] <= coordinates[1]) {
          result->Error("invalid_monitor", "Monitor must have positive area");
          return;
        }
        APPBARDATA data{};
        data.cbSize = sizeof(data);
        data.rc = {coordinates[0], coordinates[1], coordinates[2], coordinates[3]};
        flutter::EncodableList insets;
        for (const UINT edge : {ABE_LEFT, ABE_TOP, ABE_RIGHT, ABE_BOTTOM}) {
          data.uEdge = edge;
          const HWND bar = reinterpret_cast<HWND>(SHAppBarMessage(ABM_GETAUTOHIDEBAREX, &data));
          RECT rect{};
          const bool vertical = edge == ABE_LEFT || edge == ABE_RIGHT;
          const LONG extent = vertical ? data.rc.right - data.rc.left : data.rc.bottom - data.rc.top;
          const LONG size = bar && GetWindowRect(bar, &rect)
              ? (vertical ? rect.right - rect.left : rect.bottom - rect.top) : 0;
          // Ignore malformed/third-party appbar dimensions; no shell mutation.
          const LONG safe_size = size > 0 && size < extent / 2 ? size : 0;
          insets.emplace_back(static_cast<int32_t>(safe_size));
        }
        result->Success(flutter::EncodableValue(insets));
      });
  frame_display_ = std::make_unique<FrameDisplayChannel>(GetHandle(), flutter_controller_->engine()->messenger());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    // this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  auto palette_manager = std::exchange(palette_manager_, nullptr);
  if (palette_manager) palette_manager->Shutdown();
  if (geometry_channel_) geometry_channel_->SetMethodCallHandler(nullptr);
  geometry_channel_.reset();
  frame_display_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (frame_display_) frame_display_->Handle(message);
  if (palette_manager_ && message == kPaletteDispatchMessage) {
    auto manager = palette_manager_;
    manager->DrainOwnerTasks();
    return 0;
  }
  if (palette_manager_ && message == WM_TIMER && wparam == kPaletteReadyTimer) {
    auto manager = palette_manager_;
    manager->ReadyTimedOut();
    return 0;
  }
  if (palette_manager_ && message == WM_TIMER && wparam == kPaletteCacheTimer) {
    auto manager = palette_manager_;
    manager->EvictCache();
    return 0;
  }
  if (palette_manager_ && message == kPaletteCloseMessage) {
    auto manager = palette_manager_;
    manager->Close(static_cast<int64_t>(wparam));
    return 0;
  }
  if (palette_manager_ && message == kPaletteShownMessage) {
    auto manager = palette_manager_;
    manager->ShowFirstFrame(static_cast<int64_t>(wparam));
    return 0;
  }
  // Work-area changes need not resize the HWND. Forward events rather than
  // polling or touching Explorer/taskbar ownership; Dart coalesces relayouts.
  if (geometry_channel_ &&
      (message == WM_DISPLAYCHANGE || message == WM_SETTINGCHANGE ||
       message == WM_DPICHANGED || message == WM_EXITSIZEMOVE)) {
    geometry_channel_->InvokeMethod("workAreaChanged", nullptr);
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

}  // namespace desktop_lyric_runner
