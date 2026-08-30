#include "../desktop_integration_fonts.h"

#include <iostream>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
  std::cerr << "Failed line " << __LINE__ << ": " #condition "\n"; \
  return 1; } } while (false)
}

// Headless GDI validation: creates memory DCs only, never a window or menu.
int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 2);
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
  const WCHAR sample[] = L"Dan\u6b4c\u8bcd";
  WORD glyphs[5]{};
  CHECK(GetGlyphIndicesW(dc, sample, 5, glyphs, GGI_MARK_NONEXISTING_GLYPHS) != GDI_ERROR);
  for (WORD glyph : glyphs) CHECK(glyph != 0xffff);
  SelectObject(dc, old);
  CHECK(DeleteDC(dc));
  LOGFONTW font{};
  CHECK(GetObjectW(fonts.row(), sizeof(font), &font) == sizeof(font));
  CHECK(font.lfHeight == -14);
  const HFONT cached = fonts.row();
  for (int frame = 0; frame < 40; ++frame) fonts.Ensure(96);
  CHECK(fonts.row() == cached);
  CHECK(!fonts.Configure(L"DanPingFangSC", argv[1]));
  CHECK(fonts.row() == cached);
  fonts.Ensure(192);
  CHECK(GetObjectW(fonts.row(), sizeof(font), &font) == sizeof(font));
  CHECK(font.lfHeight == -28);
  CHECK(fonts.Configure(L"CustomFontLoaderAlias", argv[1]));
  CHECK(fonts.private_font_loaded());
  CHECK(!fonts.face().empty());
  fonts.Ensure(96);
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
