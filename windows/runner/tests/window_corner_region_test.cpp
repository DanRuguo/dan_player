#include "../window_corner_region.h"
#include "../window_resize_policy.h"
#include "../window_teardown.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace {
int checks = 0, shows = 0;
bool fail_create = false, fail_set = false;
bool fake_visible = true;
int hide_calls = 0;
void Check(bool value, int line) {
  ++checks;
  if (!value) { std::cerr << "FAIL corner region line " << line << '\n'; std::exit(1); }
}
#define CHECK(value) Check((value), __LINE__)
BOOL WINAPI ValidTeardownWindow(HWND window) {
  return window == reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
}
BOOL WINAPI HideTeardownWindow(HWND window, int command) {
  CHECK(ValidTeardownWindow(window));
  CHECK(command == SW_HIDE);
  const bool was_visible = fake_visible;
  fake_visible = false;
  ++hide_calls;
  return was_visible;
}
struct Fixture { window_corners::Controller* controller = nullptr; bool close_on_change = false; };
LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* fixture = reinterpret_cast<Fixture*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    fixture = static_cast<Fixture*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(fixture));
  }
  if (message == WM_SHOWWINDOW && wparam) ++shows;
  if (fixture && fixture->controller) {
    if (message == WM_WINDOWPOSCHANGING && fixture->close_on_change) {
      fixture->close_on_change = false;
      fixture->controller->Close();
    }
    if (message == WM_SIZE || message == WM_WINDOWPOSCHANGED) fixture->controller->Refresh();
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
HRGN WINAPI MakeRegion(int left, int top, int right, int bottom, int x, int y) {
  return fail_create ? nullptr : CreateRoundRectRgn(left, top, right, bottom, x, y);
}
int WINAPI SetRegion(HWND window, HRGN region, BOOL redraw) {
  return fail_set && region ? 0 : SetWindowRgn(window, region, redraw);
}
void HasRoundedRegion(HWND window) {
  RECT frame{};
  CHECK(GetWindowRect(window, &frame));
  const int width = frame.right - frame.left, height = frame.bottom - frame.top;
  HRGN region = CreateRectRgn(0, 0, 0, 0);
  CHECK(region != nullptr);
  CHECK(GetWindowRgn(window, region) == COMPLEXREGION);
  CHECK(!PtInRegion(region, 0, 0));
  CHECK(!PtInRegion(region, width - 1, 0));
  CHECK(!PtInRegion(region, 0, height - 1));
  CHECK(!PtInRegion(region, width - 1, height - 1));
  CHECK(PtInRegion(region, width / 2, height / 2));
  CHECK(PtInRegion(region, width / 2, 0));
  CHECK(DeleteObject(region));
}
void NoRegion(HWND window) {
  HRGN region = CreateRectRgn(0, 0, 0, 0);
  CHECK(region != nullptr);
  CHECK(GetWindowRgn(window, region) == ERROR);
  CHECK(DeleteObject(region));
}
}  // namespace

