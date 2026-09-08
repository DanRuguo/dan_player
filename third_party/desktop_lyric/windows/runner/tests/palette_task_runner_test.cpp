// No visible HWND, Flutter engine, music, app profile or shell interaction.
// Exercises the exact production message runner with an intentionally slow
// cold-start task: the owner must keep servicing messages and never join it.
#include "../palette_task_runner.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <stdexcept>

using namespace desktop_lyric_runner;
namespace {
unsigned owner_ticks = 0;
void CALLBACK Tick(HWND, UINT, UINT_PTR, DWORD) { ++owner_ticks; }
void Require(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
template <class Predicate> void PumpUntil(Predicate done) {
  const auto deadline = GetTickCount64() + 3000;
  MSG message{};
  while (!done()) {
    Require(GetTickCount64() < deadline, "worker timeout");
    while (PeekMessage(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessage(&message);
    }
    Sleep(1);
  }
}
}

int main() {
  try {
    PaletteTaskRunner runner;
    const DWORD owner = GetCurrentThreadId();
    std::atomic<DWORD> created{0}, destroyed{0};
    std::atomic<bool> started{false}, ready{false}, retired{false};
    const HANDLE cold_gate = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    Require(cold_gate != nullptr, "cold gate unavailable");
    const auto before = GetTickCount64();
    runner.Post([&] {
      created = GetCurrentThreadId();
      started = true;
      WaitForSingleObject(cold_gate, 2000);
      Sleep(240); // models synchronous engine initialization on its platform thread
      ready = true;
    });
    Require(GetTickCount64() - before < 100, "open waited for cold startup");
    PumpUntil([&] { return started.load(); });
    const auto cold_started = GetTickCount64();
    const auto timer = SetTimer(nullptr, 0, 10, Tick);
    Require(timer != 0, "owner timer unavailable");
    SetEvent(cold_gate);
    PumpUntil([&] { return ready.load(); });
    KillTimer(nullptr, timer);
    CloseHandle(cold_gate);
    std::printf("cold owner WM_TIMER messages=%u\n", owner_ticks);
    Require(owner_ticks >= 3, "owner did not keep running during startup");
    Require(created != owner, "engine task ran on owner thread");
    runner.Post([&] {
      destroyed = GetCurrentThreadId();
      runner.Retire();
      retired = true;
    });
    PumpUntil([&] { return retired.load(); });
    Require(created == destroyed, "engine teardown changed platform threads");

    // Cache expiry and an immediate subsequent open can retire/recreate without
    // blocking the owner or losing queued work. Thread IDs may be OS-reused.
    std::atomic<int> order{0};
    std::atomic<bool> closed{false};
    runner.Post([&] { order.fetch_add(1); });
    runner.Post([&] { order.fetch_add(1); });
    runner.Post([&] {
      Require(order == 2, "queued open/close order changed");
      runner.Retire();
      closed = true;
    });
    PumpUntil([&] { return closed.load(); });
    std::printf("PASS: cold startup %llums; owner ticks=%u; create/destroy same worker; retirement/reopen FIFO\n",
      static_cast<unsigned long long>(GetTickCount64() - cold_started), owner_ticks);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "FAIL: %s\n", error.what());
    return 1;
  }
}
