#ifndef RUNNER_PALETTE_TASK_RUNNER_H_
#define RUNNER_PALETTE_TASK_RUNNER_H_

#include <windows.h>
#include <objbase.h>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>

namespace desktop_lyric_runner {
// A lazy platform thread: engine construction, its message loop and destruction
// use this same thread. Post never waits for engine startup or a window reply.
class PaletteTaskRunner {
 public:
  using Task = std::function<void()>;
  void Post(Task task) {
    std::lock_guard<std::mutex> guard(mutex_);
    if (!state_) {
      state_ = std::make_shared<State>();
      auto state = state_;
      std::thread([state] { Loop(state); }).detach();
    }
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->tasks.push_back(std::move(task));
    if (state_->thread) PostThreadMessage(state_->thread, kRun, 0, 0);
  }
  // Called after the engine has been destroyed, on its platform thread. A
  // subsequent open lazily starts a fresh thread; no idle engine is retained.
  void Retire() {
    std::lock_guard<std::mutex> guard(mutex_);
    if (state_) {
      std::lock_guard<std::mutex> lock(state_->mutex);
      // Requests already queued (e.g. immediate reopen) retain this thread.
      if (!state_->tasks.empty()) return;
      state_->stopping = true;
      state_.reset();
      PostQuitMessage(0);
    }
  }
 private:
  static constexpr UINT kRun = WM_APP + 96;
  struct State {
    std::mutex mutex;
    std::deque<Task> tasks;
    DWORD thread = 0;
    bool stopping = false;
  };
  static void Loop(const std::shared_ptr<State>& state) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    MSG message{};
    PeekMessage(&message, nullptr, WM_USER, WM_USER, PM_NOREMOVE);
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      state->thread = GetCurrentThreadId();
      PostThreadMessage(state->thread, kRun, 0, 0);
    }
    while (GetMessage(&message, nullptr, 0, 0) > 0) {
      if (message.message == kRun && !message.hwnd) {
        for (;;) {
          Task task;
          {
            std::lock_guard<std::mutex> lock(state->mutex);
            if (state->tasks.empty() || state->stopping) break;
            task = std::move(state->tasks.front());
            state->tasks.pop_front();
          }
          task();
        }
      } else {
        TranslateMessage(&message);
        DispatchMessage(&message);
      }
    }
    CoUninitialize();
  }
  std::mutex mutex_;
  std::shared_ptr<State> state_;
};
}  // namespace desktop_lyric_runner
#endif
