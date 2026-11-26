// Material 3 Expressive chrome on real Windows controls: native focus, keyboard
// activation, tab order and accessibility remain owned by the underlying HWNDs.
#include <windows.h>
#include <commctrl.h>
#include <dwmapi.h>
#include <objidl.h>
#include <gdiplus.h>

#include "installer_paint.h"

#include <algorithm>
#include <cmath>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace {
constexpr DWORD kDwmUseImmersiveDarkMode = 20;
constexpr DWORD kDwmWindowCornerPreference = 33;
constexpr DWORD kDwmBorderColor = 34;
constexpr DWORD kDwmCaptionColor = 35;
constexpr DWORD kDwmCornerRound = 2;

struct ButtonStyle {
  COLORREF surface;
  COLORREF accent;
  COLORREF text;
  bool primary;
  bool hovered = false;
  int radius;
};

struct CheckCardStyle {
  COLORREF surface;
  COLORREF accent;
  bool hovered = false;
  int radius;
};

struct SurfaceCardSpec {
  COLORREF surface;
  COLORREF accent;
  int radius;
  bool tonal_tint;
};

struct InfoCardStyle {
  COLORREF surface;
  COLORREF accent;
  int radius;
  int pad_x;
  int pad_y;
  bool centered;
};

ULONG_PTR graphics_token = 0;
std::map<HWND, std::unique_ptr<ButtonStyle>> buttons;
std::map<HWND, std::unique_ptr<CheckCardStyle>> check_cards;
std::map<HWND, std::unique_ptr<SurfaceCardSpec>> surface_cards;
std::map<HWND, std::unique_ptr<InfoCardStyle>> info_cards;

bool EnsureGdiPlus() {
  if (!graphics_token) {
    Gdiplus::GdiplusStartupInput input;
    if (Gdiplus::GdiplusStartup(&graphics_token, &input, nullptr) !=
        Gdiplus::Ok) {
      graphics_token = 0;
      return false;
    }
  }
  return true;
}

BYTE MixByte(BYTE a, BYTE b, double t) {
  const double clamped = (std::max)(0.0, (std::min)(1.0, t));
  return static_cast<BYTE>(std::lround(a * (1.0 - clamped) + b * clamped));
}

COLORREF MixColorRef(COLORREF a, COLORREF b, double t) {
  return RGB(MixByte(GetRValue(a), GetRValue(b), t),
             MixByte(GetGValue(a), GetGValue(b), t),
             MixByte(GetBValue(a), GetBValue(b), t));
}

Gdiplus::Color Color(COLORREF value, BYTE alpha = 255) {
  return Gdiplus::Color(alpha, GetRValue(value), GetGValue(value),
                        GetBValue(value));
}

double Luminance(COLORREF value) {
  const auto linear = [](BYTE component) {
    const double channel = component / 255.0;
    return channel <= 0.04045 ? channel / 12.92
                              : std::pow((channel + 0.055) / 1.055, 2.4);
  };
  return 0.2126 * linear(GetRValue(value)) +
         0.7152 * linear(GetGValue(value)) +
         0.0722 * linear(GetBValue(value));
}

double Contrast(COLORREF a, COLORREF b) {
  const double x = Luminance(a);
  const double y = Luminance(b);
  return ((std::max)(x, y) + 0.05) / ((std::min)(x, y) + 0.05);
}

COLORREF ReadableText(COLORREF background) {
  return Contrast(RGB(255, 255, 255), background) >=
                 Contrast(RGB(0, 0, 0), background)
             ? RGB(255, 255, 255)
             : RGB(0, 0, 0);
}

bool IsDarkSurface(COLORREF surface) {
  return (GetRValue(surface) * 299 + GetGValue(surface) * 587 +
          GetBValue(surface) * 114) < 128000;
}

bool HighContrast() {
  HIGHCONTRASTW value{sizeof(value), 0, nullptr};
  return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(value), &value, 0) &&
         (value.dwFlags & HCF_HIGHCONTRASTON);
}

