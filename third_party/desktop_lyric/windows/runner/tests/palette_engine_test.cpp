// Opt-in real-AOT first-frame benchmark. Both top-level HWNDs remain hidden.
// No Show/ShowFirstFrame, screenshot, plugins, audio, stdin or user settings.
// Suspend uses production SW_HIDE only; a first-frame event never shows it.
#include <windows.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "appearance_palette_window.h"

namespace {
using Clock = std::chrono::steady_clock;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
constexpr auto kStageLimit = std::chrono::seconds(10);

// Message pumps are bounded below; this watchdog additionally bounds blocking
// engine construction/destruction without ever displaying a crash/error UI.
class StageBudget {
 public:
  StageBudget() : worker_([this] { Watch(); }) {}
  ~StageBudget() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      done_ = true;
    }
    changed_.notify_one();
    worker_.join();
  }
  void Begin(const char* name) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      name_ = name;
      deadline_ = Clock::now() + kStageLimit;
      ++revision_;
    }
    changed_.notify_one();
  }
 private:
  void Watch() {
    std::unique_lock<std::mutex> lock(mutex_);
    while (!done_) {
      const auto revision = revision_;
      if (changed_.wait_until(lock, deadline_, [&] {
            return done_ || revision != revision_;
          })) continue;
      std::fprintf(stderr, "FAIL: 10s stage watchdog: %s\n", name_);
      std::fflush(stderr);
      // Only the isolated test process is terminated on a hung native API.
      TerminateProcess(GetCurrentProcess(), 124);
    }
  }
  std::mutex mutex_;
  std::condition_variable changed_;
  const char* name_ = "initialization";
  Clock::time_point deadline_ = Clock::now() + kStageLimit;
  unsigned revision_ = 0;
  bool done_ = false;
  std::thread worker_;
};

