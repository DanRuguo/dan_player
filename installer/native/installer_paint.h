#pragma once
#include <windows.h>
#include <uxtheme.h>

namespace dan::installer {
// Render the parent's own background into this child's memory DC, never read
// the desktop. VCL styles can replace a Pascal Color property; using the parent
// painting contract keeps alpha edges and rounded corners on the real surface.
inline void PaintParentSurface(HWND child, HDC dc, const RECT& bounds,
                               COLORREF fallback) {
  HBRUSH brush = CreateSolidBrush(fallback);
  FillRect(dc, &bounds, brush);
  DeleteObject(brush);
  const int saved = SaveDC(dc);
  DrawThemeParentBackground(child, dc, &bounds);
  if (saved) RestoreDC(dc, saved);
}
}  // namespace dan::installer