void Rounded(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& r,
             float radius) {
  const float diameter =
      (std::min)(radius * 2.0f, (std::min)(r.Width, r.Height));
  if (diameter <= 0.5f) {
    path.AddRectangle(r);
    return;
  }
  path.AddArc(r.X, r.Y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(r.GetRight() - diameter, r.Y, diameter, diameter, 270.0f, 90.0f);
  path.AddArc(r.GetRight() - diameter, r.GetBottom() - diameter, diameter,
              diameter, 0.0f, 90.0f);
  path.AddArc(r.X, r.GetBottom() - diameter, diameter, diameter, 90.0f, 90.0f);
  path.CloseFigure();
}

void PaintButton(HWND window, HDC destination, const ButtonStyle& style) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  if (bounds.right <= 0 || bounds.bottom <= 0) return;
  HDC memory = CreateCompatibleDC(destination);
  HBITMAP bitmap =
      CreateCompatibleBitmap(destination, bounds.right, bounds.bottom);
  if (!memory || !bitmap) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    return;
  }
  const auto old_bitmap = SelectObject(memory, bitmap);
  const bool enabled = IsWindowEnabled(window) != FALSE;
  const bool pressed =
      (SendMessageW(window, BM_GETSTATE, 0, 0) & BST_PUSHED) != 0;

  dan::installer::PaintParentSurface(window, memory, bounds, style.surface);
  const COLORREF actual_surface = GetPixel(memory, 0, 0);
  const bool dark = IsDarkSurface(actual_surface);

  const COLORREF tonal_bg = MixColorRef(
      actual_surface, style.accent,
      pressed ? (dark ? 0.30 : 0.20)
              : (style.hovered ? (dark ? 0.24 : 0.15)
                               : (dark ? 0.16 : 0.09)));
  COLORREF foreground =
      style.primary ? style.text
                    : MixColorRef(style.accent,
                                  dark ? RGB(236, 240, 255) : RGB(22, 26, 40),
                                  dark ? 0.35 : 0.22);
  if (!style.primary && Contrast(foreground, tonal_bg) < 4.5) {
    foreground = ReadableText(tonal_bg);
  }

  {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath path;
    const float w = static_cast<float>(bounds.right - 2);
    const float h = static_cast<float>(bounds.bottom - 2);
    const float pill_radius =
        (std::min)(static_cast<float>(style.radius), h / 2.0f);
    Rounded(path, Gdiplus::RectF(1.0f, 1.0f, w, h), pill_radius);

    if (style.primary) {
      const COLORREF primary_fill =
          pressed ? MixColorRef(style.accent, RGB(0, 0, 0), 0.14)
                  : (style.hovered
                         ? MixColorRef(style.accent, RGB(255, 255, 255), 0.10)
                         : style.accent);
      Gdiplus::SolidBrush fill(Color(primary_fill, enabled ? 255 : 96));
      graphics.FillPath(&fill, &path);
    } else {
      Gdiplus::SolidBrush fill(Color(tonal_bg, enabled ? 255 : 110));
      graphics.FillPath(&fill, &path);
      const COLORREF border_col = MixColorRef(
          actual_surface, style.accent,
          style.hovered ? (dark ? 0.56 : 0.44) : (dark ? 0.36 : 0.26));
      Gdiplus::Pen outline(Color(border_col, enabled ? 220 : 85), 1.15f);
      graphics.DrawPath(&outline, &path);
    }
  }

  const HFONT font =
      reinterpret_cast<HFONT>(SendMessageW(window, WM_GETFONT, 0, 0));
  const auto old_font =
      SelectObject(memory, font ? font : GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(memory, TRANSPARENT);
  SetTextColor(memory, enabled ? foreground : GetSysColor(COLOR_GRAYTEXT));
  std::wstring caption(
      static_cast<size_t>(GetWindowTextLengthW(window)) + 1, L'\0');
  const int count =
      GetWindowTextW(window, caption.data(), static_cast<int>(caption.size()));
  UINT format = DT_CENTER | DT_VCENTER | DT_SINGLELINE;
  if (SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEACCEL) {
    format |= DT_HIDEPREFIX;
  }
  DrawTextW(memory, caption.data(), count, &bounds, format);
  if (GetFocus() == window &&
      !(SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEFOCUS)) {
    RECT focus = bounds;
    InflateRect(&focus, -6, -5);
    DrawFocusRect(memory, &focus);
  }
  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, old_font);
  SelectObject(memory, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

void PaintCheckCard(HWND window, HDC destination, const CheckCardStyle& style) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  if (bounds.right <= 0 || bounds.bottom <= 0) return;
  HDC memory = CreateCompatibleDC(destination);
  HBITMAP bitmap =
      CreateCompatibleBitmap(destination, bounds.right, bounds.bottom);
  if (!memory || !bitmap) {
    if (bitmap) DeleteObject(bitmap);
    if (memory) DeleteDC(memory);
    return;
  }
  const auto old_bitmap = SelectObject(memory, bitmap);
  const bool enabled = IsWindowEnabled(window) != FALSE;
  const bool checked =
      (SendMessageW(window, BM_GETCHECK, 0, 0) & BST_CHECKED) != 0;
  const float dpi_scale =
      static_cast<float>(GetDpiForWindow(window)) / 96.0f;

  dan::installer::PaintParentSurface(window, memory, bounds, style.surface);
  const COLORREF actual_surface = GetPixel(memory, 0, 0);
  const bool dark = IsDarkSurface(actual_surface);

  const COLORREF card_fill = checked
      ? MixColorRef(actual_surface, style.accent,
                    style.hovered ? (dark ? 0.24 : 0.14) : (dark ? 0.18 : 0.10))
      : MixColorRef(actual_surface, dark ? RGB(255, 255, 255) : RGB(0, 0, 0),
                    style.hovered ? (dark ? 0.08 : 0.045)
                                  : (dark ? 0.045 : 0.022));
  const COLORREF card_border = checked
      ? MixColorRef(actual_surface, style.accent, dark ? 0.50 : 0.36)
      : MixColorRef(actual_surface, dark ? RGB(255, 255, 255) : RGB(0, 0, 0),
                    dark ? 0.16 : 0.12);

  const float box_size = 18.0f * dpi_scale;
  const float pad_left = 12.0f * dpi_scale;
  const float box_y =
      (static_cast<float>(bounds.bottom) - box_size) / 2.0f;

  {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath card_path;
    Rounded(card_path,
            Gdiplus::RectF(0.5f, 0.5f, static_cast<float>(bounds.right) - 1.0f,
                           static_cast<float>(bounds.bottom) - 1.0f),
            static_cast<float>(style.radius));
    Gdiplus::SolidBrush fill_brush(Color(card_fill, enabled ? 255 : 120));
    graphics.FillPath(&fill_brush, &card_path);
    Gdiplus::Pen border_pen(Color(card_border, enabled ? 235 : 100), 1.1f);
    graphics.DrawPath(&border_pen, &card_path);

    Gdiplus::RectF indicator_rect(pad_left, box_y, box_size, box_size);
    Gdiplus::GraphicsPath indicator_path;
    Rounded(indicator_path, indicator_rect, 6.0f * dpi_scale);
    if (checked) {
      Gdiplus::SolidBrush check_fill(Color(style.accent, enabled ? 255 : 120));
      graphics.FillPath(&check_fill, &indicator_path);
      const COLORREF mark_col = ReadableText(style.accent);
      Gdiplus::Pen check_pen(Color(mark_col), 2.0f * dpi_scale);
      check_pen.SetStartCap(Gdiplus::LineCapRound);
      check_pen.SetEndCap(Gdiplus::LineCapRound);
      check_pen.SetLineJoin(Gdiplus::LineJoinRound);
      const Gdiplus::PointF pts[3] = {
          Gdiplus::PointF(pad_left + box_size * 0.24f,
                          box_y + box_size * 0.52f),
          Gdiplus::PointF(pad_left + box_size * 0.44f,
                          box_y + box_size * 0.72f),
          Gdiplus::PointF(pad_left + box_size * 0.77f,
                          box_y + box_size * 0.30f),
      };
      graphics.DrawLines(&check_pen, pts, 3);
    } else {
      const COLORREF unchecked_outline = MixColorRef(
          actual_surface, dark ? RGB(255, 255, 255) : RGB(0, 0, 0), 0.42);
      Gdiplus::Pen box_pen(Color(unchecked_outline), 1.5f * dpi_scale);
      graphics.DrawPath(&box_pen, &indicator_path);
    }
  }

  const HFONT font =
      reinterpret_cast<HFONT>(SendMessageW(window, WM_GETFONT, 0, 0));
  const auto old_font =
      SelectObject(memory, font ? font : GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(memory, TRANSPARENT);
  const COLORREF text_col =
      dark ? RGB(238, 240, 248) : RGB(26, 29, 38);
  SetTextColor(memory, enabled ? text_col : GetSysColor(COLOR_GRAYTEXT));
  std::wstring caption(
      static_cast<size_t>(GetWindowTextLengthW(window)) + 1, L'\0');
  const int count =
      GetWindowTextW(window, caption.data(), static_cast<int>(caption.size()));
  RECT text_rect = bounds;
  text_rect.left = static_cast<LONG>(pad_left + box_size + 10.0f * dpi_scale);
  text_rect.right = bounds.right - static_cast<LONG>(10.0f * dpi_scale);
  UINT format = DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS;
  if (SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEACCEL) {
    format |= DT_HIDEPREFIX;
  }
  DrawTextW(memory, caption.data(), count, &text_rect, format);
  if (GetFocus() == window &&
      !(SendMessageW(window, WM_QUERYUISTATE, 0, 0) & UISF_HIDEFOCUS)) {
    RECT focus = bounds;
    InflateRect(&focus, -4, -4);
    DrawFocusRect(memory, &focus);
  }
  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, old_font);
  SelectObject(memory, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

void PaintSurfaceCard(HWND window, HDC destination,
                      const SurfaceCardSpec& spec) {
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
  const auto old_bitmap = SelectObject(memory, bitmap);
  dan::installer::PaintParentSurface(window, memory, bounds, spec.surface);
  const COLORREF actual_surface = GetPixel(memory, 0, 0);
  const bool dark = IsDarkSurface(actual_surface);

  const COLORREF card_fill = spec.tonal_tint
      ? MixColorRef(actual_surface, spec.accent, dark ? 0.14 : 0.075)
      : MixColorRef(actual_surface,
                    dark ? RGB(255, 255, 255) : RGB(255, 255, 255),
                    dark ? 0.055 : 0.72);
  const COLORREF border_col = spec.tonal_tint
      ? MixColorRef(actual_surface, spec.accent, dark ? 0.34 : 0.22)
      : MixColorRef(actual_surface,
                    dark ? RGB(255, 255, 255) : RGB(0, 0, 0),
                    dark ? 0.14 : 0.09);

  if (!HighContrast()) {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath path;
    Rounded(path,
            Gdiplus::RectF(0.5f, 0.5f, static_cast<float>(bounds.right) - 1.0f,
                           static_cast<float>(bounds.bottom) - 1.0f),
            static_cast<float>(spec.radius));
    Gdiplus::SolidBrush fill(Color(card_fill));
    graphics.FillPath(&fill, &path);
    Gdiplus::Pen border(Color(border_col), 1.1f);
    graphics.DrawPath(&border, &path);
  }
  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

void PaintInfoCard(HWND window, HDC destination, const InfoCardStyle& style) {
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
  const auto old_bitmap = SelectObject(memory, bitmap);
  dan::installer::PaintParentSurface(window, memory, bounds, style.surface);
  const COLORREF actual_surface = GetPixel(memory, 0, 0);
  const bool dark = IsDarkSurface(actual_surface);

  const COLORREF card_fill =
      MixColorRef(actual_surface, style.accent, dark ? 0.13 : 0.068);
  const COLORREF border_col =
      MixColorRef(actual_surface, style.accent, dark ? 0.32 : 0.20);
  {
    Gdiplus::Graphics graphics(memory);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::GraphicsPath path;
    Rounded(path,
            Gdiplus::RectF(0.5f, 0.5f, static_cast<float>(bounds.right) - 1.0f,
                           static_cast<float>(bounds.bottom) - 1.0f),
            static_cast<float>(style.radius));
    Gdiplus::SolidBrush fill(Color(card_fill));
    graphics.FillPath(&fill, &path);
    Gdiplus::Pen border(Color(border_col), 1.05f);
    graphics.DrawPath(&border, &path);
  }

  const HFONT font =
      reinterpret_cast<HFONT>(SendMessageW(window, WM_GETFONT, 0, 0));
  const auto old_font =
      SelectObject(memory, font ? font : GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(memory, TRANSPARENT);
  const COLORREF text_col =
      dark ? RGB(218, 224, 238) : RGB(54, 60, 76);
  SetTextColor(memory, text_col);
  std::wstring caption(
      static_cast<size_t>(GetWindowTextLengthW(window)) + 1, L'\0');
  const int count =
      GetWindowTextW(window, caption.data(), static_cast<int>(caption.size()));
  RECT inner = bounds;
  inner.left += style.pad_x;
  inner.right -= style.pad_x;
  inner.top += style.pad_y;
  inner.bottom -= style.pad_y;
  if (inner.right > inner.left && inner.bottom > inner.top) {
    RECT calc = inner;
    const UINT align = style.centered ? DT_CENTER : DT_LEFT;
    DrawTextW(memory, caption.data(), count, &calc,
              align | DT_WORDBREAK | DT_NOPREFIX | DT_CALCRECT);
    const int text_h = calc.bottom - calc.top;
    const int avail_h = inner.bottom - inner.top;
    if (text_h < avail_h) {
      inner.top += (avail_h - text_h) / 2;
    }
    DrawTextW(memory, caption.data(), count, &inner,
              align | DT_WORDBREAK | DT_NOPREFIX);
  }

  BitBlt(destination, 0, 0, bounds.right, bounds.bottom, memory, 0, 0, SRCCOPY);
  SelectObject(memory, old_font);
  SelectObject(memory, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory);
}

LRESULT CALLBACK ButtonProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam, UINT_PTR id,
                                 DWORD_PTR reference) {
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
      PAINTSTRUCT paint{};
      const HDC dc = BeginPaint(window, &paint);
      PaintButton(window, dc, *style);
      EndPaint(window, &paint);
      return 0;
    }
    if (message == WM_PRINTCLIENT) {
      PaintButton(window, reinterpret_cast<HDC>(wparam), *style);
      return 0;
    }
  }
  if (message == WM_MOUSEMOVE && !style->hovered) {
    style->hovered = true;
    TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
    TrackMouseEvent(&track);
    InvalidateRect(window, nullptr, FALSE);
  } else if (message == WM_MOUSELEAVE) {
    style->hovered = false;
    InvalidateRect(window, nullptr, FALSE);
  }
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  if (message == BM_SETSTATE || message == WM_ENABLE ||
      message == WM_SETFOCUS || message == WM_KILLFOCUS ||
      message == WM_SETTEXT || message == WM_THEMECHANGED ||
      message == WM_UPDATEUISTATE) {
    InvalidateRect(window, nullptr, FALSE);
  }
  return result;
}

LRESULT CALLBACK CheckCardProcedure(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam, UINT_PTR id,
                                    DWORD_PTR reference) {
  auto* style = reinterpret_cast<CheckCardStyle*>(reference);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, CheckCardProcedure, id);
    const auto result = DefSubclassProc(window, message, wparam, lparam);
    check_cards.erase(window);
    return result;
  }
  if (!HighContrast()) {
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{};
      const HDC dc = BeginPaint(window, &paint);
      PaintCheckCard(window, dc, *style);
      EndPaint(window, &paint);
      return 0;
    }
    if (message == WM_PRINTCLIENT) {
      PaintCheckCard(window, reinterpret_cast<HDC>(wparam), *style);
      return 0;
    }
  }
  if (message == WM_MOUSEMOVE && !style->hovered) {
    style->hovered = true;
    TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
    TrackMouseEvent(&track);
    InvalidateRect(window, nullptr, FALSE);
  } else if (message == WM_MOUSELEAVE) {
    style->hovered = false;
    InvalidateRect(window, nullptr, FALSE);
  }
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  if (message == BM_SETCHECK || message == BM_SETSTATE ||
      message == WM_LBUTTONUP || message == WM_KEYUP ||
      message == WM_ENABLE || message == WM_SETFOCUS ||
      message == WM_KILLFOCUS || message == WM_SETTEXT ||
      message == WM_UPDATEUISTATE) {
    InvalidateRect(window, nullptr, FALSE);
  }
  return result;
}

