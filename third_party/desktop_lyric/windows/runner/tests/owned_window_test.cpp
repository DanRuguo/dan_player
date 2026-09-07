// Hidden HWND metrics only. No ShowWindow, screenshot, GUI automation, settings
// or installed player. This does not claim DWM/real-engine visual acceptance.
#include <windows.h>
#include <iostream>
#include "palette_window_shape.h"
#include "win32_window.h"

using desktop_lyric_runner::Win32Window;

namespace {

bool HasRoundedOpaqueRegion(HWND window, UINT dpi) {
  RECT bounds{};
  if (!GetWindowRect(window, &bounds)) return false;
  const int width = bounds.right - bounds.left;
  const int height = bounds.bottom - bounds.top;
  const int radius = MulDiv(16, static_cast<int>(dpi), 96);
  HRGN region = CreateRectRgn(0, 0, 0, 0);
  if (!region) return false;
  const int type = GetWindowRgn(window, region);
  // A real HWND region, not DWM-only decoration: every extreme corner is
  // outside, while the opaque center and straight edges remain inside.
  bool matches = type == COMPLEXREGION &&
      !PtInRegion(region, 0, 0) &&
      !PtInRegion(region, width - 1, 0) &&
      !PtInRegion(region, 0, height - 1) &&
      !PtInRegion(region, width - 1, height - 1) &&
      PtInRegion(region, width / 2, height / 2) &&
      PtInRegion(region, width / 2, 2) &&
      PtInRegion(region, width / 2, height - 3) &&
      PtInRegion(region, 2, height / 2) &&
      PtInRegion(region, width - 3, height / 2);
  // These probes straddle the expected 16/24/32px corner arc. In particular,
  // a fixed 16px radius incorrectly includes the outer probe at 144/192 DPI.
  matches = matches &&
      !PtInRegion(region, radius / 4, radius / 4) &&
      PtInRegion(region, radius / 2, radius / 2);
  DeleteObject(region);  // GetWindowRgn copies into our separately owned HRGN.
  const auto extended = GetWindowLongPtr(window, GWL_EXSTYLE);
  return matches && !(extended & (WS_EX_LAYERED | WS_EX_TRANSPARENT)) &&
      !IsWindowVisible(window);
}

bool ApplyAndCheckRoundedRegion(HWND window, UINT dpi) {
  RECT before{}, after{};
  if (!GetWindowRect(window, &before) ||
      !ApplyPaletteRoundedRegion(window, dpi) ||
      !GetWindowRect(window, &after)) return false;
  // Applying the shape itself must never resize or move its own HWND either.
  return EqualRect(&before, &after) && HasRoundedOpaqueRegion(window, dpi);
}

}  // namespace

