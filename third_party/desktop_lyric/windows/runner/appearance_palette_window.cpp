#include "appearance_palette_window.h"
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/standard_message_codec.h>
#include <flutter_windows.h>
#include <algorithm>
#include <optional>
#include <utility>
#include <chrono>
#include <cstdio>
#include "palette_window_shape.h"

namespace desktop_lyric_runner {

namespace {
using Value = flutter::EncodableValue;
const Value* Field(const Value* value, const char* name) {
  const auto* map = value ? std::get_if<flutter::EncodableMap>(value) : nullptr;
  if (!map) return nullptr;
  auto found = map->find(Value(name));
  return found == map->end() ? nullptr : &found->second;
}
int64_t Integer(const Value* value) {
  if (!value) return 0;
  if (const auto* small_value = std::get_if<int32_t>(value)) return *small_value;
  if (const auto* large_value = std::get_if<int64_t>(value)) return *large_value;
  return 0;
}
bool Alive(const std::weak_ptr<bool>& weak) {
  const auto alive = weak.lock();
  return alive && *alive;
}
std::wstring PaletteTitle(const Value& snapshot) {
  const auto* language_value = Field(&snapshot, "language");
  const auto* language = language_value ? std::get_if<std::string>(language_value) : nullptr;
  if (language && *language == "en") return L"Lyric appearance";
  if (language && *language == "ja") return L"\u6b4c\u8a5e\u306e\u5916\u89b3";
  if (language && *language == "ko") return L"\uac00\uc0ac \ubaa8\uc591";
  return L"\u6b4c\u8bcd\u5916\u89c2";
}
std::string SnapshotArgument(const Value& snapshot) {
  const auto bytes = flutter::StandardMessageCodec::GetInstance().EncodeMessage(snapshot);
  constexpr char hex[] = "0123456789abcdef";
  std::string argument;
  argument.reserve(bytes->size() * 2);
  for (const auto byte : *bytes) {
    argument.push_back(hex[byte >> 4]);
    argument.push_back(hex[byte & 15]);
  }
  return argument;
}
std::optional<RECT> PaletteBounds(HWND owner) {
  RECT parent{};
  if (!GetWindowRect(owner, &parent)) return std::nullopt;
  HMONITOR monitor = MonitorFromWindow(owner, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  if (!monitor || !GetMonitorInfo(monitor, &info)) return std::nullopt;
  const RECT area = info.rcWork;
  const double ratio = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  if (ratio <= 0 || area.right <= area.left || area.bottom <= area.top) {
    return std::nullopt;
  }
  const LONG width = std::min(static_cast<LONG>(400 * ratio), area.right - area.left);
  const LONG height = std::min(static_cast<LONG>(520 * ratio), area.bottom - area.top);
  const LONG left = std::clamp(parent.left + (parent.right - parent.left - width) / 2,
                               area.left, area.right - width);
  const LONG top = std::clamp(parent.top + (parent.bottom - parent.top - height) / 2,
                              area.top, area.bottom - height);
  return RECT{left, top, left + width, top + height};
}
}  // namespace

AppearancePaletteWindow::AppearancePaletteWindow(
    const flutter::DartProject& project, HWND owner, int64_t session,
    const Value& snapshot, Handler handler)
    : project_(project), owner_(owner), session_(session), handler_(std::move(handler)) {
  project_.set_dart_entrypoint("desktopLyricAppearanceMain");
  // Seed the first frame without a pre-runApp engine/owner/engine round trip.
  // This payload contains UI preferences only, never song or file data.
  project_.set_dart_entrypoint_arguments({SnapshotArgument(snapshot)});
  SetQuitOnClose(false);
}

AppearancePaletteWindow::~AppearancePaletteWindow() { Destroy(); }

bool AppearancePaletteWindow::OnCreate() {
  if (!IsWindow(owner_) || !IsWindow(GetHandle())) return false;
  *alive_ = true;
  UpdateRoundedRegion();
  const RECT frame = GetClientArea();
  const auto engine_started = std::chrono::steady_clock::now();
  controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - engine_started).count();
  std::fprintf(stderr, "[palette] engine initialization=%lldms platform_thread=%lu owner_thread=%lu\n",
      static_cast<long long>(elapsed), GetCurrentThreadId(),
      GetWindowThreadProcessId(owner_, nullptr));
  if (!*alive_ || !IsWindow(owner_) || !IsWindow(GetHandle()) ||
      !controller_->engine() || !controller_->view()) {
    controller_.reset();
    return false;
  }
  // No RegisterPlugins here: the palette needs no window_manager, audio,
  // screen, file or global-HWND plugins. Its only native API is this channel.
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      controller_->engine()->messenger(), "dan_player/desktop_lyric_palette_child",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(handler_);
  frame_display_ = std::make_unique<FrameDisplayChannel>(GetHandle(), controller_->engine()->messenger());
  SetChildContent(controller_->view()->GetNativeWindow(), false);
  if (!*alive_ || !controller_ || !IsWindow(GetHandle()) || !IsWindow(owner_)) return false;
  RequestFreshFrame(session_);
  return true;
}

void AppearancePaletteWindow::RequestFreshFrame(int64_t session) {
  if (!controller_ || !IsWindow(GetHandle())) return;
  const HWND owner = owner_;
  const auto weak = lifetime();
  controller_->engine()->SetNextFrameCallback([owner, session, weak]() {
    if (Alive(weak) && IsWindow(owner)) {
      PostMessage(owner, kPaletteShownMessage, static_cast<WPARAM>(session), 0);
    }
  });
  if (!Alive(weak) || !controller_ || !IsWindow(GetHandle())) return;
  controller_->ForceRedraw();
}

void AppearancePaletteWindow::UpdateRoundedRegion() {
  const auto monitor = MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST);
  ApplyPaletteRoundedRegion(GetHandle(), FlutterDesktopGetDpiForMonitor(monitor));
}