LRESULT CALLBACK SurfaceCardProcedure(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_ERASEBKGND) return 1;
  const auto found = surface_cards.find(window);
  if (found != surface_cards.end()) {
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{};
      HDC dc = BeginPaint(window, &paint);
      PaintSurfaceCard(window, dc, *found->second);
      EndPaint(window, &paint);
      return 0;
    }
    if (message == WM_PRINT || message == WM_PRINTCLIENT) {
      PaintSurfaceCard(window, reinterpret_cast<HDC>(wparam), *found->second);
      return 0;
    }
  }
  if (message == WM_NCDESTROY) {
    surface_cards.erase(window);
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT CALLBACK InfoCardProcedure(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam, UINT_PTR id,
                                   DWORD_PTR reference) {
  auto* style = reinterpret_cast<InfoCardStyle*>(reference);
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, InfoCardProcedure, id);
    const auto result = DefSubclassProc(window, message, wparam, lparam);
    info_cards.erase(window);
    return result;
  }
  if (!HighContrast()) {
    if (message == WM_ERASEBKGND) return 1;
    if (message == WM_PAINT) {
      PAINTSTRUCT paint{};
      const HDC dc = BeginPaint(window, &paint);
      PaintInfoCard(window, dc, *style);
      EndPaint(window, &paint);
      return 0;
    }
    if (message == WM_PRINT || message == WM_PRINTCLIENT) {
      PaintInfoCard(window, reinterpret_cast<HDC>(wparam), *style);
      return 0;
    }
  }
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  if (message == WM_SETTEXT || message == WM_ENABLE ||
      message == WM_THEMECHANGED) {
    InvalidateRect(window, nullptr, FALSE);
  }
  return result;
}
}  // namespace

