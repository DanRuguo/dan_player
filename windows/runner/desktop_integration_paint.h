#ifndef RUNNER_DESKTOP_INTEGRATION_PAINT_H_
#define RUNNER_DESKTOP_INTEGRATION_PAINT_H_

#include <windows.h>

#include <cstdint>

namespace desktop_integration {

// One bounded backing surface per open popup. Hover never allocates a bitmap,
// captures the desktop, or exposes the background-only intermediate frame.
class PopupPaintBuffer {
 public:
  PopupPaintBuffer() = default;
  ~PopupPaintBuffer() { Clear(); }
  PopupPaintBuffer(const PopupPaintBuffer&) = delete;
  PopupPaintBuffer& operator=(const PopupPaintBuffer&) = delete;

  bool Open(int width, int height) {
    if (dc_ && width == width_ && height == height_) return true;
    Clear();
    if (width <= 0 || height <= 0 || width > 4096 || height > 4096 ||
        static_cast<std::int64_t>(width) * height > 4 * 1024 * 1024) {
      return false;
    }
    BITMAPINFO info{};
    info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth = width;
    info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1;
    info.bmiHeader.biBitCount = 32;
    info.bmiHeader.biCompression = BI_RGB;
    void* pixels = nullptr;
    bitmap_ = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &pixels,
                               nullptr, 0);
    dc_ = CreateCompatibleDC(nullptr);
    if (!bitmap_ || !pixels || !dc_) { Clear(); return false; }
    original_ = SelectObject(dc_, bitmap_);
    if (!original_ || original_ == HGDI_ERROR) { Clear(); return false; }
    width_ = width;
    height_ = height;
    return true;
  }

  template <typename Draw>
  bool Paint(HDC target, const RECT& dirty, Draw&& draw) {
    if (!dc_ || !target) return false;
    const RECT client{0, 0, width_, height_};
    RECT clipped{};
    if (!IntersectRect(&clipped, &client, &dirty)) return true;
    const int saved = SaveDC(dc_);
    if (saved == 0) return false;
    IntersectClipRect(dc_, clipped.left, clipped.top,
                       clipped.right, clipped.bottom);
    draw(dc_);
    RestoreDC(dc_, saved);
    // This is the only write to the visible window, after ALL text and icons
    // are ready. BeginPaint's destination clip preserves disjoint dirty rows.
    return BitBlt(target, clipped.left, clipped.top,
                  clipped.right - clipped.left, clipped.bottom - clipped.top,
                  dc_, clipped.left, clipped.top, SRCCOPY) != FALSE;
  }

  void Clear() {
    if (dc_ && original_ && original_ != HGDI_ERROR) SelectObject(dc_, original_);
    if (dc_) DeleteDC(dc_);
    if (bitmap_) DeleteObject(bitmap_);
    dc_ = nullptr;
    bitmap_ = nullptr;
    original_ = nullptr;
    width_ = height_ = 0;
  }

 private:
  HDC dc_ = nullptr;
  HBITMAP bitmap_ = nullptr;
  HGDIOBJ original_ = nullptr;
  int width_ = 0;
  int height_ = 0;
};

}  // namespace desktop_integration

#endif  // RUNNER_DESKTOP_INTEGRATION_PAINT_H_
