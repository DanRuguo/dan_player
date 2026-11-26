#ifndef RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_
#define RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_

#ifndef GDIPVER
#define GDIPVER 0x0110
#endif
#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <cstdint>

namespace desktop_integration {

inline Gdiplus::Color GdipColorFromColorRef(COLORREF color, BYTE alpha = 255) {
  return Gdiplus::Color(alpha, GetRValue(color), GetGValue(color),
                        GetBValue(color));
}

inline void BuildRoundedRectPath(Gdiplus::GraphicsPath* path,
                                 const Gdiplus::RectF& bounds, float radius) {
  path->Reset();
  const float max_r = std::min(bounds.Width, bounds.Height) * 0.5f;
  const float r = std::clamp(radius, 0.0f, max_r);
  if (r <= 0.5f) {
    path->AddRectangle(bounds);
    return;
  }
  const float d = r * 2.0f;
  path->AddArc(bounds.X, bounds.Y, d, d, 180.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.Y, d, d, 270.0f, 90.0f);
  path->AddArc(bounds.GetRight() - d, bounds.GetBottom() - d, d, d, 0.0f,
               90.0f);
  path->AddArc(bounds.X, bounds.GetBottom() - d, d, d, 90.0f, 90.0f);
  path->CloseFigure();
}

inline void FillSmoothRoundRect(Gdiplus::Graphics& g, const RECT& rc,
                                float radius, Gdiplus::Color fill,
                                Gdiplus::Color border = Gdiplus::Color(0, 0, 0, 0),
                                float border_width = 1.0f) {
  const Gdiplus::RectF bounds(
      static_cast<float>(rc.left), static_cast<float>(rc.top),
      static_cast<float>(rc.right - rc.left),
      static_cast<float>(rc.bottom - rc.top));
  if (bounds.Width <= 0.0f || bounds.Height <= 0.0f) return;
  Gdiplus::GraphicsPath path;
  BuildRoundedRectPath(&path, bounds, radius);
  if (fill.GetA() > 0) {
    Gdiplus::SolidBrush brush(fill);
    g.FillPath(&brush, &path);
  }
  if (border.GetA() > 0 && border_width > 0.0f) {
    const float inset = border_width * 0.5f;
    Gdiplus::RectF stroke_bounds(bounds.X + inset, bounds.Y + inset,
                                 std::max(0.0f, bounds.Width - border_width),
                                 std::max(0.0f, bounds.Height - border_width));
    Gdiplus::GraphicsPath stroke_path;
    BuildRoundedRectPath(&stroke_path, stroke_bounds,
                         std::max(0.0f, radius - inset));
    Gdiplus::Pen pen(border, border_width);
    g.DrawPath(&pen, &stroke_path);
  }
}

// Draws a rounded album cover (from premultiplied BGRA pixels) or a sleek
// layered tonal emblem with the app icon / vinyl rings when no cover is loaded.
inline void PaintTrayArtworkBadge(HDC dc, Gdiplus::Graphics& g,
                                  const RECT& bounds, float radius,
                                  const std::uint8_t* bgra_pixels,
                                  int pixel_edge, HICON app_icon,
                                  COLORREF accent, COLORREF card_bg,
                                  bool dark_mode, bool has_track) {
  const int w = bounds.right - bounds.left;
  const int h = bounds.bottom - bounds.top;
  if (w <= 0 || h <= 0) return;

  if (bgra_pixels && pixel_edge > 0) {
    Gdiplus::GraphicsPath clip;
    BuildRoundedRectPath(
        &clip,
        Gdiplus::RectF(static_cast<float>(bounds.left),
                       static_cast<float>(bounds.top), static_cast<float>(w),
                       static_cast<float>(h)),
        radius);
    const auto state = g.Save();
    g.SetClip(&clip);
    g.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    Gdiplus::Bitmap cover(pixel_edge, pixel_edge, pixel_edge * 4,
                          PixelFormat32bppPARGB,
                          const_cast<BYTE*>(bgra_pixels));
    g.DrawImage(&cover, Gdiplus::Rect(bounds.left, bounds.top, w, h));
    g.Restore(state);
    FillSmoothRoundRect(
        g, bounds, radius, Gdiplus::Color(0, 0, 0, 0),
        Gdiplus::Color(dark_mode ? 42 : 28, dark_mode ? 255 : 0,
                       dark_mode ? 255 : 0, dark_mode ? 255 : 0),
        1.0f);
    return;
  }

  // Fallback gradient badge with vinyl groove rings (when playing) or app icon.
  const Gdiplus::RectF rectf(static_cast<float>(bounds.left),
                             static_cast<float>(bounds.top),
                             static_cast<float>(w), static_cast<float>(h));
  Gdiplus::GraphicsPath badge_path;
  BuildRoundedRectPath(&badge_path, rectf, radius);
  const BYTE top_mix = dark_mode ? 110 : 62;
  const BYTE bot_mix = dark_mode ? 58 : 28;
  auto mix = [&](BYTE a) {
    return Gdiplus::Color(
        255,
        static_cast<BYTE>((GetRValue(accent) * a + GetRValue(card_bg) * (255 - a)) / 255),
        static_cast<BYTE>((GetGValue(accent) * a + GetGValue(card_bg) * (255 - a)) / 255),
        static_cast<BYTE>((GetBValue(accent) * a + GetBValue(card_bg) * (255 - a)) / 255));
  };
  Gdiplus::LinearGradientBrush grad(
      Gdiplus::PointF(rectf.X, rectf.Y),
      Gdiplus::PointF(rectf.GetRight(), rectf.GetBottom()), mix(top_mix),
      mix(bot_mix));
  g.FillPath(&grad, &badge_path);

  if (has_track) {
    // Sleek minimal vinyl disc emblem when a song has no embedded cover.
    const float cx = rectf.X + rectf.Width * 0.5f;
    const float cy = rectf.Y + rectf.Height * 0.5f;
    const float disc_r = std::min(rectf.Width, rectf.Height) * 0.34f;
    Gdiplus::SolidBrush disc_brush(
        Gdiplus::Color(dark_mode ? 175 : 195, 28, 28, 34));
    g.FillEllipse(&disc_brush, cx - disc_r, cy - disc_r, disc_r * 2.0f,
                  disc_r * 2.0f);
    Gdiplus::Pen groove_pen(Gdiplus::Color(55, 255, 255, 255), 1.0f);
    const float gr = disc_r * 0.68f;
    g.DrawEllipse(&groove_pen, cx - gr, cy - gr, gr * 2.0f, gr * 2.0f);
    const float label_r = disc_r * 0.36f;
    Gdiplus::SolidBrush center_brush(GdipColorFromColorRef(accent, 240));
    g.FillEllipse(&center_brush, cx - label_r, cy - label_r, label_r * 2.0f,
                  label_r * 2.0f);
    const float hole_r = std::max(1.5f, disc_r * 0.11f);
    Gdiplus::SolidBrush hole_brush(Gdiplus::Color(235, 250, 250, 252));
    g.FillEllipse(&hole_brush, cx - hole_r, cy - hole_r, hole_r * 2.0f,
                  hole_r * 2.0f);
  } else if (app_icon) {
    const int icon_edge = std::max(16, (w * 62) / 100);
    const int ix = bounds.left + (w - icon_edge) / 2;
    const int iy = bounds.top + (h - icon_edge) / 2;
    DrawIconEx(dc, ix, iy, app_icon, icon_edge, icon_edge, 0, nullptr,
               DI_NORMAL);
  }

  FillSmoothRoundRect(g, bounds, radius, Gdiplus::Color(0, 0, 0, 0),
                      GdipColorFromColorRef(accent, dark_mode ? 54 : 34), 1.0f);
}

inline void PaintCenteredGlyph(HDC dc, const RECT& bounds, HFONT font,
                               wchar_t glyph, COLORREF color) {
  if (!glyph) return;
  const int saved = SaveDC(dc);
  if (saved == 0) return;
  SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, color);
  RECT rc = bounds;
  DrawTextW(dc, &glyph, 1, &rc,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  RestoreDC(dc, saved);
}

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_TRAY_STYLE_H_