extern "C" __declspec(dllexport) COLORREF __stdcall DP_AccentColor() {
  DWORD argb = 0;
  BOOL opaque = FALSE;
  if (SUCCEEDED(DwmGetColorizationColor(&argb, &opaque))) {
    return RGB((argb >> 16) & 255, (argb >> 8) & 255, argb & 255);
  }
  return RGB(83, 88, 172);
}

extern "C" __declspec(dllexport) void __stdcall DP_ApplyWindowChrome(
    HWND window, COLORREF surface, COLORREF accent, BOOL dark) {
  if (!IsWindow(window) || HighContrast()) return;
  const BOOL dark_mode = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, kDwmUseImmersiveDarkMode, &dark_mode,
                        sizeof(dark_mode));
  const DWORD corner = kDwmCornerRound;
  DwmSetWindowAttribute(window, kDwmWindowCornerPreference, &corner,
                        sizeof(corner));
  DwmSetWindowAttribute(window, kDwmCaptionColor, &surface, sizeof(surface));
  const COLORREF border =
      MixColorRef(surface, accent, dark ? 0.34 : 0.22);
  DwmSetWindowAttribute(window, kDwmBorderColor, &border, sizeof(border));
}

extern "C" __declspec(dllexport) int __stdcall DP_StyleButton(
    HWND window, COLORREF surface, COLORREF accent, BOOL primary, int radius) {
  if (!IsWindow(window) || radius < 1 || radius > 128) return 0;
  if (!EnsureGdiPlus()) return 0;
  const COLORREF text = ReadableText(accent);
  auto style = std::make_unique<ButtonStyle>(
      ButtonStyle{surface, accent, text, primary != FALSE, false, radius});
  if (!SetWindowSubclass(window, ButtonProcedure, 1,
                         reinterpret_cast<DWORD_PTR>(style.get()))) {
    return 0;
  }
  buttons[window] = std::move(style);
  InvalidateRect(window, nullptr, FALSE);
  return 1;
}

