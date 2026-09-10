#include "../../../third_party/desktop_lyric/windows/runner/window_chrome_policy.h"
#include "../window_resize_policy.h"

#include <dwmapi.h>
#include <iostream>
#include <cstdlib>

namespace {
int checks = 0;
int shown = 0;
void Check(bool pass, int line) {
  ++checks;
  if (!pass) {
    std::cerr << "FAIL custom title bar line " << line << '\n';
    std::exit(1);
  }
}
#define CHECK(value) Check((value), __LINE__)
LRESULT CALLBACK Proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_SHOWWINDOW && wparam) ++shown;
  if (message == WM_STYLECHANGING) window_chrome::KeepCustomTitleBar(wparam, lparam);
  // Same full-client calculation as the hidden-title fullscreen plugin path.
  if (message == WM_NCCALCSIZE && wparam) return 0;
  return DefWindowProcW(window, message, wparam, lparam);
}
constexpr UINT kRefresh = SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
    SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE;
void Verify(HWND window, LONG_PTR capabilities, bool maximized, HWND foreground) {
  const auto style = GetWindowLongPtrW(window, GWL_STYLE);
  CHECK((style & WS_CAPTION) == 0);
  constexpr LONG_PTR mask = WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX |
      WS_MAXIMIZEBOX | WS_CLIPCHILDREN;
  CHECK((style & mask) == (capabilities & mask));
  CHECK((IsZoomed(window) != FALSE) == maximized);
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
  const auto top_right = MAKELPARAM(frame.right - 32, frame.top + 20);
  const auto hit = SendMessageW(window, WM_NCHITTEST, 0, top_right);
  CHECK(hit != HTMINBUTTON && hit != HTMAXBUTTON && hit != HTCLOSE);
  CHECK(window_resize::CanHitTestResizeBorder(style, maximized) ==
      ((capabilities & WS_THICKFRAME) != 0 && !maximized));
}
}  // namespace

// Real hidden HWNDs only: no ShowWindow, Flutter, playback, user files, or
// foreground changes. Styles replay the plugin's fullscreen and resize calls.
int main() {
  constexpr LONG_PTR original = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN;
  CHECK((original & WS_CAPTION) == WS_CAPTION);
  CHECK(window_chrome::CustomTitleBarStyle(original) == (original & ~WS_CAPTION));
  STYLESTRUCT ignored{WS_CAPTION, WS_CAPTION};
  window_chrome::KeepCustomTitleBar(static_cast<WPARAM>(GWL_EXSTYLE), reinterpret_cast<LPARAM>(&ignored));
  CHECK(ignored.styleNew == WS_CAPTION);
  window_chrome::KeepCustomTitleBar(static_cast<WPARAM>(GWL_STYLE), 0);
  const auto foreground = GetForegroundWindow();
  const auto instance = GetModuleHandleW(nullptr);
  constexpr auto name = L"DanPlayer.HiddenChromeRegression";
  WNDCLASSW cls{};
  cls.hInstance = instance;
  cls.lpszClassName = name;
  cls.lpfnWndProc = Proc;
  CHECK(RegisterClassW(&cls));
  for (bool maximized : {false, true}) {
    const DWORD state = maximized ? WS_MAXIMIZE : 0;
    HWND window = CreateWindowExW(WS_EX_TOOLWINDOW, name, L"hidden chrome fixture",
        static_cast<DWORD>(window_chrome::CustomTitleBarStyle(original)) | state,
        100, 100, 800, 600, nullptr, nullptr, instance, nullptr);
    CHECK(window != nullptr);
    CHECK(window_chrome::InitializeCustomTitleBar(window));
    CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
    Verify(window, original, maximized, foreground);
    // The native acrylic frame cannot restore a title bar that has no caption
    // style; exercise both composition modes without showing this HWND.
    for (const MARGINS margins : {MARGINS{0, 0, 0, 0}, MARGINS{-1, -1, -1, -1}}) {
      CHECK(SUCCEEDED(DwmExtendFrameIntoClientArea(window, &margins)));
      Verify(window, original, maximized, foreground);
    }
    const auto fullscreen = (original | state) & ~(WS_THICKFRAME | WS_MAXIMIZEBOX);
    SetWindowLongPtrW(window, GWL_STYLE, fullscreen);
    CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
    Verify(window, fullscreen, maximized, foreground);
    // Saved legacy/plugin styles can contain WS_CAPTION. Sanitize before the
    // style is committed, avoiding a transient native caption during restore.
    SetWindowLongPtrW(window, GWL_STYLE, original | state);
    CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
    Verify(window, original, maximized, foreground);
    SetWindowLongPtrW(window, GWL_STYLE, (original | state) & ~WS_THICKFRAME);
    CHECK(SetWindowPos(window, nullptr, 0, 0, 0, 0, kRefresh));
    Verify(window, original & ~WS_THICKFRAME, maximized, foreground);
    CHECK(DestroyWindow(window));
  }
  CHECK(UnregisterClassW(name, instance));
  CHECK(GetForegroundWindow() == foreground);
  CHECK(shown == 0);
  std::cout << "Custom title bar: " << checks << " checks passed; shown=0\n";
}
