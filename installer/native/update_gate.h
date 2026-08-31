#pragma once

#include "installer_core.h"

namespace dan::installer {
// Read-only authorization/wait state. It never closes a process, writes an
// installation path, or treats a disappeared/reused PID as initial approval.
class UpdateGate final {
 public:
  UpdateGate(const fs::path& target, const fs::path& manifest,
             const std::wstring& version, const std::wstring& parent_pid,
             const std::wstring& ready_event);
  ~UpdateGate();
  UpdateGate(const UpdateGate&) = delete;
  UpdateGate& operator=(const UpdateGate&) = delete;
  // 0 waiting, 1 normally exited, 2 parent timeout, 3 expired handoff.
  int Poll(uint64_t timeout_ms = 30000);
  void Retry();
  void RequireReady(const fs::path& target, const fs::path& manifest);

 private:
  fs::path target_, manifest_;
  std::string manifest_hash_, parent_hash_;
  HANDLE parent_ = nullptr;
  HANDLE accepted_ = nullptr;
  HANDLE image_ = INVALID_HANDLE_VALUE;
  uint64_t started_ = 0;
  bool handoff_expired_ = false;
};
}  // namespace dan::installer
