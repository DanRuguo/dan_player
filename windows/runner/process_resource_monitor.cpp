#include "process_resource_monitor.h"

#include <psapi.h>
#include <algorithm>
#include <cmath>
#include <limits>

namespace process_resources {
bool IsGpuInstanceForProcess(const std::wstring& name, DWORD pid) {
  const auto prefix = L"pid_" + std::to_wstring(pid) + L"_";
  return name.size() > prefix.size() && name.compare(0, prefix.size(), prefix) == 0;
}
std::optional<double> BusiestEngine(const std::vector<double>& values) {
  std::optional<double> result;
  for (double value : values) {
    if (!std::isfinite(value) || value < 0) continue;
    value = std::min(100.0, value);
    result = result ? std::max(*result, value) : value;
  }
  return result;
}
static uint64_t FileTimeValue(FILETIME value) {
  return (static_cast<uint64_t>(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
Sampler::~Sampler() { Reset(); }
void Sampler::Reset() {
  if (query_) PdhCloseQuery(query_);
  query_ = nullptr; counter_ = nullptr;
  gpu_attempted_ = gpu_warm_ = false;
  cpu_time_ = 0; wall_time_ = 0;
}
Sample Sampler::Read() {
  Sample sample;
  FILETIME creation{}, exit{}, kernel{}, user{};
  LARGE_INTEGER now{}, frequency{};
  if (GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user) &&
      QueryPerformanceCounter(&now) && QueryPerformanceFrequency(&frequency)) {
    const uint64_t cpu = FileTimeValue(kernel) + FileTimeValue(user);
    const auto cores = std::max<DWORD>(1, GetActiveProcessorCount(ALL_PROCESSOR_GROUPS));
    if (wall_time_ && now.QuadPart > wall_time_ && cpu >= cpu_time_) {
      const double seconds = static_cast<double>(now.QuadPart - wall_time_) / frequency.QuadPart;
      sample.cpu_percent = std::clamp((cpu - cpu_time_) / 100000.0 / seconds / cores, 0.0, 100.0);
      sample.cpu_status = "ready";
    } else {
      sample.cpu_status = "warming";
    }
    cpu_time_ = cpu; wall_time_ = now.QuadPart;
  }
  PROCESS_MEMORY_COUNTERS_EX memory{};
  memory.cb = sizeof(memory);
  if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory))) {
    sample.working_set_bytes = static_cast<int64_t>(memory.WorkingSetSize);
  }
  if (!gpu_attempted_) {
    gpu_attempted_ = true;
    if (PdhOpenQueryW(nullptr, 0, &query_) != ERROR_SUCCESS ||
        PdhAddEnglishCounterW(query_, L"\\GPU Engine(*)\\Utilization Percentage", 0, &counter_) != ERROR_SUCCESS) {
      if (query_) PdhCloseQuery(query_);
      query_ = nullptr; counter_ = nullptr;
    }
  }
  if (!query_ || !counter_) return sample;
  if (PdhCollectQueryData(query_) != ERROR_SUCCESS) return sample;
  if (!gpu_warm_) {
    gpu_warm_ = true; sample.gpu_status = "warming"; return sample;
  }
  // Instances can change between sizing and reading. Bound both allocation and
  // retries; a transient provider change reports unavailable, never fake zero.
  DWORD bytes = 0, count = 0;
  std::vector<BYTE> buffer;
  PDH_STATUS status = PDH_MORE_DATA;
  for (int attempt = 0; attempt < 3 && status == PDH_MORE_DATA; ++attempt) {
    status = PdhGetFormattedCounterArrayW(counter_, PDH_FMT_DOUBLE, &bytes, &count,
        buffer.empty() ? nullptr : reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data()));
    if (status == PDH_MORE_DATA) {
      if (!bytes || bytes > 16 * 1024 * 1024) return sample;
      buffer.resize(bytes);
    }
  }
  if (status != ERROR_SUCCESS || count > buffer.size() / sizeof(PDH_FMT_COUNTERVALUE_ITEM_W)) return sample;
  const auto items = reinterpret_cast<const PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer.data());
  std::vector<double> values;
  for (DWORD index = 0; index < count; ++index) {
    const auto& item = items[index];
    if (item.FmtValue.CStatus != PDH_CSTATUS_VALID_DATA && item.FmtValue.CStatus != PDH_CSTATUS_NEW_DATA) continue;
    if (item.szName && IsGpuInstanceForProcess(item.szName, GetCurrentProcessId())) values.push_back(item.FmtValue.doubleValue);
  }
  sample.gpu_percent = BusiestEngine(values);
  if (sample.gpu_percent) sample.gpu_status = "ready";
  return sample;
}
}  // namespace process_resources