void AppearancePaletteWindow::Present(int64_t session, const Value& snapshot,
                                      const RECT& bounds) {
  const bool new_session = session != session_;
  session_ = session;
  const auto weak = lifetime();
  SetWindowText(GetHandle(), PaletteTitle(snapshot).c_str());
  SetWindowPos(GetHandle(), nullptr, bounds.left, bounds.top,
      bounds.right - bounds.left, bounds.bottom - bounds.top,
      SWP_NOACTIVATE | SWP_NOZORDER);
  if (!Alive(weak) || !channel_) return;
  // Wait for Dart to lay out the new authoritative session/theme, then raster
  // a fresh frame. Showing the previous cached frame would flash old colors.
  auto response = std::make_unique<flutter::MethodResultFunctions<Value>>(
      [this, weak, session](const Value*) {
        if (Alive(weak) && session == session_) RequestFreshFrame(session);
      },
      [owner = owner_, weak, session](const std::string&, const std::string&, const Value*) {
        if (Alive(weak) && IsWindow(owner)) PostMessage(owner, kPaletteCloseMessage,
                                                       static_cast<WPARAM>(session), 0);
      },
      [owner = owner_, weak, session]() {
        if (Alive(weak) && IsWindow(owner)) PostMessage(owner, kPaletteCloseMessage,
                                                       static_cast<WPARAM>(session), 0);
      });
  channel_->InvokeMethod(new_session ? "present" : "refresh",
                         std::make_unique<Value>(snapshot), std::move(response));
}

void AppearancePaletteWindow::Suspend() {
  const auto weak = lifetime();
  ShowWindow(GetHandle(), SW_HIDE);
  if (Alive(weak) && channel_) {
    channel_->InvokeMethod("suspend", std::make_unique<Value>(session_));
  }
}

void AppearancePaletteWindow::ShowFirstFrame() {
  if (!controller_ || !GetHandle()) return;
  const HWND window = GetHandle();
  const HWND content = controller_->view()->GetNativeWindow();
  const auto weak = lifetime();
  ShowWindow(window, SW_SHOWNORMAL);
  if (!Alive(weak) || !IsWindow(window)) return;
  SetForegroundWindow(window);
  if (!Alive(weak) || !IsWindow(content)) return;
  SetFocus(content);
}