int main() {
  namespace corners = window_corners;
  CHECK(!corners::kCustomCornersAvailable);
  CHECK(!corners::EffectiveEnabled(false));
  CHECK(!corners::EffectiveEnabled(true));
  const auto fake_window = reinterpret_cast<HWND>(static_cast<UINT_PTR>(1));
  window_teardown::HideBeforeResources(nullptr, &HideTeardownWindow, &ValidTeardownWindow);
  window_teardown::HideBeforeResources(reinterpret_cast<HWND>(static_cast<UINT_PTR>(2)),
                                       &HideTeardownWindow, &ValidTeardownWindow);
  CHECK(hide_calls == 0 && fake_visible);
  window_teardown::HideBeforeResources(fake_window, &HideTeardownWindow, &ValidTeardownWindow);
  CHECK(hide_calls == 1 && !fake_visible);
  // The second runner guard remains safe; ShowWindow's FALSE return means
  // "already hidden", not failure. No positive show command is ever issued.
  window_teardown::HideBeforeResources(fake_window, &HideTeardownWindow, &ValidTeardownWindow);
  CHECK(hide_calls == 2 && !fake_visible);
  for (UINT dpi : {96u, 120u, 144u, 192u, 288u}) {
    const auto shape = corners::DesiredShape(1280, 800, dpi, 16, true, false, false, false);
    CHECK(shape.diameter == static_cast<int>(32 * dpi / 96));
    for (int reason = 0; reason < 4; ++reason) {
      CHECK(corners::DesiredShape(1280, 800, dpi, 16, reason != 0, reason == 1,
                                   reason == 2, reason == 3).diameter == 0);
    }
  }
  CHECK(corners::DesiredShape(10, 9, 192, 16, true, false, false, false).diameter == 9);
  CHECK(corners::DesiredShape(0, 800, 96, 16, true, false, false, false).diameter == 0);
  CHECK(corners::DesiredShape(1280, 800, 96, std::numeric_limits<double>::infinity(), true, false, false, false).diameter == 0);

  const auto old_dpi = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const HWND foreground = GetForegroundWindow();
  const auto instance = GetModuleHandleW(nullptr);
  constexpr auto name = L"DanPlayer.HiddenCornerRegion.Test";
  WNDCLASSW cls{};
  cls.hInstance = instance;
  cls.lpfnWndProc = Proc;
  cls.lpszClassName = name;
  CHECK(RegisterClassW(&cls) != 0);
  Fixture fixture;
  HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, name, L"hidden region fixture",
      WS_OVERLAPPEDWINDOW, 100, 100, 640, 420, nullptr, nullptr, instance, &fixture);
  CHECK(window != nullptr && !IsWindowVisible(window));
  const auto style = GetWindowLongPtrW(window, GWL_STYLE);
  corners::Controller controller(window, &SetRegion, &MakeRegion);
  fixture.controller = &controller;
  NoRegion(window);
  controller.Configure(corners::EffectiveEnabled(true), 16);
  NoRegion(window);
  CHECK(controller.updates() == 0);
  controller.Configure(true, 16);
  CHECK(controller.available());
  HasRoundedRegion(window);
  const unsigned initial = controller.updates();
  for (int unchanged = 0; unchanged < 1000; ++unchanged) controller.Refresh();
  CHECK(controller.updates() == initial);
  CHECK(SetWindowPos(window, nullptr, 104, 107, 0, 0,
                     SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE));
  CHECK(controller.updates() == initial);
  // A real HWND can lose its region after plugin/compositor work without any
  // change to geometry. Refresh alone used to trust the now-stale cache.
  CHECK(SetWindowRgn(window, nullptr, FALSE));
  NoRegion(window);
  controller.Refresh();
  NoRegion(window);
  controller.Revalidate();
  HasRoundedRegion(window);
  CHECK(controller.updates() == initial + 1);
  const auto before_replacement = controller.updates();
  CHECK(SetWindowRgn(window, CreateRectRgn(0, 0, 640, 420), FALSE));
  controller.Revalidate();
  HasRoundedRegion(window);
  CHECK(controller.updates() == before_replacement + 1);
  const auto before_validation = controller.updates();
  const DWORD objects = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int unchanged = 0; unchanged < 1000; ++unchanged) controller.Revalidate();
  CHECK(controller.updates() == before_validation);
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == objects);
  const auto started = std::chrono::steady_clock::now();
  for (int resize = 0; resize < 500; ++resize) {
    const unsigned before = controller.updates();
    CHECK(SetWindowPos(window, nullptr, 0, 0, 641 + resize % 251, 421 + resize % 117,
                         SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
    controller.Refresh();
    CHECK(controller.updates() == before + 1);
    CHECK(GetWindowLongPtrW(window, GWL_STYLE) == style);
    CHECK(!IsWindowVisible(window));
    if (resize % 25 == 0) HasRoundedRegion(window);
  }
  const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(
      std::chrono::steady_clock::now() - started).count();
  // Mini-sized windows retain the same logical 16dp corner radius.
  CHECK(SetWindowPos(window, nullptr, 0, 0, 320, 200, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
  HasRoundedRegion(window);
  RECT rect{};
  CHECK(GetWindowRect(window, &rect));
  CHECK(window_resize::HitTestResizeBorder(rect, {rect.left + 1, rect.top + 1}, 8, 8) == HTTOPLEFT);

  controller.Configure(false, 16);
  NoRegion(window);
  controller.Configure(true, 16);
  HasRoundedRegion(window);
  fail_create = true;
  controller.Configure(true, 17);
  CHECK(!controller.available());
  NoRegion(window);
  const unsigned failed_attempt = controller.updates();
  for (int repeated = 0; repeated < 1000; ++repeated) controller.Refresh();
  CHECK(controller.updates() == failed_attempt);
  fail_create = false;
  controller.Refresh();
  CHECK(controller.updates() == failed_attempt);
  CHECK(SetWindowPos(window, nullptr, 0, 0, 321, 200,
                     SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE));
  CHECK(controller.available());
  HasRoundedRegion(window);
  fail_set = true;
  controller.Configure(true, 18);
  CHECK(!controller.available());
  NoRegion(window);
  fail_set = false;
  controller.Configure(true, 18.5);
  CHECK(controller.available());
  HasRoundedRegion(window);
  fixture.close_on_change = true;
  controller.Configure(true, 19);
  NoRegion(window);
  controller.Configure(true, 16);
  NoRegion(window);
  CHECK(DestroyWindow(window));
  fixture.controller = nullptr;

  for (DWORD extra : {DWORD{WS_MINIMIZE}, DWORD{WS_MAXIMIZE}}) {
    HWND state_window = CreateWindowExW(WS_EX_TOOLWINDOW, name, L"hidden state fixture",
        WS_OVERLAPPEDWINDOW | extra, 100, 100, 800, 600, nullptr, nullptr, instance, &fixture);
    CHECK(state_window != nullptr && !IsWindowVisible(state_window));
    corners::Controller state(state_window);
    state.Configure(true, 16);
    NoRegion(state_window);
    state.Close();
    CHECK(DestroyWindow(state_window));
  }
  MONITORINFO monitor{sizeof(monitor)};
  CHECK(GetMonitorInfoW(MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY), &monitor));
  const RECT full = monitor.rcMonitor;
  HWND fullscreen = CreateWindowExW(WS_EX_TOOLWINDOW, name, L"hidden fullscreen-size fixture",
      WS_POPUP, full.left, full.top, full.right - full.left, full.bottom - full.top,
      nullptr, nullptr, instance, &fixture);
  CHECK(fullscreen != nullptr && !IsWindowVisible(fullscreen));
  corners::Controller full_controller(fullscreen);
  full_controller.Configure(true, 16);
  NoRegion(fullscreen);
  full_controller.Close();
  CHECK(DestroyWindow(fullscreen));
  corners::Controller invalid(nullptr);
  invalid.Configure(true, 16);
  invalid.Refresh();
  invalid.Close();
  CHECK(invalid.updates() == 0);
  CHECK(GetForegroundWindow() == foreground && shows == 0);
  CHECK(UnregisterClassW(name, instance));
  if (old_dpi) SetThreadDpiAwarenessContext(old_dpi);
  std::cout << "PASS: " << checks << " corner-region checks; 500 hidden resizes in "
            << elapsed / 1000.0 << "ms; no ShowWindow/DWM appearance validation.\n";
}