#ifndef DAN_PLAYER_RESOURCE_SAMPLER_ONLY
#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
constexpr UINT kSample = WM_APP + 51, kStopped = WM_APP + 52;
constexpr wchar_t kWindowClass[] = L"DanPlayerProcessResourceRelay";
std::optional<int64_t> Integer(const Map& map, const char* key) {
  auto found = map.find(Value(key));
  if (found == map.end()) return std::nullopt;
  if (auto value = std::get_if<int32_t>(&found->second)) return *value;
  if (auto value = std::get_if<int64_t>(&found->second)) return *value;
  return std::nullopt;
}
}
struct ProcessResourceMonitorController::Impl {
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  std::unique_ptr<flutter::MethodResult<Value>> stop_result;
  std::thread worker;
  std::mutex mutex;
  std::condition_variable wake;
  HWND relay = nullptr;
  bool disposed = false, active = false, cancel = false, sample_pending = false;
  int interval = 5;
  int64_t session = 0;
  process_resources::Sample latest;

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto self = reinterpret_cast<Impl*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if (self && message == kSample) { self->Publish(); return 0; }
    if (self && message == kStopped) { self->Stopped(); return 0; }
    return DefWindowProcW(window, message, wparam, lparam);
  }
  bool CreateRelay() {
    WNDCLASSW cls{}; cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpfnWndProc = WindowProc; cls.lpszClassName = kWindowClass;
    if (!RegisterClassW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
    relay = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, cls.hInstance, this);
    return relay != nullptr;
  }
  void Publish() {
    process_resources::Sample value;
    { std::lock_guard<std::mutex> lock(mutex); value = latest; sample_pending = false; }
    if (!active || disposed || !channel) return;
    Map map{{Value("session"), Value(session)},
      {Value("cpuPercent"), value.cpu_percent ? Value(*value.cpu_percent) : Value()},
      {Value("cpuStatus"), Value(value.cpu_status)},
      {Value("gpuPercent"), value.gpu_percent ? Value(*value.gpu_percent) : Value()},
      {Value("workingSetBytes"), value.working_set_bytes ? Value(*value.working_set_bytes) : Value()},
      {Value("gpuStatus"), Value(value.gpu_status)}};
    channel->InvokeMethod("sample", std::make_unique<Value>(map));
  }
  void Stopped() {
    if (worker.joinable()) worker.join(); // Worker posts only after releasing PDH.
    if (relay) { DestroyWindow(relay); relay = nullptr; }
    if (stop_result) { stop_result->Success(); stop_result.reset(); }
  }
  void Stop() {
    active = false;
    { std::lock_guard<std::mutex> lock(mutex); cancel = true; }
    wake.notify_one();
  }
  void Run() {
    {
      process_resources::Sampler sampler;
      while (true) {
        { std::lock_guard<std::mutex> lock(mutex); if (cancel) break; }
        auto sample = sampler.Read();
        std::unique_lock<std::mutex> lock(mutex);
        if (cancel) break;
        latest = sample;
        if (!sample_pending) sample_pending = PostMessageW(relay, kSample, 0, 0) != FALSE;
        if (wake.wait_for(lock, std::chrono::seconds(interval), [&] { return cancel; })) break;
      }
    }
    PostMessageW(relay, kStopped, 0, 0);
  }
  void Handle(const flutter::MethodCall<Value>& call, std::unique_ptr<flutter::MethodResult<Value>> result) {
    if (disposed) { result->Error("DISPOSED", "Resource monitor is closed"); return; }
    const auto args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    const auto id = args ? Integer(*args, "session") : std::nullopt;
    if (!id || *id <= 0) { result->Error("INVALID_ARGUMENT", "A positive session is required"); return; }
    if (call.method_name() == "stop") {
      // A stale stop never tears down a newer presentation.
      if (*id != session || !worker.joinable()) { result->Success(); return; }
      if (stop_result) { result->Error("BUSY", "Stop is already pending"); return; }
      stop_result = std::move(result); Stop(); return;
    }
    if (call.method_name() != "start") { result->NotImplemented(); return; }
    const auto period = Integer(*args, "intervalSeconds");
    if (!period || (*period != 1 && *period != 5 && *period != 10)) {
      result->Error("INVALID_ARGUMENT", "Interval must be 1, 5 or 10 seconds"); return;
    }
    if (worker.joinable()) { result->Error("BUSY", "Previous session is still active"); return; }
    if (!CreateRelay()) { result->Error("UNAVAILABLE", "Cannot create resource relay"); return; }
    interval = static_cast<int>(*period); session = *id;
    active = true; cancel = false; sample_pending = false;
    try { worker = std::thread([this] { Run(); }); }
    catch (const std::system_error&) {
      active = false; DestroyWindow(relay); relay = nullptr;
      result->Error("UNAVAILABLE", "Cannot start resource worker"); return;
    }
    result->Success();
  }
  void Dispose() {
    if (disposed) return;
    disposed = true;
    if (channel) channel->SetMethodCallHandler(nullptr);
    Stop();
    if (worker.joinable()) worker.join();
    if (relay) { DestroyWindow(relay); relay = nullptr; }
    if (stop_result) { stop_result->Error("DISPOSED", "Resource monitor is closed"); stop_result.reset(); }
    channel.reset();
  }
};
ProcessResourceMonitorController::ProcessResourceMonitorController(flutter::FlutterEngine* engine)
    : impl_(std::make_shared<Impl>()) {
  impl_->channel = std::make_unique<flutter::MethodChannel<Value>>(engine->messenger(),
      "dan_player/process_resources", &flutter::StandardMethodCodec::GetInstance());
  const std::weak_ptr<Impl> weak = impl_;
  impl_->channel->SetMethodCallHandler([weak](const auto& call, auto result) {
    if (auto self = weak.lock()) self->Handle(call, std::move(result));
    else result->Error("DISPOSED", "Resource monitor is closed");
  });
}
ProcessResourceMonitorController::~ProcessResourceMonitorController() { Dispose(); }
void ProcessResourceMonitorController::Dispose() { if (impl_) impl_->Dispose(); }
#endif
