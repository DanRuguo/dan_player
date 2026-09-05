#pragma once

#include <flutter/flutter_engine.h>
#include <windows.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

// The lease lasts for the process, including startup and native teardown.
class PlayerInstanceLease {
 public:
  explicit PlayerInstanceLease(const std::vector<std::string>& arguments);
  ~PlayerInstanceLease();
  bool is_primary() const { return primary_; }
  bool forwarded() const { return forwarded_; }

 private:
  HANDLE mutex_ = nullptr;
  bool primary_ = false;
  bool forwarded_ = false;
};

class WindowsShellController {
 public:
  WindowsShellController(HWND window, flutter::FlutterEngine* engine);
  ~WindowsShellController();
  std::optional<LRESULT> HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
