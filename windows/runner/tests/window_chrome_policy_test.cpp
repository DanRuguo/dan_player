#include "../../../third_party/desktop_lyric/windows/runner/window_chrome_policy.h"
#include "../window_resize_policy.h"

#include <cstdlib>
#include <iostream>

namespace {
int checks = 0;
int shown = 0;
void Check(bool pass, int line) {
  ++checks;
  if (!pass) {
    std::cerr << "FAIL window chrome policy line " << line << '\n';
    std::exit(1);
  }
}
#define CHECK(value) Check((value), __LINE__)

bool SameRect(const RECT& left, const RECT& right) {
  return EqualRect(&left, &right) != FALSE;
}

RECT HiddenFrame(const RECT& proposed, LONG top) {
  return {proposed.left + 8, proposed.top + top,
          proposed.right - 8, proposed.bottom - 8};
}

void CheckNotCorrected(const RECT& proposed, RECT calculated,
                       std::optional<LRESULT> result, bool maximized) {
  const RECT previous = calculated;
  CHECK(!window_chrome::CorrectWindowManagerHiddenFrame(
      proposed, calculated, result, maximized));
  CHECK(SameRect(previous, calculated));
}

void CheckCalculations() {
  // Physical-pixel calculations must not depend on screen origin or DPI.
  for (const RECT proposed : {RECT{100, 150, 900, 750},
                              RECT{-1600, -80, -500, 850}}) {
    for (const LONG top : {0L, 1L}) {
      RECT calculated = HiddenFrame(proposed, top);
      CHECK(window_chrome::CorrectWindowManagerHiddenFrame(
          proposed, calculated, 0, false));
      CHECK(SameRect(proposed, calculated));
      // Unhandled/native title bars, nonzero plugin results, and maximized
      // windows must never be mistaken for a restored hidden title bar.
      CheckNotCorrected(proposed, HiddenFrame(proposed, top), std::nullopt,
                        false);
      CheckNotCorrected(proposed, HiddenFrame(proposed, top), WVR_REDRAW, false);
      CheckNotCorrected(proposed, HiddenFrame(proposed, top), 0, true);
    }
    CheckNotCorrected(proposed, proposed, 0, false);  // Fullscreen/full client.
    CheckNotCorrected(proposed, HiddenFrame(proposed, 31), std::nullopt, false);
    CheckNotCorrected(proposed, HiddenFrame(proposed, 8), 0, true);  // Work area.
    CheckNotCorrected(proposed, HiddenFrame(proposed, 8), 0, false);
    RECT custom = HiddenFrame(proposed, 0);
    ++custom.left;
    CheckNotCorrected(proposed, custom, 0, false);
    custom = HiddenFrame(proposed, 1);
    --custom.bottom;
    CheckNotCorrected(proposed, custom, 0, false);
    custom = HiddenFrame(proposed, 0);
    ++custom.right;
    CheckNotCorrected(proposed, custom, 0, false);
  }
}

LONG fixture_top = 0;
bool fixture_fullscreen = false;
LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_SHOWWINDOW && wparam) ++shown;
  if (message == WM_NCCALCSIZE && wparam) {
    auto* parameters = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
    const RECT proposed = parameters->rgrc[0];
    if (!fixture_fullscreen) {
      parameters->rgrc[0] = HiddenFrame(proposed, fixture_top);
    }
    window_chrome::CorrectWindowManagerHiddenFrame(
        proposed, parameters->rgrc[0], 0, IsZoomed(window) != FALSE);
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

constexpr UINT kRefresh = SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
    SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE;

void VerifyStylesAndClient(HWND window, LONG_PTR capabilities, HWND foreground) {
  const auto style = GetWindowLongPtrW(window, GWL_STYLE);
  CHECK((style & WS_CAPTION) == WS_CAPTION);
  constexpr LONG_PTR mask = WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX |
      WS_MAXIMIZEBOX | WS_CLIPCHILDREN;
  CHECK((style & mask) == (capabilities & mask));
  CHECK(!IsWindowVisible(window));
  CHECK(GetForegroundWindow() == foreground);
  CHECK(shown == 0);
  const auto menu = GetSystemMenu(window, FALSE);
  CHECK(menu != nullptr);
  CHECK(GetMenuState(menu, SC_CLOSE, MF_BYCOMMAND) != static_cast<UINT>(-1));
  CHECK(GetMenuState(menu, SC_MINIMIZE, MF_BYCOMMAND) != static_cast<UINT>(-1));
  RECT frame{}, client{};
  CHECK(GetWindowRect(window, &frame));
  CHECK(GetClientRect(window, &client));
  CHECK(client.right == frame.right - frame.left);
  CHECK(client.bottom == frame.bottom - frame.top);
  CHECK(window_resize::CanHitTestResizeBorder(style, false) ==
      ((capabilities & WS_THICKFRAME) != 0));
}
}  // namespace

// This checks geometry and preserved native capabilities on hidden HWNDs.
// Actual DWM borders, caption painting and transition animations require a
// separate visible-window integration check; these assertions do not prove it.
int main() {
  CheckCalculations();
  const auto foreground = GetForegroundWindow();
  const auto instance = GetModuleHandleW(nullptr);
  constexpr auto name = L"DanPlayer.HiddenChromeRegression";
  WNDCLASSW cls{};
  cls.hInstance = instance;
  cls.lpszClassName = name;
  cls.lpfnWndProc = Proc;
  CHECK(RegisterClassW(&cls));
  for (const LONG_PTR original : {LONG_PTR{WS_OVERLAPPEDWINDOW},
         LONG_PTR{WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN}}) {
    for (const LONG top : {0L, 1L}) {
      fixture_top = top;
      fixture_fullscreen = false;
      HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, name,
          L"hidden chrome fixture", static_cast<DWORD>(original),
          100, 100, 800, 600, nullptr, nullptr, instance, nullptr);
      CHECK(window != nullptr);
      CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
      VerifyStylesAndClient(window, original, foreground);
      fixture_fullscreen = true;
      const auto fullscreen = original & ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
      SetWindowLongPtrW(window, GWL_STYLE, fullscreen);
      CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
      VerifyStylesAndClient(window, fullscreen, foreground);
      fixture_fullscreen = false;
      SetWindowLongPtrW(window, GWL_STYLE, original);
      CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
      VerifyStylesAndClient(window, original, foreground);
      // Size-lock retains the caption and system menu as well.
      SetWindowLongPtrW(window, GWL_STYLE, original & ~WS_THICKFRAME);
      CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
      VerifyStylesAndClient(window, original & ~WS_THICKFRAME, foreground);
      CHECK(DestroyWindow(window));
    }
  }
  CHECK(UnregisterClassW(name, instance));
  CHECK(GetForegroundWindow() == foreground);
  CHECK(shown == 0);
  std::cout << "Window chrome geometry: " << checks
            << " checks passed; shown=0 (visual integration separate)\n";
}
