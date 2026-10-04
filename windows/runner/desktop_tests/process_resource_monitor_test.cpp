#include "../process_resource_monitor.h"
#include <cmath>
#include <iostream>
#include <limits>
#include <thread>
#include <chrono>

int main() {
  using namespace process_resources;
  int checks = 0;
  const auto require = [&](bool condition, const char* label) {
    ++checks;
    if (!condition) { std::cerr << "FAIL " << label << std::endl; std::exit(1); }
  };
  require(IsGpuInstanceForProcess(L"pid_123_luid_0x01_eng_0_engtype_3D", 123), "exact PID accepted");
  require(!IsGpuInstanceForProcess(L"pid_1234_luid_0x01_eng_0", 123), "PID prefix collision rejected");
  require(!IsGpuInstanceForProcess(L"pid_12_luid_0x01_eng_0", 123), "shorter PID rejected");
  require(!IsGpuInstanceForProcess(L"other_pid_123_luid_0x01", 123), "embedded PID rejected");
  require(BusiestEngine({25, 70, 60}) == 70, "busiest engine, no sum");
  require(BusiestEngine({0}) == 0, "actual idle zero preserved");
  require(!BusiestEngine({-1, std::numeric_limits<double>::quiet_NaN(), std::numeric_limits<double>::infinity()}), "invalid is unavailable");
  require(BusiestEngine({101}) == 100, "provider percent bounded");
  Sampler sampler;
  const auto start = std::chrono::steady_clock::now();
  const auto first = sampler.Read();
  const auto first_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now()-start).count();
  require(!first.cpu_percent, "CPU baseline is not fabricated zero");
  require(first.working_set_bytes && *first.working_set_bytes > 0, "actual process working set");
  std::this_thread::sleep_for(std::chrono::milliseconds(220));
  const auto idle = sampler.Read();
  require(idle.cpu_percent && std::isfinite(*idle.cpu_percent), "actual CPU interval");
  volatile double result = 0;
  const auto busy_start = std::chrono::steady_clock::now();
  while (std::chrono::steady_clock::now()-busy_start < std::chrono::milliseconds(500)) {
    for(int i=1;i<10000;++i) result = result + std::sqrt(static_cast<double>(i));
  }
  const auto busy = sampler.Read();
  require(busy.cpu_percent && *busy.cpu_percent > *idle.cpu_percent && *busy.cpu_percent > 0, "generated CPU load measured");
  constexpr size_t allocation = 32 * 1024 * 1024;
  auto memory = static_cast<BYTE*>(VirtualAlloc(nullptr, allocation, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE));
  require(memory != nullptr, "private fixture allocation");
  for(size_t offset=0; offset<allocation; offset+=4096) memory[offset]=1;
  const auto allocated = sampler.Read();
  require(allocated.working_set_bytes && *allocated.working_set_bytes > *busy.working_set_bytes + 20*1024*1024, "committed touched pages affect working set");
  VirtualFree(memory, 0, MEM_RELEASE);
  require(!busy.gpu_percent || (*busy.gpu_percent>=0 && *busy.gpu_percent<=100), "GPU real sample bounded or unavailable");
  if (!busy.gpu_percent) require(busy.gpu_status == "unavailable", "GPU absence is explicit unavailable");
  sampler.Reset();
  require(!sampler.Read().cpu_percent, "reset drops CPU baseline");
  std::cout << "PASS " << checks << " checks; first PDH/read=" << first_ms << "ms; idleCPU=" << *idle.cpu_percent
    << "; busyCPU=" << *busy.cpu_percent << "; memory=" << *busy.working_set_bytes << "->" << *allocated.working_set_bytes
    << "; GPU=" << (busy.gpu_percent ? std::to_string(*busy.gpu_percent) : busy.gpu_status) << std::endl;
}
