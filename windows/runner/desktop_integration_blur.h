#ifndef RUNNER_DESKTOP_INTEGRATION_BLUR_H_
#define RUNNER_DESKTOP_INTEGRATION_BLUR_H_

#ifndef GDIPVER
#define GDIPVER 0x0110
#endif
#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

#pragma comment(lib, "gdiplus.lib")

namespace desktop_integration {

constexpr double kMaxTrayBlurRadius = 24.0;
// Retained DIB <= 4 MiB. GDI+ convolution has additional temporary storage;
// this is a pixel/work budget, not a claim about total process memory.
constexpr std::uint64_t kMaxTrayBlurPixels = 1024 * 1024;

inline bool ValidTrayBlurRadius(double radius) {
  return std::isfinite(radius) && radius >= 0 && radius <= kMaxTrayBlurRadius;
}

// Logical-pixel Gaussian kernel radius, not sigma, opacity or an acrylic tint.
inline float TrayBlurPixelRadius(double radius, UINT dpi) {
  if (!ValidTrayBlurRadius(radius) || dpi < 48 || dpi > 768) return 0;
  return static_cast<float>(radius * dpi / 96.0);
}

inline bool TrayBlurAllowed(bool high_contrast, bool advanced_effects,
                           bool energy_saver) {
  return !high_contrast && advanced_effects && !energy_saver;
}

inline bool ValidTrayBlurRect(const RECT& rect, const RECT& work) {
  const auto width = static_cast<std::int64_t>(rect.right) - rect.left;
  const auto height = static_cast<std::int64_t>(rect.bottom) - rect.top;
  return width > 0 && height > 0 && width <= 4096 && height <= 4096 &&
         static_cast<std::uint64_t>(width * height) <= kMaxTrayBlurPixels &&
         rect.left >= work.left && rect.top >= work.top &&
         rect.right <= work.right && rect.bottom <= work.bottom;
}

// If the complete menu cannot fit (tiny/RDP work area), let the system HMENU
// handle scrolling instead of clipping controls or reading beyond a display.
inline bool PlaceTrayPopup(POINT anchor, int width, int height,
                           const RECT& work, RECT* output) {
  const auto work_width = static_cast<std::int64_t>(work.right) - work.left;
  const auto work_height = static_cast<std::int64_t>(work.bottom) - work.top;
  if (!output || width <= 0 || height <= 0 || width > work_width ||
      height > work_height) return false;
  const auto left = std::clamp(static_cast<std::int64_t>(anchor.x) - width,
      static_cast<std::int64_t>(work.left),
      static_cast<std::int64_t>(work.right) - width);
  const auto top = std::clamp(static_cast<std::int64_t>(anchor.y) - height,
      static_cast<std::int64_t>(work.top),
      static_cast<std::int64_t>(work.bottom) - height);
  *output = {static_cast<LONG>(left), static_cast<LONG>(top),
             static_cast<LONG>(left + width), static_cast<LONG>(top + height)};
  return true;
}

// One exact-menu capture on Open, then only an in-memory blurred bitmap.
// Capture is injected so tests NEVER read desktop pixels or create a window.
// No padding/overscan, timer, file output or full-screen intermediate exists.
class PopupBlurImage {
 public:
  PopupBlurImage() = default;
  ~PopupBlurImage() { Clear(); }
  PopupBlurImage(const PopupBlurImage&) = delete;
  PopupBlurImage& operator=(const PopupBlurImage&) = delete;

  template <typename Capture>
  bool Open(const RECT& rect, const RECT& work, double logical_radius, UINT dpi,
            bool allowed, Capture&& capture) {
    Clear();
    const float radius = TrayBlurPixelRadius(logical_radius, dpi);
    if (!allowed || radius <= 0 || !ValidTrayBlurRect(rect, work)) return false;
    Gdiplus::GdiplusStartupInput startup;
    if (Gdiplus::GdiplusStartup(&gdiplus_, &startup, nullptr) != Gdiplus::Ok) {
      gdiplus_ = 0;
      return false;
    }
    width_ = rect.right - rect.left;
    height_ = rect.bottom - rect.top;
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width_;
    info.bmiHeader.biHeight = -height_;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    bitmap_ = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels_, nullptr, 0);
    if (!bitmap_ || !pixels_) { Clear(); return false; }
    const HDC target = CreateCompatibleDC(nullptr);
    if (!target) { Clear(); return false; }
    const auto previous = SelectObject(target, bitmap_);
    const bool captured = previous && previous != HGDI_ERROR && capture(target, rect);
    // Screen BitBlt is batched; flush before reading its DIB on the CPU.
    GdiFlush();
    if (previous && previous != HGDI_ERROR) SelectObject(target, previous);
    DeleteDC(target);
    if (!captured || !ApplyGaussian(radius)) { Clear(); return false; }
    return true;
  }

