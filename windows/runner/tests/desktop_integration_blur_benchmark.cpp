#include "../desktop_integration_blur.h"

#include <chrono>
#include <iomanip>
#include <iostream>
#include <vector>

// Timing diagnostic only; no pass/fail speed threshold or screen access.
// The only pixels are alternating mathematical 16px checkerboard blocks.
int main() {
  Gdiplus::GdiplusStartupInput input;
  ULONG_PTR token = 0;
  if (Gdiplus::GdiplusStartup(&token, &input, nullptr) != Gdiplus::Ok) return 1;
  const struct { int width; int height; UINT dpi; } cases[] = {
      {292, 406, 96}, {438, 609, 144}, {584, 812, 192}, {730, 1015, 240},
      {1024, 1024, 240}};
  std::cout << "Synthetic-only PopupBlurImage::Open, radius=24 logical px; one warmup + 5 trials.\n";
  for (const auto& sample : cases) {
    const RECT rect{0, 0, sample.width, sample.height};
    std::vector<double> elapsed;
    desktop_integration::PopupBlurImage image;
    const auto synthetic = [](HDC target, const RECT& bounds) {
      DIBSECTION dib{};
      const auto bitmap = GetCurrentObject(target, OBJ_BITMAP);
      if (GetObjectW(bitmap, sizeof(dib), &dib) != sizeof(dib) || !dib.dsBm.bmBits) return false;
      auto* pixels = static_cast<std::uint32_t*>(dib.dsBm.bmBits);
      for (int y = 0; y < bounds.bottom; ++y) {
        for (int x = 0; x < bounds.right; ++x) {
          pixels[y * bounds.right + x] = ((x / 16 + y / 16) % 2) ? 0xffffffff : 0xff000000;
        }
      }
      return true;
    };
    for (int trial = -1; trial < 5; ++trial) {
      const auto start = std::chrono::steady_clock::now();
      if (!image.Open(rect, rect, 24, sample.dpi, true, synthetic)) return 2;
      const auto end = std::chrono::steady_clock::now();
      if (trial >= 0) elapsed.push_back(std::chrono::duration<double, std::milli>(end - start).count());
    }
    std::sort(elapsed.begin(), elapsed.end());
    std::cout << sample.width << 'x' << sample.height << " dpi=" << sample.dpi
              << " kernel_radius=" << desktop_integration::TrayBlurPixelRadius(24, sample.dpi)
              << " retained_bytes=" << image.byte_count() << std::fixed << std::setprecision(2)
              << " min_ms=" << elapsed.front() << " median_ms=" << elapsed[2]
              << " max_ms=" << elapsed.back() << '\n';
  }
  Gdiplus::GdiplusShutdown(token);
  return 0;
}
