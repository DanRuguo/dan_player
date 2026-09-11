#ifndef DESKTOP_LYRIC_RUNNER_FLUTTER_WINDOW_H_
#define DESKTOP_LYRIC_RUNNER_FLUTTER_WINDOW_H_

#include "frame_display_channel.h"

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "appearance_palette_window.h"

namespace desktop_lyric_runner {

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
  std::unique_ptr<FrameDisplayChannel> frame_display_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> geometry_channel_;
  std::shared_ptr<PaletteWindowManager> palette_manager_;
};

}  // namespace desktop_lyric_runner

#endif  // DESKTOP_LYRIC_RUNNER_FLUTTER_WINDOW_H_