class HiddenOwner : public Win32Window {
 public:
  struct Frame { int64_t session; Clock::time_point arrived; };
  std::vector<Frame> frames;
  unsigned closes = 0, sizes = 0, positions = 0, show_changes = 0;
 protected:
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override {
    if (message == kPaletteShownMessage) {
      frames.push_back({static_cast<int64_t>(wparam), Clock::now()});
      return 0;  // Intentionally never call ShowFirstFrame.
    }
    if (message == kPaletteCloseMessage) { ++closes; return 0; }
    if (message == WM_SIZE) ++sizes;
    if (message == WM_SHOWWINDOW) ++show_changes;
    if (message == WM_WINDOWPOSCHANGING) {
      const auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
      if (!(position->flags & SWP_NOMOVE) ||
          !(position->flags & SWP_NOSIZE)) ++positions;
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
};

struct OwnerState {
  RECT bounds{};
  LONG_PTR style, extended;
  unsigned sizes, positions, show_changes;
  explicit OwnerState(HiddenOwner& owner)
      : style(GetWindowLongPtr(owner.GetHandle(), GWL_STYLE)),
        extended(GetWindowLongPtr(owner.GetHandle(), GWL_EXSTYLE)),
        sizes(owner.sizes), positions(owner.positions),
        show_changes(owner.show_changes) {
    GetWindowRect(owner.GetHandle(), &bounds);
  }
  bool Unchanged(HiddenOwner& owner) const {
    RECT current{};
    return IsWindow(owner.GetHandle()) &&
        GetWindowRect(owner.GetHandle(), &current) &&
        EqualRect(&bounds, &current) && !IsWindowVisible(owner.GetHandle()) &&
        GetWindowLongPtr(owner.GetHandle(), GWL_STYLE) == style &&
        GetWindowLongPtr(owner.GetHandle(), GWL_EXSTYLE) == extended &&
        owner.sizes == sizes && owner.positions == positions &&
        owner.show_changes == show_changes;
  }
};

bool HiddenAndStable(HiddenOwner& owner, const OwnerState& baseline,
                     HWND palette, HWND content) {
  return baseline.Unchanged(owner) && IsWindow(palette) &&
      !IsWindowVisible(palette) &&
      !(GetWindowLongPtr(palette, GWL_STYLE) & WS_VISIBLE) &&
      GetWindow(palette, GW_OWNER) == owner.GetHandle() &&
      GetWindow(palette, GW_CHILD) == content && IsWindow(content) &&
      !IsWindowVisible(content);
}

// Dispatch all engine/platform messages, not just the owner's HWND messages.
// A hidden Flutter view still needs its normal platform-thread message pump.
template <typename Predicate>
bool PumpUntil(Predicate done, Clock::time_point deadline) {
  while (!done()) {
    if (Clock::now() >= deadline) return false;
    MSG message{};
    for (unsigned i = 0; i < 256 &&
         PeekMessage(&message, nullptr, 0, 0, PM_REMOVE); ++i) {
      if (message.message == WM_QUIT) {
        std::cerr << "FAIL: unexpected WM_QUIT\n";
        return false;
      }
      TranslateMessage(&message);
      DispatchMessage(&message);
      if (Clock::now() >= deadline) return false;
    }
    if (!done()) MsgWaitForMultipleObjectsEx(
        0, nullptr, 10, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
  }
  return true;
}

bool Settle() {
  const auto until = Clock::now() + std::chrono::milliseconds(40);
  return PumpUntil([&] { return Clock::now() >= until; }, until + kStageLimit);
}

Value Snapshot(int64_t session) {
  const bool dark = session % 2 == 0;
  constexpr std::array<const char*, 4> languages{"zh", "en", "ja", "ko"};
  constexpr std::array<const char*, 4> fonts{
      "DanPingFangSC", "Segoe UI", "Yu Gothic UI", "Malgun Gothic"};
  const auto variant = static_cast<size_t>((session - 1) % 4);
  Map appearance{
      {Value("lyricFontSize"), Value(22.0 + static_cast<double>(session))},
      {Value("translationFontSize"), Value(18.0 + static_cast<double>(session))},
      {Value("customColor"), Value()},
      {Value("backgroundOpacity"), Value(0.25)},
      {Value("textOpacity"), Value(0.9)},
      {Value("strokeEnabled"), Value(true)},
      {Value("taskbarMode"), Value(session % 2 == 0)},
      {Value("taskbarGap"), Value(8.0)},
      {Value("taskbarHeight"), Value(56.0)},
      {Value("taskbarMinimumFontSize"), Value(14.0)},
      {Value("taskbarTranslation"), Value(false)}};
  return Value(Map{
      {Value("session"), Value(session)},
      {Value("revision"), Value(session)},
      {Value("editAck"), Value(int64_t{0})},
      {Value("appearance"), Value(appearance)},
      {Value("darkMode"), Value(dark)},
      {Value("primary"), Value(int64_t{dark ? 0xffa8d5ff : 0xff36618e})},
      {Value("surfaceContainer"), Value(int64_t{dark ? 0xff1d2024 : 0xffeef0f7})},
      {Value("onSurface"), Value(int64_t{dark ? 0xfff3f3f3 : 0xff202020})},
      {Value("language"), Value(languages[variant])},
      {Value("fontFamily"), Value(fonts[variant])},
      {Value("fontFamilyFallback"), Value(flutter::EncodableList{
          Value("DanPingFangSC"), Value("Segoe UI Symbol"), Value("Segoe UI Emoji")})},
      {Value("saveError"), Value()},
      {Value("layoutError"), Value()}});
}

bool HasData(const std::filesystem::path& data) {
  std::error_code error;
  return std::filesystem::is_directory(data / L"flutter_assets", error) &&
      std::filesystem::is_regular_file(data / L"icudtl.dat", error) &&
      std::filesystem::file_size(data / L"icudtl.dat", error) > 0 && !error &&
      std::filesystem::is_regular_file(data / L"app.so", error) &&
      std::filesystem::file_size(data / L"app.so", error) > 0 && !error;
}

int Run(const std::filesystem::path& data) {
  StageBudget budget;
  HiddenOwner owner;
  if (!owner.Create(L"Hidden palette engine benchmark owner", {100, 100}, {800, 160})) {
    std::cerr << "FAIL: owner Create\n";
    return 2;
  }
  const OwnerState baseline(owner);
  if (IsWindowVisible(owner.GetHandle())) return 3;
  flutter::DartProject project(data.wstring());
  Value current = Snapshot(1);
  unsigned ready_calls = 0, unexpected_calls = 0;
  budget.Begin("cold create to hidden first frame");
  const auto cold_start = Clock::now();
  auto palette = std::make_unique<AppearancePaletteWindow>(
      project, owner.GetHandle(), 1, current,
      [&](const flutter::MethodCall<Value>& call,
          std::unique_ptr<AppearancePaletteWindow::Result> result) {
        if (call.method_name() == "ready") {
          ++ready_calls;
          result->Success(current);
        } else {
          ++unexpected_calls;
          result->Error("test_read_only", "No appearance edits in the hidden benchmark");
        }
      });
  const RECT bounds{120, 120, 520, 640};
  if (!palette->CreateOwned(L"Hidden palette engine benchmark", owner.GetHandle(), bounds)) {
    std::cerr << "FAIL: palette CreateOwned\n";
    return 4;
  }
  const HWND palette_handle = palette->GetHandle();
  const HWND content = GetWindow(palette_handle, GW_CHILD);
  auto valid = [&] { return HiddenAndStable(owner, baseline, palette_handle, content); };
  std::array<double, 5> elapsed{};
  for (int64_t session = 1; session <= 5; ++session) {
    auto started = cold_start;
    if (session != 1) {
      budget.Begin("warm present to hidden first frame");
      current = Snapshot(session);
      started = Clock::now();
      palette->Present(session, current, bounds);
    }
    bool invariant_failed = false;
    if (!PumpUntil([&] {
          invariant_failed = !valid() || owner.closes != 0 || unexpected_calls != 0;
          return invariant_failed || owner.frames.size() >= static_cast<size_t>(session);
        }, started + kStageLimit) || invariant_failed ||
        owner.frames.size() != static_cast<size_t>(session) ||
        owner.frames.back().session != session || !valid()) {
      std::cerr << "FAIL: hidden first frame/invariants, session=" << session
                << " frames=" << owner.frames.size() << " closes=" << owner.closes << '\n';
      return 5;
    }
    elapsed[static_cast<size_t>(session - 1)] =
        std::chrono::duration<double, std::milli>(owner.frames.back().arrived - started).count();
    std::cout << (session == 1 ? "cold_create_to_frame_ms=" : "warm_present_to_frame_ms=")
              << std::fixed << std::setprecision(3)
              << elapsed[static_cast<size_t>(session - 1)]
              << " session=" << session << '\n';
    budget.Begin("suspend hidden palette");
    palette->Suspend();
    if (!Settle() || !valid() || owner.closes != 0 ||
        owner.frames.size() != static_cast<size_t>(session)) return 6;
  }
  // Native startup arguments replace the old ready round trip. Unexpected
  // calls would also reveal accidental persistence/plugin/UI initialization.
  if (ready_calls != 0 || unexpected_calls != 0) return 7;
  budget.Begin("destroy hidden engine and owner");
  const auto lifetime = palette->lifetime();
  palette->Destroy();
  if (IsWindow(palette_handle) || IsWindow(content) || !baseline.Unchanged(owner)) return 8;
  if (const auto alive = lifetime.lock(); alive && *alive) return 9;
  palette.reset();
  if (!Settle() || !baseline.Unchanged(owner) || owner.closes != 1) return 10;
  const HWND owner_handle = owner.GetHandle();
  owner.Destroy();
  if (IsWindow(owner_handle) || !Settle()) return 11;
  auto warm = std::array<double, 4>{elapsed[1], elapsed[2], elapsed[3], elapsed[4]};
  std::sort(warm.begin(), warm.end());
  std::cout << "warm_median_ms=" << (warm[1] + warm[2]) / 2
            << " warm_min_ms=" << warm.front() << " warm_max_ms=" << warm.back() << '\n'
            << "PASS: 1 cold + 4 warm real-AOT hidden first-frame stages; same palette/content HWND; "
               "4 languages and changing themes/fonts; zero startup ready round trips; "
               "owner bounds/styles/resize/move/show unchanged; both windows always hidden; "
               "complete engine/HWND teardown; no WM_QUIT. Timing is observational, not a speed gate.\n";
  return 0;
}
}  // namespace

int wmain(int argc, wchar_t** argv) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);
  if (argc != 2) {
    std::cerr << "Usage: desktop_lyric_palette_engine_test.exe <existing-Release-data-directory>\n";
    return 64;
  }
  std::error_code error;
  const auto data = std::filesystem::canonical(argv[1], error);
  if (error || !HasData(data)) {
    std::cerr << "FAIL: an existing Release data directory with flutter_assets, icudtl.dat and app.so is required\n";
    return 65;
  }
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized)) return 66;
  const int result = Run(data);
  CoUninitialize();
  return result;
}