void AppearancePaletteWindow::Update(const Value& snapshot) {
  if (GetHandle()) SetWindowText(GetHandle(), PaletteTitle(snapshot).c_str());
  if (channel_) channel_->InvokeMethod("snapshot", std::make_unique<Value>(snapshot));
}

void AppearancePaletteWindow::OnDestroy() {
  *alive_ = false;
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
  frame_display_.reset();
  controller_.reset();
  Win32Window::OnDestroy();
}

LRESULT AppearancePaletteWindow::MessageHandler(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (frame_display_) frame_display_->Handle(message);
  if (message == WM_CLOSE) {
    // Ask Dart to flush a last slider edit first. The visible close button and
    // Escape use the same path. Destruction itself is always owner-queued.
    if (channel_) channel_->InvokeMethod("requestClose", nullptr);
    return 0;
  }
  if (message == WM_DESTROY && IsWindow(owner_)) {
    PostMessage(owner_, kPaletteCloseMessage, static_cast<WPARAM>(session_), 0);
  }
  if (message == WM_SIZE || message == WM_DPICHANGED) {
    const auto handled = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
    UpdateRoundedRegion();
    if (controller_) controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    return handled;
  }
  if (controller_) {
    auto handled = controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (handled) return *handled;
    if (message == WM_FONTCHANGE) controller_->engine()->ReloadSystemFonts();
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

PaletteWindowManager::PaletteWindowManager(HWND owner,
    flutter::BinaryMessenger* messenger, const flutter::DartProject& project)
    : owner_(owner), project_(project) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(messenger,
      "dan_player/desktop_lyric_palette", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    auto keep_alive = shared_from_this();
    auto name = call.method_name();
    auto args = call.arguments() ? std::make_shared<Value>(*call.arguments()) : nullptr;
    auto reply = OwnerReply(std::shared_ptr<Result>(std::move(result)));
    OnPalette([keep_alive, name, args, reply] {
      keep_alive->Handle(flutter::MethodCall<Value>(name,
          args ? std::make_unique<Value>(*args) : nullptr), reply);
    });
  });
}

PaletteWindowManager::~PaletteWindowManager() {
  Shutdown();
}

void PaletteWindowManager::Shutdown() {
  if (shutdown_requested_.exchange(true)) return;
  KillTimer(owner_, kPaletteCacheTimer);
  KillTimer(owner_, kPaletteReadyTimer);
  channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
  {
    std::lock_guard<std::mutex> lock(owner_tasks_mutex_);
    owner_tasks_.clear();
  }
  auto self = shared_from_this();
  OnPalette([self] {
    self->closing_ = true;
    self->CloseOnPalette(self->session_, false);
    self->EvictCacheOnPalette();

  });
}

void PaletteWindowManager::OnPalette(std::function<void()> task) {
  auto self = shared_from_this();
  runner_.Post([self, task = std::move(task)] {
    task();
    // Includes failed creation, early close, stale timer/reply and cache expiry.
    // Retire only after any engine is destroyed and all queued work is drained.
    if (!self->active_ && !self->palette_) self->runner_.Retire();
  });
}

void PaletteWindowManager::OnOwner(std::function<void()> task) {
  if (shutdown_requested_) return;
  std::lock_guard<std::mutex> lock(owner_tasks_mutex_);
  if (shutdown_requested_ || !IsWindow(owner_)) return;
  owner_tasks_.push_back(std::move(task));
  if (!PostMessage(owner_, kPaletteDispatchMessage, 0, 0)) owner_tasks_.clear();
}