class MetricsWindow : public Win32Window {
 public:
  int sizes = 0;
  int positions = 0;
  int show_changes = 0;
 protected:
  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override {
    if (message == WM_SIZE) ++sizes;
    if (message == WM_WINDOWPOSCHANGING) {
      const auto* position = reinterpret_cast<WINDOWPOS*>(lparam);
      // Activation may reorder owned HWNDs; a z-order-only notification is not
      // a position/size change. Count only native geometry requests.
      if (!(position->flags & SWP_NOMOVE) || !(position->flags & SWP_NOSIZE)) ++positions;
    }
    if (message == WM_SHOWWINDOW) ++show_changes;
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
};

int main() {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  MetricsWindow owner;
  if (!owner.Create(L"Hidden lyric owner test", {100, 100}, {800, 160})) return 1;
  const HWND lyric_content = CreateWindowEx(0, L"STATIC", L"", WS_CHILD,
      0, 0, 800, 160, owner.GetHandle(), nullptr, GetModuleHandle(nullptr), nullptr);
  if (!lyric_content) return 11;
  owner.SetChildContent(lyric_content, false);
  RECT before{};
  GetWindowRect(owner.GetHandle(), &before);
  const auto styles = GetWindowLongPtr(owner.GetHandle(), GWL_STYLE);
  const auto exstyles = GetWindowLongPtr(owner.GetHandle(), GWL_EXSTYLE);
  const int sizes = owner.sizes, positions = owner.positions, shown = owner.show_changes;
  if (ApplyPaletteRoundedRegion(nullptr, 96)) return 14;
  for (int i = 0; i < 25; ++i) {
    MetricsWindow palette;
    if (!palette.CreateOwned(L"Hidden palette test", owner.GetHandle(),
                             {120, 120, 520, 640})) return 2;
    if (GetWindow(palette.GetHandle(), GW_OWNER) != owner.GetHandle()) return 3;
    if (IsWindowVisible(palette.GetHandle()) || IsWindowVisible(owner.GetHandle())) return 4;
    if (!(GetWindowLongPtr(palette.GetHandle(), GWL_EXSTYLE) & WS_EX_TOOLWINDOW)) return 5;
    const HWND palette_content = CreateWindowEx(0, L"STATIC", L"", WS_CHILD,
        0, 0, 400, 520, palette.GetHandle(), nullptr, GetModuleHandle(nullptr), nullptr);
    SetFocus(palette_content);
    if (GetFocus() != palette_content) return 12;
    SendMessage(owner.GetHandle(), WM_ACTIVATE, WA_INACTIVE,
                reinterpret_cast<LPARAM>(palette.GetHandle()));
    if (GetFocus() != palette_content) return 13;
    for (const UINT dpi : {96u, 144u, 192u}) {
      if (!ApplyAndCheckRoundedRegion(palette.GetHandle(), dpi)) return 15;
      // Exercise both shrinking and growing on the same HWND: an old region
      // must neither leave square corners nor clip the newly enlarged center.
      for (const SIZE size : {SIZE{220, 100}, SIZE{540, 360}}) {
        if (!SetWindowPos(palette.GetHandle(), nullptr, 0, 0,
                          size.cx, size.cy,
                          SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) return 16;
        if (!ApplyAndCheckRoundedRegion(palette.GetHandle(), dpi)) return 17;
        RECT owner_after{};
        if (!GetWindowRect(owner.GetHandle(), &owner_after) ||
            !EqualRect(&before, &owner_after) || owner.sizes != sizes ||
            owner.positions != positions || owner.show_changes != shown ||
            IsWindowVisible(owner.GetHandle())) return 18;
      }
    }
    const HWND destroyed_palette = palette.GetHandle();
    palette.Destroy();
    if (ApplyPaletteRoundedRegion(destroyed_palette, 192)) return 19;
    RECT after{};
    GetWindowRect(owner.GetHandle(), &after);
    if (!EqualRect(&before, &after) || owner.sizes != sizes ||
        owner.positions != positions || owner.show_changes != shown) return 6;
    if (GetWindowLongPtr(owner.GetHandle(), GWL_STYLE) != styles ||
        GetWindowLongPtr(owner.GetHandle(), GWL_EXSTYLE) != exstyles) return 7;
  }
  MSG message{};
  if (PeekMessage(&message, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE)) return 8;
  MetricsWindow child;
  child.CreateOwned(L"Hidden owner shutdown test", owner.GetHandle(), {120,120,520,640});
  HWND child_handle = child.GetHandle();
  owner.Destroy();
  if (IsWindow(child_handle)) return 9;
  if (PeekMessage(&message, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE)) return 10;
  std::cout << "PASS: 25 hidden owned-HWND cycles; owner bounds/styles unchanged; "
               "0 owner resize/move/show events (z-order-only notifications excluded); no inactive-owner focus theft; "
               "opaque rounded regions at 96/144/192 DPI survive shrink/grow; corners excluded, center included; "
               "null/destroyed HWNDs rejected; "
               "no WM_QUIT; owner closes child.\n";
  return 0;
}