extern "C" __declspec(dllexport) int __stdcall DP_StyleCheckCard(
    HWND window, COLORREF surface, COLORREF accent, int radius) {
  if (!IsWindow(window) || radius < 1 || radius > 64) return 0;
  if (!EnsureGdiPlus()) return 0;
  auto style = std::make_unique<CheckCardStyle>(
      CheckCardStyle{surface, accent, false, radius});
  if (!SetWindowSubclass(window, CheckCardProcedure, 2,
                         reinterpret_cast<DWORD_PTR>(style.get()))) {
    return 0;
  }
  check_cards[window] = std::move(style);
  InvalidateRect(window, nullptr, FALSE);
  return 1;
}

extern "C" __declspec(dllexport) HWND __stdcall DP_CreateSurfaceCard(
    HWND parent, int left, int top, int width, int height, COLORREF surface,
    COLORREF accent, int radius, BOOL tonal_tint) {
  if (!IsWindow(parent) || width <= 0 || height <= 0 || radius < 1 ||
      radius > 64) {
    return nullptr;
  }
  if (!EnsureGdiPlus()) return nullptr;
  WNDCLASSW cls{};
  cls.lpfnWndProc = SurfaceCardProcedure;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"DanPlayerM3SurfaceCard";
  RegisterClassW(&cls);
  HWND card = CreateWindowExW(
      WS_EX_TRANSPARENT, cls.lpszClassName, L"",
      WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, left, top, width, height, parent,
      nullptr, cls.hInstance, nullptr);
  if (!card) return nullptr;
  surface_cards[card] = std::make_unique<SurfaceCardSpec>(
      SurfaceCardSpec{surface, accent, radius, tonal_tint != FALSE});
  SetWindowPos(card, HWND_BOTTOM, left, top, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(card, nullptr, FALSE);
  return card;
}

extern "C" __declspec(dllexport) int __stdcall DP_StyleInfoCard(
    HWND window, COLORREF surface, COLORREF accent, int radius, int pad_x,
    int pad_y, BOOL centered) {
  if (!IsWindow(window) || radius < 1 || radius > 64) return 0;
  if (!EnsureGdiPlus()) return 0;
  auto style = std::make_unique<InfoCardStyle>(InfoCardStyle{
      surface, accent, radius, pad_x, pad_y, centered != FALSE});
  if (!SetWindowSubclass(window, InfoCardProcedure, 3,
                         reinterpret_cast<DWORD_PTR>(style.get()))) {
    return 0;
  }
  info_cards[window] = std::move(style);
  InvalidateRect(window, nullptr, FALSE);
  return 1;
}

extern "C" __declspec(dllexport) void __stdcall DP_CloseControls() {
  for (const auto& entry : buttons) {
    if (IsWindow(entry.first)) {
      RemoveWindowSubclass(entry.first, ButtonProcedure, 1);
    }
  }
  buttons.clear();
  for (const auto& entry : check_cards) {
    if (IsWindow(entry.first)) {
      RemoveWindowSubclass(entry.first, CheckCardProcedure, 2);
    }
  }
  check_cards.clear();
  for (const auto& entry : info_cards) {
    if (IsWindow(entry.first)) {
      RemoveWindowSubclass(entry.first, InfoCardProcedure, 3);
    }
  }
  info_cards.clear();
  std::vector<HWND> cards;
  cards.reserve(surface_cards.size());
  for (const auto& entry : surface_cards) cards.push_back(entry.first);
  surface_cards.clear();
  for (HWND card : cards) {
    if (IsWindow(card)) DestroyWindow(card);
  }
  if (graphics_token) Gdiplus::GdiplusShutdown(graphics_token);
  graphics_token = 0;
}
