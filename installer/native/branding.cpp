#include "installer_core.h"
#include "installer_paint.h"

#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

using namespace dan::installer;
namespace {
ULONG_PTR gdiplus_token = 0;
HWND logo_window = nullptr;
std::unique_ptr<Gdiplus::Bitmap> player_icon;
uint64_t started = 0;
COLORREF background_color = RGB(246, 247, 252);
COLORREF brand_accent_color = RGB(83, 88, 172);
std::wstring loaded_font_family = L"Segoe UI";
std::wstring brand_subtitle;
using Completed = void(__stdcall*)();
Completed completed = nullptr;
bool reduce_motion = false;
HANDLE private_font = nullptr;
std::vector<BYTE> private_font_bytes;

void EnsureGraphics() {
  if (!gdiplus_token) {
    Gdiplus::GdiplusStartupInput options;
    if (Gdiplus::GdiplusStartup(&gdiplus_token, &options, nullptr) != Gdiplus::Ok) {
      gdiplus_token = 0;
    }
  }
}

BYTE BlendChannel(BYTE base, BYTE tint, double ratio) {
  const double clamped = (std::max)(0.0, (std::min)(1.0, ratio));
  return static_cast<BYTE>(
      std::lround(base * (1.0 - clamped) + tint * clamped));
}

Gdiplus::Color BlendGdiColor(COLORREF base, COLORREF tint, double ratio,
                             BYTE alpha = 255) {
  return Gdiplus::Color(
      alpha,
      BlendChannel(GetRValue(base), GetRValue(tint), ratio),
      BlendChannel(GetGValue(base), GetGValue(tint), ratio),
      BlendChannel(GetBValue(base), GetBValue(tint), ratio));
}

void AddRoundedRect(Gdiplus::GraphicsPath& path, const Gdiplus::RectF& rect,
                    float radius) {
  const float diameter =
      (std::min)(radius * 2.0f, (std::min)(rect.Width, rect.Height));
  if (diameter <= 0.5f) {
    path.AddRectangle(rect);
    return;
  }
  path.AddArc(rect.X, rect.Y, diameter, diameter, 180.0f, 90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.Y, diameter, diameter, 270.0f,
              90.0f);
  path.AddArc(rect.GetRight() - diameter, rect.GetBottom() - diameter, diameter,
              diameter, 0.0f, 90.0f);
  path.AddArc(rect.X, rect.GetBottom() - diameter, diameter, diameter, 90.0f,
              90.0f);
  path.CloseFigure();
}

void DrawPlayer(Gdiplus::Graphics& graphics, Gdiplus::Image* image,
                const RECT& bounds, const LogoFrame& frame) {
  if (!image || image->GetLastStatus() != Gdiplus::Ok || frame.player <= 0) {
    return;
  }
  const float width = static_cast<float>(bounds.right - bounds.left);
  const float height = static_cast<float>(bounds.bottom - bounds.top);
  const float dpi_scale =
      static_cast<float>(GetDpiForWindow(logo_window)) / 96.0f;
  const float dw =
      (std::min)(96.0f * dpi_scale, (std::min)(width * 0.28f, height * 0.36f));
  const float dh = dw;
  const float title_size = (std::min)(22.0f * dpi_scale, width * 0.078f);
  const float pill_font_size = (std::min)(12.5f * dpi_scale, title_size * 0.58f);
  const float gap = 16.0f * dpi_scale;
  const float pill_height =
      brand_subtitle.empty() ? 0.0f : (26.0f * dpi_scale);
  const float pill_gap = brand_subtitle.empty() ? 0.0f : (8.0f * dpi_scale);
  const float total_height =
      dh + gap + title_size * 1.45f + pill_gap + pill_height;
  const float top = (height - total_height) / 2.0f;

  const bool dark =
      (GetRValue(background_color) * 299 + GetGValue(background_color) * 587 +
       GetBValue(background_color) * 114) < 128000;
  const auto alpha =
      static_cast<BYTE>((std::max)(0.0, (std::min)(1.0, frame.player)) * 255.0);

  // Material 3 Expressive soft concentric tonal halo & squircle pedestal
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  const float center_x = width / 2.0f;
  const float center_y =
      top + dh / 2.0f + static_cast<float>(frame.lift) * dpi_scale * 0.5f;
  const float halo_outer = dw * (1.46f + 0.06f * static_cast<float>(frame.scale));
  Gdiplus::SolidBrush outer_halo(BlendGdiColor(
      background_color, brand_accent_color, dark ? 0.16 : 0.09,
      static_cast<BYTE>(alpha * 0.65)));
  graphics.FillEllipse(&outer_halo, center_x - halo_outer / 2.0f,
                       center_y - halo_outer / 2.0f, halo_outer, halo_outer);

  const float pedestal = dw * 1.18f;
  Gdiplus::GraphicsPath squircle;
  AddRoundedRect(
      squircle,
      Gdiplus::RectF(center_x - pedestal / 2.0f, center_y - pedestal / 2.0f,
                     pedestal, pedestal),
      pedestal * 0.30f);
  Gdiplus::SolidBrush inner_fill(BlendGdiColor(
      background_color, brand_accent_color, dark ? 0.24 : 0.14,
      static_cast<BYTE>(alpha * 0.88)));
  graphics.FillPath(&inner_fill, &squircle);
  Gdiplus::Pen inner_border(
      BlendGdiColor(background_color, brand_accent_color, dark ? 0.42 : 0.28,
                    static_cast<BYTE>(alpha * 0.72)),
      1.2f * dpi_scale);
  graphics.DrawPath(&inner_border, &squircle);

  Gdiplus::ColorMatrix matrix = {{{1, 0, 0, 0, 0},
                                  {0, 1, 0, 0, 0},
                                  {0, 0, 1, 0, 0},
                                  {0, 0, 0, static_cast<float>(frame.player), 0},
                                  {0, 0, 0, 0, 1}}};
  Gdiplus::ImageAttributes attributes;
  attributes.SetColorMatrix(&matrix);
  const Gdiplus::GraphicsState stable = graphics.Save();
  graphics.TranslateTransform(
      center_x, top + dh / 2.0f + static_cast<float>(frame.lift) * dpi_scale);
  graphics.RotateTransform(static_cast<float>(frame.tilt));
  graphics.ScaleTransform(static_cast<float>(frame.scale),
                          static_cast<float>(frame.scale));
  graphics.DrawImage(image, Gdiplus::RectF(-dw / 2.0f, -dh / 2.0f, dw, dh), 0,
                     0, static_cast<float>(image->GetWidth()),
                     static_cast<float>(image->GetHeight()), Gdiplus::UnitPixel,
                     &attributes);
  graphics.Restore(stable);

  Gdiplus::SolidBrush text_brush(Gdiplus::Color(
      alpha, dark ? 242 : 24, dark ? 244 : 27, dark ? 250 : 34));
  Gdiplus::Font title_font(loaded_font_family.c_str(), title_size,
                           Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
  Gdiplus::Font fallback_title(L"Segoe UI", title_size, Gdiplus::FontStyleBold,
                               Gdiplus::UnitPixel);
  const Gdiplus::Font* active_title =
      title_font.IsAvailable() ? &title_font : &fallback_title;

  Gdiplus::StringFormat format;
  format.SetAlignment(Gdiplus::StringAlignmentCenter);
  format.SetLineAlignment(Gdiplus::StringAlignmentCenter);
  graphics.SetTextRenderingHint(Gdiplus::TextRenderingHintAntiAliasGridFit);
  const float title_top = top + dh + gap;
  const float title_box_h = title_size * 1.45f;
  graphics.DrawString(L"Dan Player", -1, active_title,
                      Gdiplus::RectF(0, title_top, width, title_box_h), &format,
                      &text_brush);

  if (!brand_subtitle.empty()) {
    Gdiplus::Font sub_font(loaded_font_family.c_str(), pill_font_size,
                           Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    Gdiplus::Font fallback_sub(L"Segoe UI", pill_font_size,
                               Gdiplus::FontStyleBold, Gdiplus::UnitPixel);
    const Gdiplus::Font* active_sub =
        sub_font.IsAvailable() ? &sub_font : &fallback_sub;
    Gdiplus::RectF measured;
    graphics.MeasureString(brand_subtitle.c_str(), -1, active_sub,
                           Gdiplus::PointF(0, 0), &measured);
    const float pill_w =
        (std::min)(width - 32.0f * dpi_scale,
                   (std::max)(88.0f * dpi_scale, measured.Width + 28.0f * dpi_scale));
    const float pill_top = title_top + title_box_h + pill_gap;
    Gdiplus::RectF pill_rect((width - pill_w) / 2.0f, pill_top, pill_w,
                             pill_height);
    Gdiplus::GraphicsPath pill_path;
    AddRoundedRect(pill_path, pill_rect, pill_height / 2.0f);
    Gdiplus::SolidBrush pill_fill(BlendGdiColor(
        background_color, brand_accent_color, dark ? 0.24 : 0.14, alpha));
    graphics.FillPath(&pill_fill, &pill_path);
    Gdiplus::Pen pill_outline(
        BlendGdiColor(background_color, brand_accent_color, dark ? 0.46 : 0.30,
                      alpha),
        1.0f);
    graphics.DrawPath(&pill_outline, &pill_path);
    Gdiplus::SolidBrush pill_text(BlendGdiColor(
        dark ? RGB(236, 240, 252) : RGB(30, 34, 46), brand_accent_color,
        dark ? 0.28 : 0.55, alpha));
    graphics.DrawString(brand_subtitle.c_str(), -1, active_sub, pill_rect,
                        &format, &pill_text);
  }
}

void PaintLogo(HWND window, HDC dc) {
  RECT bounds{};
  GetClientRect(window, &bounds);
  if (!dc || bounds.right <= 0 || bounds.bottom <= 0) return;
  Gdiplus::Bitmap buffer(bounds.right, bounds.bottom, PixelFormat32bppPARGB);
  {
    Gdiplus::Graphics graphics(&buffer);
    graphics.Clear(Gdiplus::Color(255, GetRValue(background_color),
                                  GetGValue(background_color),
                                  GetBValue(background_color)));
    HDC background = graphics.GetHDC();
    PaintParentSurface(window, background, bounds, background_color);
    graphics.ReleaseHDC(background);
    graphics.SetInterpolationMode(
        Gdiplus::InterpolationModeHighQualityBicubic);
    const auto frame =
        EvaluateLogoFrame(GetTickCount64() - started, reduce_motion);
    DrawPlayer(graphics, player_icon.get(), bounds, frame);
  }
  Gdiplus::Graphics destination(dc);
  destination.DrawImage(&buffer, 0, 0);
}

LRESULT CALLBACK LogoProcedure(HWND window, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_TIMER) {
    if (EvaluateLogoFrame(GetTickCount64() - started, reduce_motion).finished) {
      KillTimer(window, 1);
      auto callback = completed;
      completed = nullptr;
      if (callback) callback();
    } else {
      InvalidateRect(window, nullptr, FALSE);
    }
    return 0;
  }
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(window, &paint);
    PaintLogo(window, dc);
    EndPaint(window, &paint);
    return 0;
  }
  if (message == WM_PRINTCLIENT) {
    PaintLogo(window, reinterpret_cast<HDC>(wparam));
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
}  // namespace

extern "C" __declspec(dllexport) int __stdcall DP_LoadPrivateFont(
    const wchar_t* path, wchar_t* output, int capacity) {
  EnsureGraphics();
  if (!gdiplus_token || !path || !output || capacity < LF_FACESIZE) return 0;
  if (private_font) RemoveFontMemResourceEx(private_font);
  private_font = nullptr;
  private_font_bytes.clear();
  try {
    CheckNoReparsePoints(fs::path(path));
    std::ifstream file(fs::path(path), std::ios::binary | std::ios::ate);
    const auto length = file.tellg();
    if (!file || length <= 0 || length > 64 * 1024 * 1024) return 0;
    private_font_bytes.resize(static_cast<size_t>(length));
    file.seekg(0);
    file.read(reinterpret_cast<char*>(private_font_bytes.data()),
              static_cast<std::streamsize>(length));
    if (!file) {
      private_font_bytes.clear();
      return 0;
    }
    file.close();
    Gdiplus::PrivateFontCollection collection;
    if (collection.AddMemoryFont(private_font_bytes.data(),
                                 static_cast<INT>(length)) != Gdiplus::Ok) {
      return 0;
    }
    Gdiplus::FontFamily family;
    INT count = 0;
    if (collection.GetFamilies(1, &family, &count) != Gdiplus::Ok ||
        count != 1 || family.GetFamilyName(output) != Gdiplus::Ok) {
      return 0;
    }
    DWORD fonts = 0;
    private_font = AddFontMemResourceEx(
        private_font_bytes.data(), static_cast<DWORD>(length), nullptr, &fonts);
    if (!private_font || !fonts) return 0;
    loaded_font_family = output;
    return static_cast<int>(wcslen(output));
  } catch (...) {
    return 0;
  }
}

extern "C" __declspec(dllexport) void __stdcall DP_ConfigureBrandTheme(
    COLORREF accent, const wchar_t* subtitle) {
  brand_accent_color = accent;
  brand_subtitle = subtitle ? subtitle : L"";
}

extern "C" __declspec(dllexport) int __stdcall DP_ShowBrand(
    HWND parent, int width, int height, COLORREF background,
    const wchar_t* icon_path, Completed callback) {
  EnsureGraphics();
  if (!gdiplus_token || !IsWindow(parent) || width <= 0 || height <= 0) {
    return 0;
  }
  if (logo_window) DestroyWindow(logo_window);
  logo_window = nullptr;
  const auto icon = static_cast<HICON>(
      LoadImageW(nullptr, icon_path, IMAGE_ICON, 256, 256, LR_LOADFROMFILE));
  if (!icon) return 0;
  player_icon.reset(Gdiplus::Bitmap::FromHICON(icon));
  DestroyIcon(icon);
  if (!player_icon || player_icon->GetLastStatus() != Gdiplus::Ok) return 0;
  WNDCLASSW cls{};
  cls.lpfnWndProc = LogoProcedure;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"DanPlayerInstallerBrand";
  RegisterClassW(&cls);
  background_color = background;
  completed = callback;
  BOOL animations = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
  reduce_motion = !animations || (contrast.dwFlags & HCF_HIGHCONTRASTON);
  started = GetTickCount64();
  logo_window =
      CreateWindowExW(0, cls.lpszClassName, L"", WS_CHILD | WS_VISIBLE, 0, 0,
                      width, height, parent, nullptr, cls.hInstance, nullptr);
  if (!logo_window) {
    completed = nullptr;
    return 0;
  }
  SetTimer(logo_window, 1, 16, nullptr);
  return 1;
}

extern "C" __declspec(dllexport) void __stdcall DP_CloseBrand() {
  completed = nullptr;
  if (logo_window) DestroyWindow(logo_window);
  logo_window = nullptr;
  player_icon.reset();
  loaded_font_family = L"Segoe UI";
  brand_subtitle.clear();
  if (private_font) RemoveFontMemResourceEx(private_font);
  private_font = nullptr;
  private_font_bytes.clear();
  if (gdiplus_token) Gdiplus::GdiplusShutdown(gdiplus_token);
  gdiplus_token = 0;
}
