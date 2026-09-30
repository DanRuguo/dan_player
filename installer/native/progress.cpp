#include "installer_paint.h"

#include <objidl.h>
#include <gdiplus.h>
#include <commctrl.h>

#include <algorithm>

namespace {
HWND progress_window = nullptr;
ULONG_PTR graphics_token = 0;
COLORREF surface_color = RGB(243, 243, 243);
COLORREF accent_color = RGB(83, 88, 172);
int progress_value = 0;

void FillPill(Gdiplus::Graphics& graphics, Gdiplus::Brush& brush,
              float width, float height) {
  if (width <= 0 || height <= 0) return;
  if (width <= height) {
    graphics.FillEllipse(&brush, Gdiplus::RectF(0, 0, width, height));
    return;
  }
  graphics.FillEllipse(&brush, Gdiplus::RectF(0, 0, height, height));
  graphics.FillRectangle(&brush, Gdiplus::RectF(height / 2, 0, width - height, height));
  graphics.FillEllipse(&brush, Gdiplus::RectF(width - height, 0, height, height));
}

void PaintProgress(HWND window, HDC dc) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  if (!dc || bounds.right <= 0 || bounds.bottom <= 0) return;
  dan::installer::PaintParentSurface(window, dc, bounds, surface_color);
  Gdiplus::Graphics graphics(dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  const bool dark = (GetRValue(surface_color) * 299 +
      GetGValue(surface_color) * 587 + GetBValue(surface_color) * 114) < 128000;
  Gdiplus::SolidBrush track(Gdiplus::Color(255, dark ? 83 : 216,
      dark ? 83 : 216, dark ? 83 : 216));
  const float width = static_cast<float>(bounds.right);
  const float height = static_cast<float>(bounds.bottom);
  FillPill(graphics, track, width, height);
  if (progress_value > 0) {
    Gdiplus::SolidBrush fill(Gdiplus::Color(255, GetRValue(accent_color),
        GetGValue(accent_color), GetBValue(accent_color)));
    FillPill(graphics, fill, width * progress_value / 100.0f, height);
  }
}

LRESULT CALLBACK ProgressProcedure(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR, DWORD_PTR) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    PaintProgress(window, dc);
    EndPaint(window, &paint);
    return 0;
  }
  if (message == WM_PRINT || message == WM_PRINTCLIENT) {
    PaintProgress(window, reinterpret_cast<HDC>(wparam));
    return 0;
  }
  if (message == WM_NCDESTROY && progress_window == window) progress_window = nullptr;
  return DefSubclassProc(window, message, wparam, lparam);
}
}  // namespace

extern "C" __declspec(dllexport) int __stdcall DP_ProgressCreate(
    HWND gauge, COLORREF surface, COLORREF accent) {
  if (!IsWindow(gauge)) return 0;
  if (progress_window) RemoveWindowSubclass(progress_window, ProgressProcedure, 1);
  progress_window = nullptr;
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
      (contrast.dwFlags & HCF_HIGHCONTRASTON)) return 0;  // Keep Inno's accessible native bar.
  if (!graphics_token) {
    Gdiplus::GdiplusStartupInput options;
    if (Gdiplus::GdiplusStartup(&graphics_token, &options, nullptr) != Gdiplus::Ok) return 0;
  }
  surface_color = surface;
  accent_color = accent;
  progress_value = 0;
  if (!SetWindowSubclass(gauge, ProgressProcedure, 1, 0)) return 0;
  progress_window = gauge;
  InvalidateRect(gauge, nullptr, FALSE);
  return 1;
}

extern "C" __declspec(dllexport) void __stdcall DP_ProgressSet(int current, int maximum) {
  if (!progress_window || maximum <= 0) return;
  const int value = static_cast<int>(std::clamp(
      static_cast<double>(current) * 100.0 / maximum, 0.0, 100.0));
  if (value == progress_value) return;
  progress_value = value;
  InvalidateRect(progress_window, nullptr, FALSE);
}

extern "C" __declspec(dllexport) void __stdcall DP_ProgressClose() {
  if (progress_window && IsWindow(progress_window))
    RemoveWindowSubclass(progress_window, ProgressProcedure, 1);
  progress_window = nullptr;
  if (graphics_token) Gdiplus::GdiplusShutdown(graphics_token);
  graphics_token = 0;
}