  void Clear() {
    // Erase both success and partial-capture buffers before releasing them.
    if (pixels_) SecureZeroMemory(pixels_, byte_count());
    pixels_ = nullptr;
    if (bitmap_) DeleteObject(bitmap_);
    bitmap_ = nullptr;
    width_ = height_ = 0;
    if (gdiplus_) Gdiplus::GdiplusShutdown(gdiplus_);
    gdiplus_ = 0;
  }

  bool Draw(HDC dc, const RECT& client, COLORREF theme_background) const {
    if (!ready() || client.right - client.left != width_ ||
        client.bottom - client.top != height_) return false;
    Gdiplus::Bitmap image(width_, height_, width_ * 4, PixelFormat32bppARGB,
                          static_cast<BYTE*>(pixels_));
    Gdiplus::Graphics graphics(dc);
    // Fixed 80% theme tint preserves text contrast; it never changes with the
    // blur slider. The remaining 20% is the real Gaussian-filtered backdrop.
    const Gdiplus::ColorMatrix tint = {{
        {.2f, 0, 0, 0, 0}, {0, .2f, 0, 0, 0}, {0, 0, .2f, 0, 0},
        {0, 0, 0, 1, 0},
        {GetRValue(theme_background) / 255.0f * .8f,
         GetGValue(theme_background) / 255.0f * .8f,
         GetBValue(theme_background) / 255.0f * .8f, 0, 1}}};
    Gdiplus::ImageAttributes attributes;
    attributes.SetColorMatrix(&tint);
    return graphics.DrawImage(&image,
        Gdiplus::Rect(client.left, client.top, width_, height_), 0, 0,
        width_, height_, Gdiplus::UnitPixel, &attributes) == Gdiplus::Ok;
  }

  bool ready() const { return bitmap_ && pixels_; }
  std::size_t byte_count() const {
    return static_cast<std::size_t>(width_) * height_ * 4;
  }
  const std::uint32_t* pixels() const {
    return static_cast<const std::uint32_t*>(pixels_);
  }

 private:
  bool ApplyGaussian(float radius) {
    auto* pixels = static_cast<std::uint32_t*>(pixels_);
    const auto count = byte_count() / 4;
    for (std::size_t i = 0; i < count; ++i) pixels[i] |= 0xff000000u;
    Gdiplus::Bitmap image(width_, height_, width_ * 4, PixelFormat32bppARGB,
                          static_cast<BYTE*>(pixels_));
    Gdiplus::Blur blur;
    Gdiplus::BlurParams parameters{radius, FALSE};
    if (image.GetLastStatus() != Gdiplus::Ok ||
        blur.SetParameters(&parameters) != Gdiplus::Ok ||
        image.ApplyEffect(&blur, nullptr) != Gdiplus::Ok) return false;
    // GDI+ may replace its internal storage during ApplyEffect. Copy the
    // filtered image back before disposing that temporary storage.
    Gdiplus::BitmapData filtered{};
    const Gdiplus::Rect bounds(0, 0, width_, height_);
    if (image.LockBits(&bounds, Gdiplus::ImageLockModeRead,
                       PixelFormat32bppARGB, &filtered) != Gdiplus::Ok) return false;
    for (int y = 0; y < height_; ++y) {
      std::memmove(pixels + static_cast<std::size_t>(y) * width_,
          static_cast<BYTE*>(filtered.Scan0) + y * filtered.Stride, width_ * 4);
    }
    const bool unlocked = image.UnlockBits(&filtered) == Gdiplus::Ok;
    for (std::size_t i = 0; i < count; ++i) pixels[i] |= 0xff000000u;
    return unlocked;
  }

  ULONG_PTR gdiplus_ = 0;
  HBITMAP bitmap_ = nullptr;
  void* pixels_ = nullptr;
  int width_ = 0;
  int height_ = 0;
};

}  // namespace desktop_integration
#endif  // RUNNER_DESKTOP_INTEGRATION_BLUR_H_
