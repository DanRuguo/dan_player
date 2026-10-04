#include "../process_resource_monitor.h"
#include <iostream>

// Focused contract for compact monitor RAM percentages. Other sampler behavior
// is exercised by process_resource_monitor_test.
int main() {
  MEMORYSTATUSEX physical{};
  physical.dwLength = sizeof(physical);
  if (!GlobalMemoryStatusEx(&physical) || physical.ullTotalPhys == 0) return 1;
  process_resources::Sampler sampler;
  for (int index = 0; index < 2; ++index) {
    const auto sample = sampler.Read();
    if (!sample.total_physical_memory_bytes ||
        static_cast<ULONGLONG>(*sample.total_physical_memory_bytes) != physical.ullTotalPhys ||
        !sample.working_set_bytes || *sample.working_set_bytes <= 0 ||
        *sample.working_set_bytes > *sample.total_physical_memory_bytes) return 2;
    const double percent = 100.0 * *sample.working_set_bytes /
        *sample.total_physical_memory_bytes;
    if (percent <= 0 || percent > 100) return 3;
    std::cout << "RAM: " << *sample.working_set_bytes << "/"
              << *sample.total_physical_memory_bytes << " = " << percent << "%\n";
  }
  std::cout << "PASS: physical RAM denominator, working set and share\n";
  return 0;
}
