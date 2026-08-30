#include "../desktop_integration_blur.h"

#include <iostream>
#include <limits>
#include <vector>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
  std::cerr << "Failed line " << __LINE__ << ": " #condition "\n"; \
  return 1; } } while (false)
}

// Memory DCs and synthetic black/white bars only. NO GetDC(NULL), BitBlt from
// a screen, HWND, image file, clipboard, screenshot or desktop pixels.
int main() {
  namespace tray = desktop_integration;
  CHECK(tray::ValidTrayBlurRadius(0));
  CHECK(tray::ValidTrayBlurRadius(24));
  CHECK(!tray::ValidTrayBlurRadius(-1));
  CHECK(!tray::ValidTrayBlurRadius(24.01));
  CHECK(!tray::ValidTrayBlurRadius(std::numeric_limits<double>::infinity()));
  CHECK(!tray::ValidTrayBlurRadius(std::numeric_limits<double>::quiet_NaN()));
  CHECK(tray::TrayBlurPixelRadius(12, 96) == 12);
  CHECK(tray::TrayBlurPixelRadius(12, 144) == 18);
  CHECK(tray::TrayBlurPixelRadius(12, 192) == 24);
  CHECK(tray::TrayBlurPixelRadius(24, 768) == 192);
  CHECK(tray::TrayBlurPixelRadius(12, 0) == 0);
  for (bool contrast : {false, true}) {
    for (bool effects : {false, true}) {
      for (bool saver : {false, true}) {
        CHECK(tray::TrayBlurAllowed(contrast, effects, saver) ==
              (!contrast && effects && !saver));
      }
    }
  }
  const RECT work{0, 0, 1920, 1080};
  RECT placed{};
  CHECK(tray::PlaceTrayPopup({0, 0}, 292, 406, work, &placed));
  CHECK(placed.left == 0 && placed.top == 0);
  CHECK(placed.right == 292 && placed.bottom == 406);
  CHECK(tray::PlaceTrayPopup({9999, 9999}, 292, 406, work, &placed));
  CHECK(placed.right == 1920 && placed.bottom == 1080);
  const RECT left_monitor{-1920, -200, 0, 880};
  CHECK(tray::PlaceTrayPopup({-800, 0}, 292, 406, left_monitor, &placed));
  CHECK(tray::ValidTrayBlurRect(placed, left_monitor));
  CHECK(!tray::PlaceTrayPopup({0, 0}, 292, 406, {0, 0, 250, 300}, &placed));
  CHECK(!tray::PlaceTrayPopup({0, 0}, 0, 406, work, &placed));
  CHECK(!tray::ValidTrayBlurRect({0, 0, 0, 1}, work));
  CHECK(!tray::ValidTrayBlurRect({-1, 0, 100, 100}, work));
  CHECK(!tray::ValidTrayBlurRect({0, 0, 1921, 100}, work));
  CHECK(!tray::ValidTrayBlurRect({0, 0, 2048, 2048}, {0, 0, 4096, 4096}));
  CHECK(tray::ValidTrayBlurRect({0, 0, 1024, 1024}, {0, 0, 4096, 4096}));
  CHECK(tray::ValidTrayBlurRect({0, 0, 2048, 512}, {0, 0, 4096, 4096}));
  CHECK(!tray::ValidTrayBlurRect({0, 0, 1025, 1024}, {0, 0, 4096, 4096}));
  CHECK(!tray::ValidTrayBlurRect({LONG_MIN, LONG_MIN, LONG_MAX, LONG_MAX}, work));

  tray::PopupBlurImage image;
  CHECK(!image.ready());
  CHECK(image.byte_count() == 0);
  int captures = 0;
  bool exact_rect = true;
  const RECT menu{200, 100, 264, 164};
  const auto synthetic = [&](HDC dc, const RECT& rect) {
    ++captures;
    exact_rect = exact_rect && EqualRect(&rect, &menu);
    const RECT background{0, 0, 64, 64};
    const RECT stripe{28, 0, 36, 64};
    return FillRect(dc, &background, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH))) &&
           FillRect(dc, &stripe, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  };
  CHECK(!image.Open(menu, work, 0, 96, true, synthetic));
  CHECK(!image.Open(menu, work, 12, 96, false, synthetic));
  CHECK(!image.Open(menu, work, 12, 99999, true, synthetic));
  CHECK(!image.Open({0, 0, 4096, 4096}, {0, 0, 4096, 4096}, 12, 96, true, synthetic));
  CHECK(!image.Open({0, 0, 1025, 1024}, {0, 0, 4096, 4096}, 24, 240, true, synthetic));
  CHECK(captures == 0);
  CHECK(image.Open(menu, work, 2, 96, true, synthetic));
  CHECK(image.ready() && exact_rect && captures == 1);
  CHECK(image.byte_count() == 64 * 64 * 4);
  const auto narrow_center = image.pixels()[32 * 64 + 32] & 255;
  const auto narrow_outside = image.pixels()[32 * 64 + 24] & 255;
  CHECK(image.Open(menu, work, 12, 96, true, synthetic));
  CHECK(captures == 2 && exact_rect);
  const auto wide_center = image.pixels()[32 * 64 + 32] & 255;
  const auto wide_outside = image.pixels()[32 * 64 + 24] & 255;
  CHECK(wide_center < narrow_center);  // Actual spatial convolution, not opacity.
  CHECK(wide_outside > narrow_outside);
  CHECK(wide_outside > 0);
  for (int x = 1; x < 28; ++x) {
    CHECK((image.pixels()[32 * 64 + x] & 255) <=
          (image.pixels()[32 * 64 + x + 1] & 255));
  }
  for (int i = 0; i < 64 * 64; ++i) CHECK((image.pixels()[i] >> 24) == 255);
  CHECK(image.Open(menu, work, 6, 192, true, synthetic));
  CHECK((image.pixels()[32 * 64 + 32] & 255) == wide_center);
  CHECK((image.pixels()[32 * 64 + 24] & 255) == wide_outside);
  const std::vector<std::uint32_t> cached(image.pixels(), image.pixels() + 64 * 64);
  const int before_paints = captures;
  const HDC drawing = CreateCompatibleDC(nullptr);
  const HBITMAP target = CreateBitmap(64, 64, 1, 32, nullptr);
  CHECK(drawing && target);
  const auto old = SelectObject(drawing, target);
  for (int frame = 0; frame < 20; ++frame) {
    CHECK(image.Draw(drawing, {0, 0, 64, 64}, frame % 2 ? RGB(250, 245, 240) : RGB(20, 30, 40)));
  }
  CHECK(!image.Draw(drawing, {0, 0, 65, 64}, RGB(0, 0, 0)));
  CHECK(captures == before_paints);  // Hover/theme repaints never recapture.
  CHECK(std::equal(cached.begin(), cached.end(), image.pixels()));
  SelectObject(drawing, old);
  DeleteObject(target);
  DeleteDC(drawing);
  image.Clear();
  CHECK(!image.ready() && image.pixels() == nullptr && image.byte_count() == 0);
  const DWORD baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int cycle = 0; cycle < 32; ++cycle) {
    CHECK(image.Open(menu, work, 8, 96, true, synthetic));
    if (cycle % 2 == 0) {
      // Failed capture retires the previous success, including partial pixels.
      CHECK(!image.Open(menu, work, 8, 96, true, [](HDC, const RECT&) { return false; }));
    }
    image.Clear();
    CHECK(!image.ready() && image.byte_count() == 0);
  }
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) <= baseline + 1);
  std::cout << checks << " tray Gaussian/policy/resource checks passed (synthetic pixels only, no GUI)\n";
  return 0;
}
