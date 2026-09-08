#ifndef RUNNER_APPEARANCE_PALETTE_WINDOW_H_
#define RUNNER_APPEARANCE_PALETTE_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <functional>
#include <memory>
#include <atomic>
#include <deque>
#include <mutex>
#include "palette_task_runner.h"
#include "win32_window.h"

namespace desktop_lyric_runner {

// Stable messages route destruction out of a Dart reply / engine callback.
constexpr UINT kPaletteCloseMessage = WM_APP + 71;
constexpr UINT kPaletteShownMessage = WM_APP + 72;
constexpr UINT kPaletteDispatchMessage = WM_APP + 73;
constexpr UINT_PTR kPaletteReadyTimer = 0xD072;
constexpr UINT kPaletteReadyMilliseconds = 12000;
constexpr UINT_PTR kPaletteCacheTimer = 0xD071;
constexpr UINT kPaletteCacheMilliseconds = 120000;

class AppearancePaletteWindow : public Win32Window {
 public:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  using Handler = std::function<void(const flutter::MethodCall<Value>&,
                                     std::unique_ptr<Result>)>;
  AppearancePaletteWindow(const flutter::DartProject& project, HWND owner,
                          int64_t session, const Value& snapshot, Handler handler);
  ~AppearancePaletteWindow() override;
  void Update(const Value& snapshot);
  void ShowFirstFrame();
  void Present(int64_t session, const Value& snapshot, const RECT& bounds);
  void Suspend();
  std::weak_ptr<bool> lifetime() const { return alive_; }
 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND, UINT, WPARAM, LPARAM) noexcept override;
 private:
  void RequestFreshFrame(int64_t session);
  void UpdateRoundedRegion();
  flutter::DartProject project_;
  HWND owner_;
  int64_t session_;
  Handler handler_;
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
  std::unique_ptr<flutter::FlutterViewController> controller_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
};

class PaletteWindowManager : public std::enable_shared_from_this<PaletteWindowManager> {
 public:
  PaletteWindowManager(HWND owner, flutter::BinaryMessenger* messenger,
                       const flutter::DartProject& project);
  ~PaletteWindowManager();
  void Shutdown();
  void Close(int64_t session, bool notify = true);
  void ShowFirstFrame(int64_t session);
  void EvictCache();
  void DrainOwnerTasks();
  void ReadyTimedOut();
 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  void Handle(const flutter::MethodCall<Value>&, std::shared_ptr<Result>);
  void HandleChild(const flutter::MethodCall<Value>&, std::unique_ptr<Result>);
  void CloseOnPalette(int64_t session, bool notify);
  void ShowFirstFrameOnPalette(int64_t session);
  void EvictCacheOnPalette();
  void OnOwner(std::function<void()> task);
  void OnPalette(std::function<void()> task);
  void ConfigureOwnerTimer(UINT_PTR timer, UINT milliseconds);
  void InvokeOwner(const std::string& method, std::unique_ptr<Value> arguments,
      std::unique_ptr<Result> result = nullptr);
  std::shared_ptr<Result> OwnerReply(std::shared_ptr<Result> result);
  PaletteTaskRunner runner_;
  std::atomic<bool> shutdown_requested_{false};
  std::mutex owner_tasks_mutex_;
  std::deque<std::function<void()>> owner_tasks_;
  HWND owner_;
  flutter::DartProject project_;
  int64_t session_ = 0;
  int64_t prepared_revision_ = 0;
  ULONGLONG ready_deadline_ = 0;
  ULONGLONG cache_deadline_ = 0;
  bool closing_ = false;
  bool palette_closing_ = false;
  bool active_ = false;
  bool warming_ = false;
  bool first_warm_cached_ = false;
  bool cache_allowed_ = false;
  Value snapshot_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::shared_ptr<AppearancePaletteWindow> palette_;
  std::shared_ptr<Result> pending_open_;
};
}  // namespace desktop_lyric_runner
#endif