void PaletteWindowManager::ConfigureOwnerTimer(UINT_PTR timer, UINT milliseconds) {
  const auto session = session_;
  auto weak = weak_from_this();
  // SetTimer requires the calling thread to own the HWND. Keep all owner timer
  // creation/cancellation beside its messenger, never on the palette thread.
  OnOwner([weak, timer, milliseconds, session] {
    auto self = weak.lock();
    if (!self) return;
    if (!milliseconds) { KillTimer(self->owner_, timer); return; }
    if (SetTimer(self->owner_, timer, milliseconds, nullptr)) return;
    self->OnPalette([self, timer, session] {
      if (session != self->session_) return;
      if (timer == kPaletteCacheTimer) {
        self->EvictCacheOnPalette();
      } else if (self->pending_open_) {
        self->pending_open_->Error("timer_failed", "Could not monitor appearance startup");
        self->pending_open_.reset();
        self->CloseOnPalette(session, true);
      }
    });
  });
}

void PaletteWindowManager::DrainOwnerTasks() {
  std::deque<std::function<void()>> tasks;
  {
    std::lock_guard<std::mutex> lock(owner_tasks_mutex_);
    tasks.swap(owner_tasks_);
  }
  for (auto& task : tasks) { if (!shutdown_requested_) task(); }
}

std::shared_ptr<PaletteWindowManager::Result> PaletteWindowManager::OwnerReply(
    std::shared_ptr<Result> reply) {
  auto weak = weak_from_this();
  return std::make_shared<flutter::MethodResultFunctions<Value>>(
      [weak, reply](const Value* value) {
        auto copy = value ? std::make_shared<Value>(*value) : nullptr;
        if (auto self = weak.lock()) self->OnOwner([reply, copy] {
          if (copy) reply->Success(*copy); else reply->Success();
        });
      },
      [weak, reply](const std::string& code, const std::string& message, const Value* details) {
        auto copy = details ? std::make_shared<Value>(*details) : nullptr;
        if (auto self = weak.lock()) self->OnOwner([reply, code, message, copy] {
          if (copy) reply->Error(code, message, *copy); else reply->Error(code, message);
        });
      },
      [weak, reply] {
        if (auto self = weak.lock()) self->OnOwner([reply] { reply->NotImplemented(); });
      });
}

void PaletteWindowManager::InvokeOwner(const std::string& method,
    std::unique_ptr<Value> arguments, std::unique_ptr<Result> result) {
  auto weak = weak_from_this();
  auto args = std::shared_ptr<Value>(std::move(arguments));
  auto reply = std::shared_ptr<Result>(std::move(result));
  OnOwner([weak, method, args, reply] {
    auto self = weak.lock();
    if (!self || self->shutdown_requested_ || !self->channel_) return;
    std::unique_ptr<Result> forward;
    if (reply) forward = std::make_unique<flutter::MethodResultFunctions<Value>>(
        [weak, reply](const Value* value) {
          auto copy = value ? std::make_shared<Value>(*value) : nullptr;
          if (auto manager = weak.lock(); manager && !manager->shutdown_requested_) {
            manager->OnPalette([reply, copy] {
              if (copy) reply->Success(*copy); else reply->Success();
            });
          }
        },
        [weak, reply](const std::string& code, const std::string& message, const Value* details) {
          auto copy = details ? std::make_shared<Value>(*details) : nullptr;
          if (auto manager = weak.lock(); manager && !manager->shutdown_requested_) {
            manager->OnPalette([reply, code, message, copy] {
              if (copy) reply->Error(code, message, *copy); else reply->Error(code, message);
            });
          }
        },
        [weak, reply] {
          if (auto manager = weak.lock(); manager && !manager->shutdown_requested_) {
            manager->OnPalette([reply] { reply->NotImplemented(); });
          }
        });
    self->channel_->InvokeMethod(method, args ? std::make_unique<Value>(*args) : nullptr,
                                std::move(forward));
  });
}

