#ifndef RUNNER_PALETTE_WINDOW_SHAPE_H_
#define RUNNER_PALETTE_WINDOW_SHAPE_H_
#include <windows.h>
#include <algorithm>

// Same 16 logical-pixel surface radius as AppShape.surface. Clip the opaque
// HWND itself on Windows 10/11, without layered/per-pixel-alpha composition.
inline bool ApplyPaletteRoundedRegion(HWND window, UINT dpi) {
  RECT rect{};
  if (!IsWindow(window) || !GetWindowRect(window, &rect)) return false;
  const int width = rect.right - rect.left;
  const int height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0 || dpi == 0) return false;
  const int diameter = std::min({MulDiv(32, dpi, 96), width, height});
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                  diameter, diameter);
  if (!region) return false;
  if (!SetWindowRgn(window, region, FALSE)) {
    DeleteObject(region);
    return false;
  }
  // Successful SetWindowRgn transfers ownership to Windows.
  return true;
}
#endif
