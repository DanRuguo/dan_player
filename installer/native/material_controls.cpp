// Material-like chrome on real Windows BUTTON controls: native focus, keyboard
// activation and accessibility remain owned by the original BUTTON procedure.
#include <windows.h>
#include <commctrl.h>
#include <objidl.h>
#include <gdiplus.h>
#include <dwmapi.h>
#include "installer_paint.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <string>

namespace {
struct ButtonStyle {
  COLORREF surface, accent, text;
  bool primary, hovered = false;
  int radius;
};
ULONG_PTR graphics_token = 0;
std::map<HWND, std::unique_ptr<ButtonStyle>> buttons;
Gdiplus::Color Color(COLORREF value, BYTE alpha = 255) {
  return Gdiplus::Color(alpha, GetRValue(value), GetGValue(value), GetBValue(value));
}
double Luminance(COLORREF value) {
  const auto linear=[](BYTE component) {
    const double channel=component/255.0;
    return channel<=.04045?channel/12.92:std::pow((channel+.055)/1.055,2.4);
  };
  return .2126*linear(GetRValue(value))+.7152*linear(GetGValue(value))+.0722*linear(GetBValue(value));
}
double Contrast(COLORREF a,COLORREF b) {
  const double x=Luminance(a),y=Luminance(b);
  return ((std::max)(x,y)+.05)/((std::min)(x,y)+.05);
}
COLORREF ReadableText(COLORREF background) {
  return Contrast(RGB(255,255,255),background)>=Contrast(RGB(0,0,0),background)
      ?RGB(255,255,255):RGB(0,0,0);
}
bool HighContrast() {
  HIGHCONTRASTW value{sizeof(value), 0, nullptr};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(value), &value, 0) &&
      (value.dwFlags & HCF_HIGHCONTRASTON);
}
void Rounded(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& r, float radius) {
  const float diameter = (std::min)(radius * 2, (std::min)(r.Width, r.Height));
  path.AddArc(r.X, r.Y, diameter, diameter, 180, 90);
  path.AddArc(r.GetRight() - diameter, r.Y, diameter, diameter, 270, 90);
  path.AddArc(r.GetRight() - diameter, r.GetBottom() - diameter, diameter, diameter, 0, 90);
  path.AddArc(r.X, r.GetBottom() - diameter, diameter, diameter, 90, 90);
  path.CloseFigure();
}
void PaintButton(HWND window, HDC destination, const ButtonStyle& style) {
  RECT bounds{}; GetClientRect(window, &bounds);
  if (bounds.right <= 0 || bounds.bottom <= 0) return;
  HDC memory = CreateCompatibleDC(destination);
  HBITMAP bitmap = CreateCompatibleBitmap(destination, bounds.right, bounds.bottom);
  if (!memory || !bitmap) { if (bitmap) DeleteObject(bitmap); if (memory) DeleteDC(memory); return; }
  const auto old_bitmap = SelectObject(memory, bitmap);
  const bool enabled = IsWindowEnabled(window) != FALSE;
  const bool pressed = (SendMessageW(window, BM_GETSTATE, 0, 0) & BST_PUSHED) != 0;
  COLORREF foreground = style.primary ? style.text : style.accent;
  dan::installer::PaintParentSurface(window, memory, bounds, style.surface);
  const COLORREF actual_surface=GetPixel(memory,0,0);
  if(!style.primary&&Contrast(foreground,actual_surface)<4.5)
    foreground=ReadableText(actual_surface);
  {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath path;
    Rounded(path, Gdiplus::RectF(1, 1, static_cast<float>(bounds.right - 2),
        static_cast<float>(bounds.bottom - 2)), static_cast<float>(style.radius));
    if (style.primary) {
      Gdiplus::SolidBrush fill(Color(style.accent, enabled ? 255 : 95));
      graphics.FillPath(&fill, &path);
    }
    if (!style.primary) {
      Gdiplus::Pen outline(Color(style.accent, enabled ? 140 : 70), 1);
      graphics.DrawPath(&outline, &path);
    }
    if (enabled && (style.hovered || pressed)) {
      Gdiplus::SolidBrush state(Color(foreground, pressed ? 30 : 18));
      graphics.FillPath(&state, &path);
    }
  }
  const HFONT font = reinterpret_cast<HFONT>(SendMessageW(window, WM_GETFONT, 0, 0));
  const auto old_font = SelectObject(memory, font ? font : GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(memory, TRANSPARENT);
  SetTextColor(memory, enabled ? foreground : GetSysColor(COLOR_GRAYTEXT));
  std::wstring caption(static_cast<size_t>(GetWindowTextLengthW(window)) + 1, L'\0');
  const int count = GetWindowTextW(window, caption.data(), static_cast<int>(caption.size()));
  UINT format = DT_CENTER | DT_VCENTER | DT_SINGLELINE;
  if (SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEACCEL) format |= DT_HIDEPREFIX;
  DrawTextW(memory, caption.data(), count, &bounds, format);
  if (GetFocus() == window && !(SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEFOCUS)) {
    RECT focus = bounds; InflateRect(&focus, -5, -5); DrawFocusRect(memory, &focus);
  }
  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, old_font); SelectObject(memory, old_bitmap);
  DeleteObject(bitmap); DeleteDC(memory);
}
LRESULT CALLBACK ButtonProcedure(HWND window, UINT message, WPARAM wparam,
    LPARAM lparam, UINT_PTR id, DWORD_PTR reference) {
  auto* style = reinterpret_cast<ButtonStyle*>(reference);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, ButtonProcedure, id);
    const auto result = DefSubclassProc(window, message, wparam, lparam);
    buttons.erase(window);
    return result;
  }
  if (!HighContrast()) {
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{}; const HDC dc = BeginPaint(window, &paint);
      PaintButton(window, dc, *style); EndPaint(window, &paint); return 0;
    }
    if (message == WM_PRINTCLIENT) { PaintButton(window, reinterpret_cast<HDC>(wparam), *style); return 0; }
  }
  if (message == WM_MOUSEMOVE && !style->hovered) {
    style->hovered = true;
    TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0}; TrackMouseEvent(&track);
    InvalidateRect(window, nullptr, FALSE);
  } else if (message == WM_MOUSELEAVE) { style->hovered = false; InvalidateRect(window, nullptr, FALSE); }
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  if (message == BM_SETSTATE || message == WM_ENABLE || message == WM_SETFOCUS ||
      message == WM_KILLFOCUS || message == WM_SETTEXT || message == WM_THEMECHANGED ||
      message == WM_UPDATEUISTATE) InvalidateRect(window, nullptr, FALSE);
  return result;
}
}  // namespace