void PaletteWindowManager::Close(int64_t session, bool notify) {
  auto self = shared_from_this();
  OnPalette([self, session, notify] { self->CloseOnPalette(session, notify); });
}
void PaletteWindowManager::ShowFirstFrame(int64_t session) {
  auto self = shared_from_this();
  OnPalette([self, session] { self->ShowFirstFrameOnPalette(session); });
}
void PaletteWindowManager::EvictCache() {
  auto self = shared_from_this();
  OnPalette([self] {
    if (GetTickCount64() >= self->cache_deadline_) self->EvictCacheOnPalette();

  });
}
void PaletteWindowManager::ReadyTimedOut() {
  auto self = shared_from_this();
  OnPalette([self] {
    // A timer message queued for a prior session may arrive after reopen.
    if (!self->pending_open_ || GetTickCount64() < self->ready_deadline_) return;
    self->ConfigureOwnerTimer(kPaletteReadyTimer, 0);
    self->pending_open_->Error("ready_timeout", "The appearance window did not produce a first frame");
    self->pending_open_.reset();
    self->CloseOnPalette(self->session_, true);
  });
}

void PaletteWindowManager::Handle(const flutter::MethodCall<Value>& call,
                                  std::shared_ptr<Result> result) {
  if (closing_ || shutdown_requested_) { result->Error("closed", "Palette owner is closing"); return; }
  if (call.method_name() == "close") {
    const auto session = Integer(call.arguments());
    result->Success();
    if (session == session_) {
      cache_allowed_ = false;
      palette_closing_ = true;
      PostMessage(owner_, kPaletteCloseMessage, static_cast<WPARAM>(session), 0);
    }
    return;
  }
  const auto session = Integer(Field(call.arguments(), "session"));
  if (session <= 0) { result->Error("invalid_session", "Expected a palette session"); return; }
  if (call.method_name() == "update") {
    if (palette_ && active_ && session == session_) {
      snapshot_ = *call.arguments();
      if (!pending_open_) {
        auto palette = palette_;
        palette->Update(snapshot_);
      }
    }
    if (!closing_) result->Success();
    return;
  }
  if (call.method_name() != "open" && call.method_name() != "warm") { result->NotImplemented(); return; }
  if (active_) { result->Error("already_open", "A palette is already open"); return; }
  warming_ = call.method_name() == "warm";
  if (warming_ && palette_) { warming_ = false; result->Success(); return; }
  if (!warming_) first_warm_cached_ = false;
  const auto bounds = PaletteBounds(owner_);
  if (!bounds) { result->Error("monitor_unavailable", "Could not read the owner's monitor"); return; }
  session_ = session;
  ConfigureOwnerTimer(kPaletteCacheTimer, 0);
  active_ = true;
  cache_allowed_ = false;
  palette_closing_ = false;
  snapshot_ = *call.arguments();
  prepared_revision_ = Integer(Field(&snapshot_, "revision"));
  pending_open_ = std::move(result);
  ready_deadline_ = GetTickCount64() + kPaletteReadyMilliseconds;
  ConfigureOwnerTimer(kPaletteReadyTimer, kPaletteReadyMilliseconds);
  if (palette_) {
    auto palette = palette_;
    palette->Present(session, snapshot_, *bounds);
    return;
  }
  auto palette = std::make_shared<AppearancePaletteWindow>(project_, owner_, session, snapshot_,
      [this](const auto& child_call, auto child_result) {
        auto keep_alive = shared_from_this();
        HandleChild(child_call, std::move(child_result));
      });
  palette_ = palette;
  const bool created = palette->CreateOwned(PaletteTitle(snapshot_), owner_, *bounds);
  if (closing_ || palette_ != palette || !pending_open_) return;
  if (!created) {
    pending_open_->Error("create_failed", "Could not create the appearance window");
    pending_open_.reset();
    CloseOnPalette(session_, false);
  }
}

void PaletteWindowManager::ShowFirstFrameOnPalette(int64_t session) {
  if (closing_ || palette_closing_ || !active_ || !palette_ || session != session_) return;
  auto palette = palette_;
  const auto latest_revision = Integer(Field(&snapshot_, "revision"));
  if (warming_) {
    warming_ = false;
    ConfigureOwnerTimer(kPaletteReadyTimer, 0);
    if (pending_open_) { pending_open_->Success(); pending_open_.reset(); }
    cache_allowed_ = true;
    first_warm_cached_ = true;
    CloseOnPalette(session, false);
    return;
  }
  if (pending_open_ && prepared_revision_ != latest_revision) {
    const auto bounds = PaletteBounds(owner_);
    if (!bounds) { CloseOnPalette(session, true); return; }
    prepared_revision_ = latest_revision;
    palette->Present(session, snapshot_, *bounds);
    return;
  }
  palette->ShowFirstFrame();
  if (closing_ || palette_closing_ || palette_ != palette || session != session_) return;
  if (pending_open_) {
    ConfigureOwnerTimer(kPaletteReadyTimer, 0);
    pending_open_->Success(); pending_open_.reset();
  }
}

