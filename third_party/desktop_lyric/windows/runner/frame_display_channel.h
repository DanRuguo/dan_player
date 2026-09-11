#pragma once

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// Per HWND: Flutter's desktop Display currently describes the primary display.
// Query the window's monitor on moves/display changes, never once per frame.
class FrameDisplayChannel {
 public:
  FrameDisplayChannel(HWND window, flutter::BinaryMessenger* messenger)
      : window_(window), channel_(messenger, "dan_player/frame_display",
          &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "refreshRate") {
        result->Success(flutter::EncodableValue(ReadRate()));
      } else { result->NotImplemented(); }
    });
  }
  ~FrameDisplayChannel() { channel_.SetMethodCallHandler(nullptr); }
  void Handle(UINT message) {
    if (message != WM_WINDOWPOSCHANGED && message != WM_DISPLAYCHANGE) return;
    const auto monitor = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
    if (message != WM_DISPLAYCHANGE && monitor == monitor_) return;
    channel_.InvokeMethod("changed",
        std::make_unique<flutter::EncodableValue>(ReadRate()));
  }
 private:
  double ReadRate() {
    monitor_ = MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST);
    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    DEVMODEW mode{};
    mode.dmSize = sizeof(mode);
    if (!GetMonitorInfoW(monitor_, reinterpret_cast<MONITORINFO*>(&info)) ||
        !EnumDisplaySettingsW(info.szDevice, ENUM_CURRENT_SETTINGS, &mode) ||
        mode.dmDisplayFrequency < 15 || mode.dmDisplayFrequency > 1000) return 0;
    return static_cast<double>(mode.dmDisplayFrequency);
  }
  HWND window_;
  HMONITOR monitor_ = nullptr;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};
