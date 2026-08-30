#include "../desktop_integration_paint.h"

#include <iostream>
#include <limits>

namespace {
int checks = 0;
#define CHECK(condition) do { ++checks; if (!(condition)) { \
  std::cerr << "Failed line " << __LINE__ << ": " #condition "\n"; \
  return 1; } } while (false)
}

// A synthetic memory surface only: no screen capture, visible HWND or music.
int main() {
  namespace tray = desktop_integration;
  // Warm the OS region allocator before lifetime measurements, independently
  // of our paint buffer; Windows may retain its two released region handles.
  HRGN warm_first = CreateRectRgn(0, 0, 1, 1);
  HRGN warm_second = CreateRectRgn(0, 0, 1, 1);
  CHECK(warm_first && warm_second);
  CHECK(DeleteObject(warm_first));
  CHECK(DeleteObject(warm_second));
  const DWORD process_baseline =
      GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = 600;
  info.bmiHeader.biHeight = -900;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  void* pixels = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS,
                                    &pixels, nullptr, 0);
  HDC target = CreateCompatibleDC(nullptr);
  CHECK(bitmap && pixels && target);
  const auto old = SelectObject(target, bitmap);
  const RECT entire{0, 0, 600, 900};
  FillRect(target, &entire, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  const DWORD baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  tray::PopupPaintBuffer buffer;
  int calls = 0;
  const auto nothing = [&](HDC) { ++calls; };
  CHECK(!buffer.Paint(target, entire, nothing));
  CHECK(!buffer.Open(0, 10));
  CHECK(!buffer.Open(-1, 10));
  CHECK(!buffer.Open(4097, 1));
  CHECK(!buffer.Open(4096, 4096));
  CHECK(!buffer.Open(std::numeric_limits<int>::max(), 900));
  CHECK(calls == 0);
  CHECK(buffer.Open(600, 900));
  CHECK(!buffer.Paint(nullptr, entire, nothing));
  const DWORD allocated = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  CHECK(allocated <= baseline + 2);
  bool intermediate_untouched = true;
  CHECK(buffer.Paint(target, entire, [&](HDC frame) {
    FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    intermediate_untouched = GetPixel(target, 12, 12) == RGB(255, 255, 255);
    SetTextColor(frame, RGB(0, 180, 180));
    SetBkMode(frame, TRANSPARENT);
    TextOutW(frame, 20, 20, L"Dan Player", 10);
  }));
  CHECK(intermediate_untouched);
  CHECK(GetPixel(target, 12, 12) == RGB(0, 0, 0));
  const COLORREF title_pixel = GetPixel(target, 23, 23);
  const RECT row{8, 100, 592, 144};
  // Repeated moves alternate enabled-row highlights. The header and other
  // rows stay bit-identical and GDI handles stay stable throughout.
  for (int iteration = 0; iteration < 500; ++iteration) {
    CHECK(buffer.Open(600, 900));
    const auto before = GetPixel(target, 100, 110);
    bool atomic = false;
    CHECK(buffer.Paint(target, row, [&](HDC frame) {
      FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(
          iteration % 2 ? WHITE_BRUSH : BLACK_BRUSH)));
      atomic = GetPixel(target, 100, 110) == before;
      SetPixel(frame, 100, 110, RGB(0, 160, iteration % 255));
      // A buggy renderer requesting a header repaint is clipped by the buffer.
      SetPixel(frame, 12, 12, RGB(255, 0, 0));
    }));
    CHECK(atomic);
    CHECK(GetPixel(target, 100, 110) == RGB(0, 160, iteration % 255));
    CHECK(GetPixel(target, 12, 12) == RGB(0, 0, 0));
    CHECK(GetPixel(target, 23, 23) == title_pixel);
    CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == allocated);
  }
  CHECK(buffer.Paint(target, {-50, -50, -1, -1}, nothing));
  CHECK(calls == 0);

  // A destination can become unavailable after Open succeeded. The failure
  // reaches WM_PAINT's fallback policy and does not silently claim a frame.
  HDC retired_target = CreateCompatibleDC(nullptr);
  CHECK(retired_target);
  CHECK(DeleteDC(retired_target));
  const COLORREF before_failure = GetPixel(target, 12, 12);
  bool failed_frame_drawn = false;
  CHECK(!buffer.Paint(retired_target, entire, [&](HDC frame) {
    failed_frame_drawn = true;
    FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  }));
  CHECK(failed_frame_drawn);
  CHECK(GetPixel(target, 12, 12) == before_failure);
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == allocated);

  // A failed destination blit does not poison the buffer or leak per-frame
  // mapping, font/text state into the following successful paint.
  POINT previous_origin{};
  int previous_background = 0;
  COLORREF previous_text = 0;
  CHECK(buffer.Paint(target, entire, [&](HDC frame) {
    GetViewportOrgEx(frame, &previous_origin);
    previous_background = GetBkMode(frame);
    previous_text = GetTextColor(frame);
    FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    SetViewportOrgEx(frame, 17, 21, nullptr);
    SetBkMode(frame, TRANSPARENT);
    SetTextColor(frame, RGB(10, 20, 30));
  }));
  bool restored_state = false;
  CHECK(buffer.Paint(target, entire, [&](HDC frame) {
    POINT origin{};
    GetViewportOrgEx(frame, &origin);
    restored_state = origin.x == previous_origin.x &&
        origin.y == previous_origin.y &&
        GetBkMode(frame) == previous_background &&
        GetTextColor(frame) == previous_text;
  }));
  CHECK(restored_state);
  CHECK(GetPixel(target, 12, 12) == RGB(0, 0, 0));

  // Resizing, DPI-like dimensions, close/reopen, and rejected bounds release
  // the old bitmap safely. No per-hover allocation or dangling selected GDI.
  for (int cycle = 0; cycle < 100; ++cycle) {
    for (int scale : {1, 2, 3}) {
      CHECK(buffer.Open(292 * scale, 406 * scale));
      CHECK(buffer.Paint(target, entire, [&](HDC frame) {
        FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
      }));
    }
    buffer.Clear();
    buffer.Clear();
    CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
  }
  // Invalid axes and overflowing/pixel-budget dimensions retire any previous
  // surface, so a later paint cannot reuse stale pixels with the wrong size.
  for (const int invalid : {-1, 0, 4097, std::numeric_limits<int>::max()}) {
    for (const int other : {1, 900, 4096, std::numeric_limits<int>::max()}) {
      CHECK(buffer.Open(600, 900));
      CHECK(!buffer.Open(invalid, other));
      CHECK(!buffer.Paint(target, entire, nothing));
      CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
      CHECK(buffer.Open(600, 900));
      CHECK(!buffer.Open(other, invalid));
      CHECK(!buffer.Paint(target, entire, nothing));
      CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
    }
  }
  CHECK(calls == 0);
  CHECK(buffer.Open(4096, 1024));  // Exactly the 4M-pixel backing budget.
  CHECK(!buffer.Open(4096, 1025));
  CHECK(!buffer.Paint(target, entire, nothing));
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
  CHECK(buffer.Open(1024, 4096));
  CHECK(!buffer.Open(1025, 4096));
  buffer.Clear();
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);

  // BeginPaint's destination clip can contain two disjoint dirty rows. Its
  // bounding rcPaint includes the gap, which must NOT be copied on screen.
  // Retire both the destination and our buffer before the final process-level
  // handle comparison, in addition to the steady per-hover lifetime checks.
  CHECK(buffer.Open(600, 900));
  CHECK(buffer.Paint(target, entire, [&](HDC frame) {
    FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
  }));
  const int saved_target = SaveDC(target);
  CHECK(saved_target != 0);
  HRGN first_row = CreateRectRgn(8, 200, 592, 244);
  HRGN last_row = CreateRectRgn(8, 288, 592, 332);
  CHECK(first_row && last_row);
  CHECK(CombineRgn(first_row, first_row, last_row, RGN_OR) == COMPLEXREGION);
  CHECK(SelectClipRgn(target, first_row) == COMPLEXREGION);
  CHECK(buffer.Paint(target, {8, 200, 592, 332}, [&](HDC frame) {
    FillRect(frame, &entire, static_cast<HBRUSH>(GetStockObject(WHITE_BRUSH)));
  }));
  CHECK(RestoreDC(target, saved_target));
  CHECK(DeleteObject(first_row));
  CHECK(DeleteObject(last_row));
  CHECK(GetPixel(target, 100, 210) == RGB(255, 255, 255));
  CHECK(GetPixel(target, 100, 300) == RGB(255, 255, 255));
  CHECK(GetPixel(target, 100, 260) == RGB(0, 0, 0));
  CHECK(GetPixel(target, 12, 12) == RGB(0, 0, 0));
  buffer.Clear();
  CHECK(SelectObject(target, old));
  CHECK(DeleteDC(target));
  CHECK(DeleteObject(bitmap));
  GdiFlush();
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == process_baseline);
  std::cout << checks << " popup atomic-paint/clipping/lifetime checks passed\n";
  return 0;
}
