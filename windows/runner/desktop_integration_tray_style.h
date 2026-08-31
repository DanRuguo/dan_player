#ifndef RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_
#define RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_

#include <windows.h>

namespace desktop_integration {

inline RECT TrayIconCapsuleRect(const RECT& row, UINT dpi) {
  const auto px = [dpi](int value) { return MulDiv(value, static_cast<int>(dpi), 96); };
  const int height = px(30);
  const int top = row.top + (row.bottom - row.top - height) / 2;
  return {row.left + px(6), top, row.left + px(42), top + height};
}

// Stock DC objects avoid a brush/font/DIB allocation on every hover. The
// existing PopupPaintBuffer still commits the entire dirty area atomically.
inline void PaintTrayIconCapsule(HDC dc, const RECT& capsule, HFONT font,
                                  wchar_t glyph, COLORREF background,
                                  COLORREF foreground) {
  const int saved = SaveDC(dc);
  if (saved == 0) return;
  SelectObject(dc, GetStockObject(DC_BRUSH));
  SelectObject(dc, GetStockObject(NULL_PEN));
  SetDCBrushColor(dc, background);
  const int diameter = capsule.bottom - capsule.top;
  RoundRect(dc, capsule.left, capsule.top, capsule.right, capsule.bottom,
              diameter, diameter);
  SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, foreground);
  RECT bounds = capsule;
  DrawTextW(dc, &glyph, 1, &bounds,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  RestoreDC(dc, saved);
}

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_
