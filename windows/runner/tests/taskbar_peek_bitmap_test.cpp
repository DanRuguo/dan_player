#include <windows.h>

#include "../taskbar_thumbnail_policy.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
  std::cerr << "Failed line " << __LINE__ << ": " #condition "\n"; \
  return 1; } } while (false)
}

// Same source/layout/writer as the production Peek path, but no HWND, desktop
// capture, Flutter engine or user data. Every temporary DIB is released.
int main() {
  namespace peek = taskbar_thumbnail;
  const auto started = std::chrono::steady_clock::now();
  const DWORD baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  std::vector<std::uint8_t> source(1440 * 720 * 4);
  for (std::size_t index = 0; index < source.size(); index += 4) {
    const auto x = (index / 4) % 1440;
    source[index] = x < 4 ? 10 : x >= 1436 ? 240 : 120;
    source[index + 1] = 60;
    source[index + 2] = 130;
    source[index + 3] = 255;
  }
  peek::Image image;
  CHECK(image.SetPeek(1440, 720, source) == peek::Update::kChanged);
  const std::array<peek::Size, 5> clients{
      peek::Size{1280, 800}, peek::Size{1920, 1080}, peek::Size{2560, 1440},
      peek::Size{1080, 1920}, peek::Size{3840, 2160}};
  std::array<std::int64_t, 5> microseconds{};
  for (int cycle = 0; cycle < 3; ++cycle) {
    for (std::size_t sample = 0; sample < clients.size(); ++sample) {
      const auto client = clients[sample];
      const auto frame_started = std::chrono::steady_clock::now();
      const auto layout = peek::FitPeekLayout(image.size(), client);
      const auto bytes = static_cast<std::size_t>(layout.canvas.width) * layout.canvas.height * 4;
      CHECK(layout.content.width > 480 && layout.content.height > 240);
      CHECK(peek::ValidPeekCanvas(layout.canvas, bytes));
      CHECK(bytes <= 16 * 1024 * 1024);
      BITMAPINFO info{};
      info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
      info.bmiHeader.biWidth = layout.canvas.width;
      info.bmiHeader.biHeight = -layout.canvas.height;
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      void* storage = nullptr;
      HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS,
                                         &storage, nullptr, 0);
      CHECK(bitmap && storage);
      CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline + 1);
      CHECK(image.WritePeekBgra(layout, static_cast<std::uint8_t*>(storage), bytes));
      const auto* pixels = static_cast<const std::uint8_t*>(storage);
      const auto pixel = [&](int x, int y) {
        const auto index = (static_cast<std::size_t>(y) * layout.canvas.width + x) * 4;
        return std::array<std::uint8_t, 4>{pixels[index], pixels[index + 1],
                                          pixels[index + 2], pixels[index + 3]};
      };
      CHECK(pixel(0, 0) == (std::array<std::uint8_t, 4>{130, 60, source[0], 255}));
      CHECK(pixel(layout.left, layout.top) ==
            (std::array<std::uint8_t, 4>{130, 60, source[0], 255}));
      CHECK(pixel(layout.left + layout.content.width - 1,
                  layout.top + layout.content.height - 1) ==
            (std::array<std::uint8_t, 4>{130, 60, source[source.size() - 4], 255}));
      CHECK(DeleteObject(bitmap));
      CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
      CHECK(image.bytes() == source.size());
      microseconds[sample] += std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - frame_started).count();
    }
  }
  CHECK(image.Clear());
  CHECK(image.bytes() == 0);
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
  const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
      std::chrono::steady_clock::now() - started).count();
  std::cout << checks << " Peek DIB/pixel/lifetime checks passed (15 synthetic frames, "
            << elapsed << "ms total; no HWND/capture)\n";
  for (std::size_t sample = 0; sample < clients.size(); ++sample) {
    std::cout << clients[sample].width << 'x' << clients[sample].height
              << ": " << microseconds[sample] / 3000.0
              << "ms/frame (mean of 3, includes allocate/write/check/release)\n";
  }
  return 0;
}