void PaletteWindowManager::HandleChild(const flutter::MethodCall<Value>& call,
                                      std::unique_ptr<Result> result) {
  if (closing_ || palette_closing_ || !active_ || !palette_) { result->Error("closed", "Palette is closed"); return; }
  if (call.method_name() == "ready") { result->Success(snapshot_); return; }
  if (Integer(Field(call.arguments(), "session")) != session_) {
    result->Error("stale_session", "Palette session has expired"); return;
  }
  if (call.method_name() == "close") {
    result->Success();
    cache_allowed_ = true; // Only the child path has flushed/acknowledged edits.
    palette_closing_ = true;
    PostMessage(owner_, kPaletteCloseMessage, static_cast<WPARAM>(session_), 0);
    return;
  }
  if (call.method_name() != "edit" && call.method_name() != "retry") {
    result->NotImplemented(); return;
  }
  // The child reply must never access a messenger belonging to a dead engine.
  const auto weak = palette_->lifetime();
  std::shared_ptr<Result> reply(std::move(result));
  auto response = std::make_unique<flutter::MethodResultFunctions<Value>>(
      [weak, reply](const Value* value) {
        if (Alive(weak)) { if (value) reply->Success(*value); else reply->Success(); }
      },
      [weak, reply](const std::string& code, const std::string& message, const Value*) {
        if (Alive(weak)) reply->Error(code, message);
      },
      [weak, reply]() { if (Alive(weak)) reply->NotImplemented(); });
  InvokeOwner(call.method_name(), std::make_unique<Value>(*call.arguments()),
                         std::move(response));
}

void PaletteWindowManager::CloseOnPalette(int64_t session, bool notify) {
  if (!palette_ || !active_ || session != session_) return;
  ConfigureOwnerTimer(kPaletteReadyTimer, 0);
  palette_closing_ = true;
  active_ = false;
  const bool reuse = !closing_ && cache_allowed_ && !pending_open_ &&
                     IsWindow(palette_->GetHandle());
  if (reuse) {
    auto palette = palette_;
    palette->Suspend();
    if (!closing_ && palette_ == palette && !active_) {
      cache_deadline_ = GetTickCount64() + kPaletteCacheMilliseconds;
      // Retain the single prewarmed engine until its first real presentation.
      // Subsequent closes use the normal bounded idle cache.
      ConfigureOwnerTimer(kPaletteCacheTimer,
                          first_warm_cached_ ? 0 : kPaletteCacheMilliseconds);
    }
  } else {
    auto palette = std::exchange(palette_, nullptr);
    palette->Destroy();
  }
  if (pending_open_) {
    pending_open_->Error("closed", "Appearance window closed before its first frame");
    pending_open_.reset();
  }
  if (notify && !closing_) {
    POINT cursor{};
    RECT owner_bounds{};
    const bool over_owner = GetCursorPos(&cursor) && GetWindowRect(owner_, &owner_bounds) &&
                            PtInRect(&owner_bounds, cursor);
    flutter::EncodableMap closed{{Value("session"), Value(session)},
                                {Value("ownerHover"), Value(over_owner)}};
    InvokeOwner("closed", std::make_unique<Value>(closed));
  }
}

void PaletteWindowManager::EvictCacheOnPalette() {
  ConfigureOwnerTimer(kPaletteCacheTimer, 0);
  if (active_) return;
  auto palette = std::exchange(palette_, nullptr);
  if (palette) palette->Destroy();
}

}  // namespace desktop_lyric_runner
