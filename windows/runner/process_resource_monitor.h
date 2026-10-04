#ifndef RUNNER_PROCESS_RESOURCE_MONITOR_H_
#define RUNNER_PROCESS_RESOURCE_MONITOR_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace process_resources {
struct Sample {
  std::optional<double> cpu_percent;
  std::optional<double> gpu_percent;
  std::optional<int64_t> working_set_bytes;
  std::string cpu_status = "unavailable";
  std::string gpu_status = "unavailable";
};
bool IsGpuInstanceForProcess(const std::wstring& instance, DWORD pid);
std::optional<double> BusiestEngine(const std::vector<double>& values);

// Used on one worker only. No counter/query/thread is created by construction.
class Sampler {
 public:
  Sampler() = default;
  ~Sampler();
  Sample Read();
  void Reset();
 private:
  bool gpu_attempted_ = false, gpu_warm_ = false;
  PDH_HQUERY query_ = nullptr;
  PDH_HCOUNTER counter_ = nullptr;
  uint64_t cpu_time_ = 0;
  LONGLONG wall_time_ = 0;
};
}  // namespace process_resources

#ifndef DAN_PLAYER_RESOURCE_SAMPLER_ONLY
namespace flutter { class FlutterEngine; }
// Owns the independent dan_player/process_resources channel. All Flutter
// callbacks are relayed through a UI-thread message-only window. PDH never runs
// on that thread. Stop acknowledges after the worker has released its query.
class ProcessResourceMonitorController {
 public:
  explicit ProcessResourceMonitorController(flutter::FlutterEngine* engine);
  ~ProcessResourceMonitorController();
  void Dispose();
 private:
  struct Impl;
  std::shared_ptr<Impl> impl_;
};
#endif
#endif
