#include "installer_launcher.h"

#include "installer_launch_core.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <process.h>

#include <mutex>
#include <new>
#include <optional>
#include <utility>

namespace {

using Result = flutter::MethodResult<flutter::EncodableValue>;
constexpr UINT kCompleted = WM_APP + 1;
constexpr UINT_PTR kCompletionPoll = 1;
constexpr wchar_t kDispatcherClass[] = L"DanPlayer.InstallerLauncher.Dispatcher";

std::wstring Wide(const std::string& value) {
  if (value.empty() || value.size() > 128000) return L"";
  const auto size = static_cast<int>(value.size());
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(), size, nullptr, 0);
  if (!count) return L"";
  std::wstring output(count, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(), size,
                           output.data(), count)) return L"";
  return output;
}

const std::string* String(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found == map.end() ? nullptr : std::get_if<std::string>(&found->second);
}

struct State : std::enable_shared_from_this<State> {
  std::mutex mutex;
  HWND window = nullptr;
  HANDLE cancelled = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  bool disposed = false;
  bool launched = false;
  std::unique_ptr<Result> pending;
  std::optional<installer_launch::Outcome> completed;

  ~State() { if (cancelled) CloseHandle(cancelled); }

  void Complete(installer_launch::Outcome outcome) {
    std::lock_guard<std::mutex> lock(mutex);
    if (disposed || !window) return;
    completed = std::move(outcome);
    // Posting while holding the mutex excludes destroy/reuse of this HWND.
    // The worker never touches Flutter's messenger or MethodResult.
    PostMessageW(window, kCompleted, 0, 0);
  }

  static LRESULT CALLBACK WindowProc(HWND window, UINT message,
                                     WPARAM wparam, LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* state = reinterpret_cast<State*>(GetWindowLongPtrW(window, GWLP_USERDATA));
    if ((message == kCompleted ||
         (message == WM_TIMER && wparam == kCompletionPoll)) && state) {
      const auto keep_alive = state->shared_from_this();
      std::unique_ptr<Result> result;
      installer_launch::Outcome outcome;
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (state->disposed || !state->completed || !state->pending) return 0;
        outcome = std::move(*state->completed);
        state->completed.reset();
        state->launched = outcome.ok();
        result = std::move(state->pending);
      }
      KillTimer(window, kCompletionPoll);
      if (outcome.ok()) {
        result->Success(flutter::EncodableValue(true));
      } else {
        result->Error(outcome.code, outcome.message,
            flutter::EncodableValue(static_cast<int64_t>(outcome.detail)));
      }
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }
};

struct Job {
  std::shared_ptr<State> state;
  installer_launch::Request request;

  static unsigned __stdcall Run(void* pointer) {
    std::unique_ptr<Job> job(static_cast<Job*>(pointer));
    job->state->Complete(installer_launch::Launch(job->request,
                                                job->state->cancelled));
    return 0;
  }
};

}  // namespace

struct InstallerLauncherController::Impl {
  std::shared_ptr<State> state = std::make_shared<State>();
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;

  explicit Impl(flutter::FlutterEngine* engine) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = State::WindowProc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = kDispatcherClass;
    const auto registered = RegisterClassW(&window_class);
    if (registered || GetLastError() == ERROR_CLASS_ALREADY_EXISTS) {
      state->window = CreateWindowExW(0, kDispatcherClass, L"", 0,
          0, 0, 0, 0, HWND_MESSAGE, nullptr, window_class.hInstance, state.get());
    }
    channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        engine->messenger(), "dan_player/installer_launcher",
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler([weak = std::weak_ptr<State>(state)](
        const auto& call, std::unique_ptr<Result> result) {
      if (call.method_name() != "launchForUpdate") {
        result->NotImplemented();
        return;
      }
      auto shared = weak.lock();
      if (!shared || !shared->window || !shared->cancelled) {
        result->Error("launcher_unavailable", "The Windows launcher is unavailable.");
        return;
      }
      const auto* map = call.arguments()
          ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      const auto* path = map ? String(*map, "path") : nullptr;
      const auto* hash = map ? String(*map, "sha256") : nullptr;
      const auto* version = map ? String(*map, "version") : nullptr;
      if (!map || map->size() != 3 || !path || !hash || !version) {
        result->Error("invalid_request", "Only installer path, SHA-256 and version are accepted.");
        return;
      }
      installer_launch::Request request{Wide(*path), *hash, Wide(*version)};
      if (!installer_launch::ValidRequest(request)) {
        result->Error("invalid_request", "Invalid installer request.");
        return;
      }
      bool busy = false;
      {
        std::lock_guard<std::mutex> lock(shared->mutex);
        busy = shared->disposed || shared->pending || shared->launched;
      }
      if (busy) {
        result->Error("launch_busy", "An installer launch is already in progress.");
        return;
      }
      // A low-frequency, active-job-only fallback also delivers completion if
      // PostMessage encounters the thread queue quota. No idle polling/ticker.
      if (!SetTimer(shared->window, kCompletionPoll, 100, nullptr)) {
        result->Error("launcher_unavailable", "The Windows result dispatcher is unavailable.");
        return;
      }
      {
        std::lock_guard<std::mutex> lock(shared->mutex);
        shared->pending = std::move(result);
      }
      auto* job = new (std::nothrow) Job{shared, std::move(request)};
      const auto thread = job ? _beginthreadex(nullptr, 0, Job::Run, job, 0, nullptr) : 0;
      if (!thread) {
        delete job;
        shared->Complete({"launch_worker_failed", "The installer verification worker could not start."});
      } else {
        CloseHandle(reinterpret_cast<HANDLE>(thread));
      }
    });
  }

  ~Impl() {
    channel->SetMethodCallHandler(nullptr);
    HWND window = nullptr;
    std::unique_ptr<Result> abandoned;
    {
      std::lock_guard<std::mutex> lock(state->mutex);
      state->disposed = true;
      if (state->cancelled) SetEvent(state->cancelled);
      window = std::exchange(state->window, nullptr);
      // Discard on the platform thread before the Flutter engine is destroyed.
      abandoned = std::move(state->pending);
      state->completed.reset();
    }
    if (window) DestroyWindow(window);
    abandoned.reset();
  }
};

InstallerLauncherController::InstallerLauncherController(flutter::FlutterEngine* engine)
    : impl_(std::make_unique<Impl>(engine)) {}

InstallerLauncherController::~InstallerLauncherController() = default;
