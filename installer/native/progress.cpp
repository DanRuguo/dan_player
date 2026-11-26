#include "installer_paint.h"

#include <commctrl.h>
#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cmath>

namespace {
HWND progress_window = nullptr;
ULONG_PTR graphics_token = 0;
COLORREF surface_color = RGB(246, 247, 252);
COLORREF accent_color = RGB(83, 88, 172);
int progress_value = 0;

BYTE BlendByte(BYTE base, BYTE tint, double ratio) {
  const double clamped = (std::max)(0.0, (std::min)(1.0, ratio));
  return static_cast<BYTE>(
      std::lround(base * (1.0 - clamped) + tint * clamped));
}

Gdiplus::Color TonalTrackColor(COLORREF surface, COLORREF accent, bool dark) {
  const double ratio = dark ? 0.24 : 0.16;
  return Gdiplus::Color(
      255,
      BlendByte(GetRValue(surface), GetRValue(accent), ratio),
      BlendByte(GetGValue(surface), GetGValue(accent), ratio),
      BlendByte(GetBValue(surface), GetBValue(accent), ratio));
}

void FillCapsule(Gdiplus::Graphics& graphics, Gdiplus::Brush& brush, float left,
                 float top, float width, float height) {
  if (width <= 0.0f || height <= 0.0f) return;
  if (width <= height) {
    graphics.FillEllipse(&brush, Gdiplus::RectF(left, top, width, height));
    return;
  }
  Gdiplus::GraphicsPath path;
  path.AddArc(left, top, height, height, 90.0f, 180.0f);
  path.AddArc(left + width - height, top, height, height, 270.0f, 180.0f);
  path.CloseFigure();
  graphics.FillPath(&brush, &path);
}

void PaintProgress(HWND window, HDC destination) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  if (!destination || bounds.right <= 0 || bounds.bottom <= 0) return;
  HDC memory = CreateCompatibleDC(destination);
  HBITMAP bitmap =
      CreateCompatibleBitmap(destination, bounds.right, bounds.bottom);
  if (!memory || !bitmap) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    return;
  }
  const auto previous = SelectObject(memory, bitmap);
  dan::installer::PaintParentSurface(window, memory, bounds, surface_color);
  const COLORREF actual_surface = GetPixel(memory, 0, 0);
  {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    const bool dark =
        (GetRValue(actual_surface) * 299 + GetGValue(actual_surface) * 587 +
         GetBValue(actual_surface) * 114) < 128000;
    const float width = static_cast<float>(bounds.right);
    const float height = static_cast<float>(bounds.bottom);
    const float gap = (std::max)(3.0f, height * 0.36f);

    Gdiplus::SolidBrush track(TonalTrackColor(actual_surface, accent_color, dark));
    Gdiplus::SolidBrush active(Gdiplus::Color(255, GetRValue(accent_color),
                                              GetGValue(accent_color),
                                              GetBValue(accent_color)));

    if (progress_value <= 0) {
      FillCapsule(graphics, track, 0.0f, 0.0f, width, height);
    } else if (progress_value >= 100) {
      FillCapsule(graphics, active, 0.0f, 0.0f, width, height);
    } else {
      const float active_w =
          (std::max)(height, width * static_cast<float>(progress_value) / 100.0f);
      FillCapsule(graphics, active, 0.0f, 0.0f, (std::min)(width, active_w),
                  height);
      const float track_left = active_w + gap;
      if (track_left + height * 0.6f < width) {
        FillCapsule(graphics, track, track_left, 0.0f, width - track_left,
                    height);
      }
    }

    // Material 3 Expressive end-stop dot on incomplete track
    if (progress_value < 97 && width > height * 3.0f) {
      const float dot = (std::max)(3.5f, height * 0.36f);
      graphics.FillEllipse(&active,
                           Gdiplus::RectF(width - height * 0.5f - dot * 0.5f,
                                          (height - dot) * 0.5f, dot, dot));
    }
  }
  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, previous);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

LRESULT CALLBACK ProgressProcedure(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR /*id*/,
                                   DWORD_PTR /*reference*/) {
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
  if (message == WM_NCDESTROY && progress_window == window) {
    progress_window = nullptr;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
}  // namespace

extern "C" __declspec(dllexport) int __stdcall DP_ProgressCreate(
    HWND gauge, COLORREF surface, COLORREF accent) {
  if (!IsWindow(gauge)) return 0;
  if (progress_window) {
    RemoveWindowSubclass(progress_window, ProgressProcedure, 1);
  }
  progress_window = nullptr;
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  if (SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast,
                            0) &&
      (contrast.dwFlags & HCF_HIGHCONTRASTON)) {
    return 0;
  }
  if (!graphics_token) {
    Gdiplus::GdiplusStartupInput options;
    if (Gdiplus::GdiplusStartup(&graphics_token, &options, nullptr) !=
        Gdiplus::Ok) {
      return 0;
    }
  }
  surface_color = surface;
  accent_color = accent;
  progress_value = 0;
  if (!SetWindowSubclass(gauge, ProgressProcedure, 1, 0)) return 0;
  progress_window = gauge;
  InvalidateRect(gauge, nullptr, FALSE);
  return 1;
}

extern "C" __declspec(dllexport) void __stdcall DP_ProgressSet(int current,
                                                               int maximum) {
  if (!progress_window || maximum <= 0) return;
  const int value = static_cast<int>(std::clamp(
      static_cast<double>(current) * 100.0 / maximum, 0.0, 100.0));
  if (value == progress_value) return;
  progress_value = value;
  InvalidateRect(progress_window, nullptr, FALSE);
}

extern "C" __declspec(dllexport) void __stdcall DP_ProgressClose() {
  if (progress_window && IsWindow(progress_window)) {
    RemoveWindowSubclass(progress_window, ProgressProcedure, 1);
  }
  progress_window = nullptr;
  if (graphics_token) Gdiplus::GdiplusShutdown(graphics_token);
  graphics_token = 0;
}
