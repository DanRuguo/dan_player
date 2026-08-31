#include "installer_core.h"
#include "installer_paint.h"

#include <objidl.h>
#include <gdiplus.h>

#include <algorithm>
#include <fstream>
#include <memory>
#include <vector>

using namespace dan::installer;
namespace {
ULONG_PTR gdiplus_token = 0;
HWND logo_window = nullptr;
std::unique_ptr<Gdiplus::Image> rce, danruguo;
uint64_t started = 0;
COLORREF background_color = RGB(255, 255, 255);
using Completed = void(__stdcall*)();
Completed completed = nullptr;
bool reduce_motion = false;
HANDLE private_font = nullptr;
std::vector<BYTE> private_font_bytes;

void EnsureGraphics() {
  if (!gdiplus_token) {
    Gdiplus::GdiplusStartupInput options;
    if (Gdiplus::GdiplusStartup(&gdiplus_token, &options, nullptr) != Gdiplus::Ok) gdiplus_token = 0;
  }
}
void DrawImage(Gdiplus::Graphics& graphics, Gdiplus::Image* image,
               const RECT& bounds, double opacity) {
  if (!image || image->GetLastStatus() != Gdiplus::Ok || opacity <= 0) return;
  const float width = static_cast<float>(bounds.right - bounds.left);
  const float height = static_cast<float>(bounds.bottom - bounds.top);
  const float scale = (std::min)(width * .76f / image->GetWidth(), height * .55f / image->GetHeight());
  const float dw = image->GetWidth() * scale, dh = image->GetHeight() * scale;
  Gdiplus::ColorMatrix matrix = {{{1,0,0,0,0},{0,1,0,0,0},{0,0,1,0,0},
                                 {0,0,0,static_cast<float>(opacity),0},{0,0,0,0,1}}};
  Gdiplus::ImageAttributes attributes;
  attributes.SetColorMatrix(&matrix);
  graphics.DrawImage(image, Gdiplus::RectF((width-dw)/2, (height-dh)/2, dw, dh),
                      0, 0, static_cast<float>(image->GetWidth()),
                      static_cast<float>(image->GetHeight()), Gdiplus::UnitPixel,
                      &attributes);
}
void PaintLogo(HWND window, HDC dc) {
  RECT bounds{}; GetClientRect(window, &bounds);
  if (!dc || bounds.right <= 0 || bounds.bottom <= 0) return;
  Gdiplus::Bitmap buffer(bounds.right, bounds.bottom, PixelFormat32bppPARGB);
  {
    Gdiplus::Graphics graphics(&buffer);
    graphics.Clear(Gdiplus::Color(255, GetRValue(background_color),
        GetGValue(background_color), GetBValue(background_color)));
    HDC background = graphics.GetHDC();
    PaintParentSurface(window, background, bounds, background_color);
    graphics.ReleaseHDC(background);
    graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
    const auto frame = EvaluateLogoFrame(GetTickCount64() - started, reduce_motion);
    DrawImage(graphics, rce.get(), bounds, frame.rce);
    DrawImage(graphics, danruguo.get(), bounds, frame.danruguo);
  }
  // Finish writing the buffer before another GDI+ Graphics reads it.
  Gdiplus::Graphics destination(dc);
  destination.DrawImage(&buffer, 0, 0);
}
LRESULT CALLBACK LogoProcedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_TIMER) {
    if (EvaluateLogoFrame(GetTickCount64() - started, reduce_motion).finished) {
      KillTimer(window, 1);
      auto callback = completed;
      completed = nullptr;
      if (callback) callback();
    } else InvalidateRect(window, nullptr, FALSE);
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
  file.read(reinterpret_cast<char*>(private_font_bytes.data()), static_cast<std::streamsize>(length));
  if (!file) { private_font_bytes.clear(); return 0; }
  file.close(); // Never keep a mapping/handle to Inno's temporary TTF.
  Gdiplus::PrivateFontCollection collection;
  if (collection.AddMemoryFont(private_font_bytes.data(), static_cast<INT>(length)) != Gdiplus::Ok) return 0;
  Gdiplus::FontFamily family;
  INT count = 0;
  if (collection.GetFamilies(1, &family, &count) != Gdiplus::Ok || count != 1 ||
      family.GetFamilyName(output) != Gdiplus::Ok) return 0;
  DWORD fonts = 0;
  // GDI makes its own copy, so surviving HFONT handles do not refer to our
  // input vector or a temporary file. Keep input alive until explicit teardown
  // anyway; the GDI+ collection/family above are destroyed before return.
  private_font = AddFontMemResourceEx(private_font_bytes.data(), static_cast<DWORD>(length), nullptr, &fonts);
  if (!private_font || !fonts) return 0;
  return static_cast<int>(wcslen(output));
  } catch (...) { return 0; }
}
extern "C" __declspec(dllexport) int __stdcall DP_ShowBrand(
    HWND parent, int width, int height, COLORREF background,
    const wchar_t* rce_path, const wchar_t* dan_path, Completed callback) {
  EnsureGraphics();
  if (!gdiplus_token || !IsWindow(parent) || width <= 0 || height <= 0) return 0;
  if (logo_window) DestroyWindow(logo_window);
  logo_window = nullptr;
  rce = std::make_unique<Gdiplus::Image>(rce_path);
  danruguo = std::make_unique<Gdiplus::Image>(dan_path);
  if (rce->GetLastStatus() != Gdiplus::Ok || danruguo->GetLastStatus() != Gdiplus::Ok) return 0;
  WNDCLASSW cls{};
  cls.lpfnWndProc = LogoProcedure;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"DanPlayerInstallerBrand";
  RegisterClassW(&cls);
  background_color = background;
  completed = callback;
  BOOL animations = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
  HIGHCONTRASTW contrast{}; contrast.cbSize = sizeof(contrast);
  SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
  reduce_motion = !animations || (contrast.dwFlags & HCF_HIGHCONTRASTON);
  started = GetTickCount64();
  logo_window = CreateWindowExW(0, cls.lpszClassName, L"", WS_CHILD | WS_VISIBLE,
      0, 0, width, height, parent, nullptr, cls.hInstance, nullptr);
  if (!logo_window) { completed = nullptr; return 0; }
  SetTimer(logo_window, 1, 16, nullptr);
  return 1;
}
extern "C" __declspec(dllexport) void __stdcall DP_CloseBrand() {
  completed = nullptr;
  if (logo_window) DestroyWindow(logo_window);
  logo_window = nullptr;
  rce.reset(); danruguo.reset();
  if (private_font) RemoveFontMemResourceEx(private_font);
  private_font = nullptr;
  private_font_bytes.clear();
  if (gdiplus_token) Gdiplus::GdiplusShutdown(gdiplus_token);
  gdiplus_token = 0;
}