extern "C" __declspec(dllexport) COLORREF __stdcall DP_AccentColor() {
  DWORD argb = 0; BOOL opaque = FALSE;
  if (SUCCEEDED(DwmGetColorizationColor(&argb, &opaque)))
    return RGB((argb >> 16) & 255, (argb >> 8) & 255, argb & 255);
  return RGB(83, 88, 172);
}
extern "C" __declspec(dllexport) int __stdcall DP_StyleButton(
    HWND window, COLORREF surface, COLORREF accent, BOOL primary, int radius) {
  if (!IsWindow(window) || radius < 1 || radius > 96) return 0;
  if (!graphics_token) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&graphics_token, &input, nullptr) != Gdiplus::Ok) return 0;
  }
  // Choose actual foreground contrast, not an assumed white-on-any-accent.
  const COLORREF text = ReadableText(accent);
  auto style = std::make_unique<ButtonStyle>(ButtonStyle{surface, accent, text, primary != FALSE, false, radius});
  if (!SetWindowSubclass(window, ButtonProcedure, 1, reinterpret_cast<DWORD_PTR>(style.get()))) return 0;
  buttons[window] = std::move(style);
  InvalidateRect(window, nullptr, FALSE);
  return 1;
}
extern "C" __declspec(dllexport) void __stdcall DP_CloseControls() {
  for (const auto& entry : buttons) if (IsWindow(entry.first)) RemoveWindowSubclass(entry.first, ButtonProcedure, 1);
  buttons.clear();
  if (graphics_token) Gdiplus::GdiplusShutdown(graphics_token);
  graphics_token = 0;
}
