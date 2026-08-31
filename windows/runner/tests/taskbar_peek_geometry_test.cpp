#include <windows.h>

#include "../taskbar_peek_geometry.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>

namespace {
namespace peek = taskbar_thumbnail;
int checks = 0;
int shown = 0;

void Check(bool passed, int line) {
  ++checks;
  if (!passed) {
    std::cerr << "FAIL: hidden Peek geometry line " << line << '\n';
    std::exit(1);
  }
}
#define CHECK(condition) Check((condition), __LINE__)

enum class Frame { kStandard, kHiddenTitle, kAllClient };
struct Fixture {
  Frame frame;
  int inset;
};

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* fixture = reinterpret_cast<Fixture*>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    fixture = static_cast<Fixture*>(reinterpret_cast<CREATESTRUCTW*>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(fixture));
  }
  if (message == WM_SHOWWINDOW && wparam) ++shown;
  if (message == WM_NCCALCSIZE && wparam && fixture && fixture->frame != Frame::kStandard) {
    if (fixture->frame == Frame::kHiddenTitle) {
      auto& rect = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0];
      rect.left += fixture->inset;
      rect.right -= fixture->inset;
      rect.bottom -= fixture->inset;
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

constexpr UINT kGeometryOnly = SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE |
                               SWP_NOOWNERZORDER | SWP_FRAMECHANGED;

peek::Size Client(HWND window) {
  RECT client{};
  CHECK(GetClientRect(window, &client) != FALSE);
  return peek::PeekRectSize(client);
}

bool Equal(peek::Size left, peek::Size right) {
  return left.width == right.width && left.height == right.height;
}

void QueryPreservesWindow(HWND window, peek::PeekClientGeometry& geometry,
                          peek::Size expected) {
  RECT before{}, after{};
  WINDOWPLACEMENT placement_before{}, placement_after{};
  placement_before.length = sizeof(placement_before);
  placement_after.length = sizeof(placement_after);
  CHECK(GetWindowRect(window, &before) != FALSE);
  CHECK(GetWindowPlacement(window, &placement_before) != FALSE);
  const auto style = GetWindowLongPtrW(window, GWL_STYLE);
  const auto foreground = GetForegroundWindow();
  CHECK(Equal(geometry.Resolve(window), expected));
  CHECK(GetWindowRect(window, &after) != FALSE);
  CHECK(EqualRect(&before, &after) != FALSE);
  CHECK(GetWindowPlacement(window, &placement_after) != FALSE);
  CHECK(EqualRect(&placement_before.rcNormalPosition, &placement_after.rcNormalPosition) != FALSE);
  CHECK(placement_before.showCmd == placement_after.showCmd);
  CHECK(GetWindowLongPtrW(window, GWL_STYLE) == style);
  CHECK(GetForegroundWindow() == foreground);
  CHECK(!IsWindowVisible(window));
  CHECK(shown == 0);
}
}  // namespace

