#include "../desktop_integration_fonts.h"
#include "../desktop_integration_tray_style.h"
#include "../desktop_integration_policy.h"

#include <iostream>
#include <fstream>
#include <iterator>
#include <vector>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
  std::cerr << "Failed line " << __LINE__ << ": " #condition "\n"; \
  return 1; } } while (false)
}

// Headless GDI validation: creates memory DCs only, never a window or menu.
int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 3);
  desktop_integration::PopupFonts fonts;
  CHECK(fonts.Configure(L"DanPingFangSC", argv[1]));
  CHECK(fonts.private_font_loaded());
  CHECK(!fonts.face().empty());
  fonts.Ensure(96);
  HDC dc = CreateCompatibleDC(nullptr);
  CHECK(dc != nullptr);
  auto old = SelectObject(dc, fonts.row());
  WCHAR actual[LF_FACESIZE]{};
  CHECK(GetTextFaceW(dc, LF_FACESIZE, actual) > 0);
  CHECK(_wcsicmp(actual, fonts.face().c_str()) == 0);
  TEXTMETRICW metrics{};
  CHECK(GetTextMetricsW(dc, &metrics));
  CHECK(metrics.tmWeight >= FW_SEMIBOLD);
  // Verify the realized GDI face's bytes, not only its family string.
  std::ifstream input(argv[1], std::ios::binary);
  const std::vector<unsigned char> expected((std::istreambuf_iterator<char>(input)), {});
  const DWORD native_size = GetFontData(dc, 0, 0, nullptr, 0);
  CHECK(native_size == expected.size());
  std::vector<unsigned char> native_bytes(native_size);
  CHECK(GetFontData(dc, 0, 0, native_bytes.data(), native_size) == native_size);
  CHECK(native_bytes == expected);
  const WCHAR sample[] = L"Dan\u6b4c\u8bcd";
  WORD glyphs[5]{};
  CHECK(GetGlyphIndicesW(dc, sample, 5, glyphs, GGI_MARK_NONEXISTING_GLYPHS) != GDI_ERROR);
  for (WORD glyph : glyphs) CHECK(glyph != 0xffff);
  const wchar_t korean[] = L"\ud55c\uad6d\uc5b4 A";
  const auto korean_font = fonts.ForText(dc, korean);
  SelectObject(dc, korean_font);
  WORD korean_glyphs[5]{};
  CHECK(GetGlyphIndicesW(dc, korean, 5, korean_glyphs, GGI_MARK_NONEXISTING_GLYPHS) != GDI_ERROR);
  for (WORD glyph : korean_glyphs) CHECK(glyph != 0xffff);
  CHECK(korean_font != fonts.row());
  CHECK(fonts.ForText(dc, korean) == korean_font);
  CHECK(fonts.ForText(dc, L"Dan\u6b4c\u8bcd") == fonts.row());
  SelectObject(dc, old);
  CHECK(DeleteDC(dc));
  LOGFONTW font{};
  CHECK(GetObjectW(fonts.row(), sizeof(font), &font) == sizeof(font));
  CHECK(font.lfHeight == -15 && font.lfWeight == FW_BOLD);
  const HFONT cached = fonts.row();
  for (int frame = 0; frame < 40; ++frame) fonts.Ensure(96);
  CHECK(fonts.row() == cached);
  CHECK(!fonts.Configure(L"DanPingFangSC", argv[1]));
  CHECK(fonts.row() == cached);
  fonts.Ensure(192);
  CHECK(GetObjectW(fonts.row(), sizeof(font), &font) == sizeof(font));
  CHECK(font.lfHeight == -30);
  CHECK(fonts.Configure(L"CustomFontLoaderAlias", argv[1]));
  CHECK(fonts.private_font_loaded());
  CHECK(!fonts.face().empty());
  fonts.Ensure(96);
  CHECK(fonts.ConfigureIcons(argv[2]));
  fonts.Ensure(96);
  CHECK(fonts.material_icons_loaded());
  dc = CreateCompatibleDC(nullptr);
  CHECK(dc != nullptr);
  old = SelectObject(dc, fonts.icons());
  CHECK(GetTextFaceW(dc, LF_FACESIZE, actual) > 0);
  CHECK(_wcsicmp(actual, fonts.icon_face().c_str()) == 0);
  constexpr wchar_t symbols[]{0xe89e, 0xe911, 0xe045, 0xe037, 0xe034, 0xe044, 0xec0b, 0xf8c7, 0xe668};
  WORD symbol_glyphs[9]{};
  CHECK(GetGlyphIndicesW(dc, symbols, 9, symbol_glyphs, GGI_MARK_NONEXISTING_GLYPHS) != GDI_ERROR);
  for (WORD glyph : symbol_glyphs) CHECK(glyph != 0xffff);
  CHECK(GetObjectW(fonts.icons(), sizeof(font), &font) == sizeof(font));
  CHECK(font.lfHeight == -20 && font.lfWeight == FW_NORMAL);
  SelectObject(dc, old);
  CHECK(DeleteDC(dc));
  const auto cached_icons = fonts.icons();
  for (int frame = 0; frame < 500; ++frame) fonts.Ensure(96);
  CHECK(fonts.icons() == cached_icons);
  CHECK(!fonts.ConfigureIcons(argv[2]));
  CHECK(desktop_integration::PopupMaterialIndex(desktop_integration::PopupIcon::kToggle, false) == 3);
  CHECK(desktop_integration::PopupMaterialIndex(desktop_integration::PopupIcon::kToggle, true) == 4);
  for (const UINT dpi : {96u, 120u, 144u, 192u, 288u}) {
    fonts.Ensure(dpi);
    CHECK(GetObjectW(fonts.icons(), sizeof(font), &font) == sizeof(font));
    CHECK(font.lfHeight == -MulDiv(20, static_cast<int>(dpi), 96));
    HDC canvas = CreateCompatibleDC(nullptr);
    CHECK(canvas != nullptr);
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = 512;
    info.bmiHeader.biHeight = -256;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    void* pixels = nullptr;
    HBITMAP bitmap = CreateDIBSection(canvas, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
    CHECK(bitmap && pixels);
    const auto old_bitmap = SelectObject(canvas, bitmap);
    const RECT row{0, 0, 500, MulDiv(44, static_cast<int>(dpi), 96)};
    const RECT capsule = desktop_integration::TrayIconCapsuleRect(row, dpi);
    CHECK(capsule.right - capsule.left == MulDiv(36, static_cast<int>(dpi), 96));
    CHECK(capsule.bottom - capsule.top == MulDiv(30, static_cast<int>(dpi), 96));
    CHECK(std::abs((capsule.top + capsule.bottom) - (row.top + row.bottom)) <= 1);
    for (const bool dark : {false, true}) {
      const COLORREF surface = dark ? RGB(32, 32, 32) : RGB(250, 250, 250);
      RECT whole{0, 0, 512, 256};
      SetDCBrushColor(canvas, surface);
      FillRect(canvas, &whole, static_cast<HBRUSH>(GetStockObject(DC_BRUSH)));
      const auto background = desktop_integration::TrayIconCapsuleColor(RGB(30, 160, 180), surface, dark, true);
      const auto foreground = desktop_integration::ContrastAdjustedAccent(RGB(30, 160, 180), background);
      CHECK(desktop_integration::ContrastRatio(foreground, background) >= 4.5);
      desktop_integration::PaintTrayIconCapsule(canvas, capsule, fonts.icons(), symbols[3], background, foreground);
      CHECK(GetPixel(canvas, capsule.left, capsule.top) == surface);
      CHECK(GetPixel(canvas, capsule.left + 1, (capsule.top + capsule.bottom) / 2) == background);
      const DWORD hover_baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
      for (int hover = 0; hover < 500; ++hover) {
        desktop_integration::PaintTrayIconCapsule(canvas, capsule, fonts.icons(), symbols[hover % 9], background, foreground);
      }
      CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == hover_baseline);
    }
    SelectObject(canvas, old_bitmap);
    CHECK(DeleteObject(bitmap));
    CHECK(DeleteDC(canvas));
  }
  fonts.Clear();
  CHECK(!fonts.private_font_loaded());
  CHECK(fonts.Configure(L"DanPingFangSC", L"Z:\\missing-font-for-test.ttf"));
  CHECK(!fonts.private_font_loaded());
  CHECK(fonts.face().empty());
  fonts.Ensure(96);
  CHECK(fonts.row() != nullptr);
  fonts.Clear();
  const DWORD baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int cycle = 0; cycle < 40; ++cycle) {
    CHECK(fonts.Configure(L"DanPingFangSC", argv[1]));
    fonts.Ensure(cycle % 2 == 0 ? 96 : 192);
    fonts.Clear();
  }
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= baseline + 1);
  std::cout << checks << " native font checks passed (no GUI)\n";
  return 0;
}