// Real HWND geometry only. No ShowWindow, Shell icon, installed app, Flutter,
// DWM presentation, screenshot or user files. Initial WS_MINIMIZE supplies a
// real iconic frame while WS_VISIBLE is absent throughout every test.
int main() {
  const auto prior_dpi = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CHECK(prior_dpi != nullptr);
  const HINSTANCE instance = GetModuleHandleW(nullptr);
  constexpr auto class_name = L"DanPlayer.HiddenPeekGeometry.Test";
  WNDCLASSW window_class{};
  window_class.hInstance = instance;
  window_class.lpfnWndProc = WindowProc;
  window_class.lpszClassName = class_name;
  CHECK(RegisterClassW(&window_class) != 0);
  const auto initial_foreground = GetForegroundWindow();
  int windows = 0;
  for (const int dpi : {96, 144, 192}) {
    for (const Frame frame : {Frame::kStandard, Frame::kHiddenTitle, Frame::kAllClient}) {
      for (const DWORD ex_style : {DWORD{0}, DWORD{WS_EX_TOOLWINDOW}}) {
        Fixture fixture{frame, 8 * dpi / 96};
        const peek::Size requested_normal{1280 * dpi / 96, 800 * dpi / 96};
        HWND window = CreateWindowExW(ex_style, class_name, L"hidden synthetic Peek fixture",
            WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_MINIMIZE, 100, 100,
            requested_normal.width, requested_normal.height, nullptr, nullptr, instance, &fixture);
        ++windows;
        CHECK(window != nullptr);
        CHECK(IsIconic(window) != FALSE);
        CHECK(!IsWindowVisible(window));
        // Runs the same custom-frame calculation used after title-bar setup.
        CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kGeometryOnly | SWP_NOSIZE) != FALSE);
        const auto iconic_client = Client(window);
        CHECK(iconic_client.width < 480 && iconic_client.height < 240);
        WINDOWPLACEMENT placement{};
        placement.length = sizeof(placement);
        CHECK(GetWindowPlacement(window, &placement) != FALSE);
        // CreateWindow may constrain an oversized initial frame to the
        // monitor. Use its actual restored placement, never the requested size.
        const auto normal = peek::PeekRectSize(placement.rcNormalPosition);
        CHECK(normal.valid());
        CHECK(normal.width > 480 && normal.height > 240);

        peek::Size expected = normal;
        if (frame == Frame::kHiddenTitle) {
          expected = {normal.width - 2 * fixture.inset, normal.height - fixture.inset};
        } else if (frame == Frame::kStandard) {
          RECT adjusted{};
          CHECK(AdjustWindowRectExForDpi(&adjusted, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                                         FALSE, ex_style, GetDpiForWindow(window)) != FALSE);
          expected = {normal.width - (adjusted.right - adjusted.left),
                       normal.height - (adjusted.bottom - adjusted.top)};
        }
        peek::PeekClientGeometry initially_minimized;
        initially_minimized.Observe(window, true);
        QueryPreservesWindow(window, initially_minimized, expected);
        const auto layout = peek::FitPeekLayout({1440, 720}, initially_minimized.Resolve(window));
        CHECK(layout.content.width > 480 && layout.content.height > 240);
        CHECK(peek::ValidPeekCanvas(layout.canvas,
            static_cast<std::size_t>(layout.canvas.width) * layout.canvas.height * 4));
        std::cout << "frame=" << static_cast<int>(frame) << " fixtureDpi=" << dpi
                  << " windowDpi=" << GetDpiForWindow(window)
                  << " tool=" << (ex_style != 0) << " iconic=" << iconic_client.width
                  << 'x' << iconic_client.height << " resolved=" << expected.width
                  << 'x' << expected.height << '\n';

        // Replay real normal/iconic measurements with separate hidden HWNDs.
        // SC_RESTORE/SC_MINIMIZE could show a window, and clearing WS_MINIMIZE
        // alone does not change Windows' internal iconic state. Neither is
        // used here. Pure policy tests cover the same state sequence without
        // HWNDs; this adapter test verifies both kinds of actual Win32 input.
        HWND restored = CreateWindowExW(ex_style, class_name, L"hidden normal Peek fixture",
            WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, 100, 100, normal.width,
            normal.height, nullptr, nullptr, instance, &fixture);
        ++windows;
        CHECK(restored != nullptr);
        CHECK(!IsIconic(restored));
        CHECK(!IsWindowVisible(restored));
        peek::PeekClientGeometry observed;
        for (const auto size : {normal, peek::Size{1920, 1080}, peek::Size{320, 200}}) {
          CHECK(SetWindowPos(restored, nullptr, 0, 0, size.width, size.height, kGeometryOnly) != FALSE);
          const auto actual = Client(restored);
          observed.Observe(restored);
          QueryPreservesWindow(restored, observed, actual);
          observed.Observe(window, true);
          observed.Observe(window);  // IsIconic independently gates it.
          QueryPreservesWindow(window, observed, actual);
        }
        CHECK(DestroyWindow(restored) != FALSE);
        CHECK(!observed.Resolve(restored).valid());
        CHECK(DestroyWindow(window) != FALSE);
        CHECK(!initially_minimized.Resolve(window).valid());
      }
    }
  }
  peek::PeekClientGeometry invalid;
  CHECK(!invalid.Resolve(nullptr).valid());
  CHECK(!peek::PeekRectSize({0, 0, 0, 1}).valid());
  CHECK(!peek::PeekRectSize({std::numeric_limits<LONG>::min(), 0,
                             std::numeric_limits<LONG>::max(), 1}).valid());
  CHECK(Equal(peek::PeekRectSize({-4000, -2000, -2720, -1200}), {1280, 800}));
  CHECK(shown == 0);
  CHECK(GetForegroundWindow() == initial_foreground);
  CHECK(UnregisterClassW(class_name, instance) != FALSE);
  CHECK(SetThreadDpiAwarenessContext(prior_dpi) != nullptr);
  std::cout << "PASS: " << checks << " Peek geometry checks; " << windows
            << " hidden HWNDs; no ShowWindow/capture/DWM visual validation.\n";
}
