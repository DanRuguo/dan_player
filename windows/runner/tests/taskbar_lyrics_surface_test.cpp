#include "../taskbar_lyrics.h"
#include "taskbar_lyrics_test_windows.h"
#include <gdiplus.h>
#include <dwmapi.h>
#include <iostream>
#include <vector>

namespace {
int checks = 0;
#define CHECK(value) do { ++checks; if (!(value)) { std::cerr << "Failed line " << __LINE__ << ": " #value "\n"; return 1; } } while(false)
void Pump(DWORD duration) {
  const auto deadline = GetTickCount64() + duration;
  do {
    MSG message;
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message); DispatchMessageW(&message);
    }
    MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
  } while (GetTickCount64() < deadline);
}
bool SaveRegion(const RECT& bounds, const std::wstring& path, bool expect_lyrics) {
  DwmFlush(); GdiFlush();
  const int width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
  if (width <= 0 || width > 7680 || height <= 0 || height > 960) return false;
  HDC screen = GetDC(nullptr), memory = CreateCompatibleDC(screen);
  HBITMAP bitmap = CreateCompatibleBitmap(screen, width, height);
  if (!screen || !memory || !bitmap) {
    if (screen) ReleaseDC(nullptr, screen); if (memory) DeleteDC(memory);
    if (bitmap) DeleteObject(bitmap); return false;
  }
  auto old = SelectObject(memory, bitmap);
  const bool copied = BitBlt(memory, 0, 0, width, height, screen,
                             bounds.left, bounds.top, SRCCOPY | CAPTUREBLT) != FALSE;
  GdiFlush();
  SelectObject(memory, old); DeleteDC(memory); ReleaseDC(nullptr, screen);
  bool saved = false;
  if (copied) {
    Gdiplus::Bitmap image(bitmap, nullptr);
    int foreground_pixels = 0;
    for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x) {
      Gdiplus::Color color;
      image.GetPixel(x, y, &color);
      if (color.GetB() > color.GetR() + 15 && color.GetG() > color.GetR() + 10) ++foreground_pixels;
    }
    const CLSID png{0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
    saved = image.Save(path.c_str(), &png, nullptr) == Gdiplus::Ok;
    std::cout << "captured foreground pixels=" << foreground_pixels << '\n';
    saved &= expect_lyrics ? foreground_pixels > 20 : foreground_pixels == 0;
  }
  DeleteObject(bitmap); return saved;
}
bool SaveSurface(HWND window, const std::wstring& path) {
  RECT bounds{};
  return GetWindowRect(window, &bounds) && SaveRegion(bounds, path, true);
}
HWND OwnedSurface() {
  HWND window = FindOwnedTaskbarWindow(L"DanPlayer.TaskbarLyrics.v1");
  DWORD process = 0; GetWindowThreadProcessId(window, &process);
  return process == GetCurrentProcessId() ? window : nullptr;
}
bool WaitVisible() {
  const auto deadline = GetTickCount64() + 4000;
  while (GetTickCount64() < deadline) {
    Pump(10);
    if (auto window = OwnedSurface(); window && IsWindowVisible(window)) return true;
  }
  return false;
}
}

// This creates only our temporary click-through lyric surface in the already
// measured primary taskbar gap. It never moves Explorer, reads application
// names, changes taskbar settings, sends input, activates a window or kills a
// process. Captures are restricted to that gap, excluding occupied controls.
int wmain(int argc, wchar_t** argv) {
  CHECK(argc == 3);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  ULONG_PTR gdiplus = 0; Gdiplus::GdiplusStartupInput input;
  CHECK(Gdiplus::GdiplusStartup(&gdiplus, &input, nullptr) == Gdiplus::Ok);
  const std::wstring font = argv[1], output = argv[2];
  const HWND foreground = GetForegroundWindow();
  TaskbarLyrics lyrics;
  auto frame = [&](std::wstring text, std::wstring next, std::wstring line,
                   double position, bool animate = true, bool playing = true,
                   std::vector<TaskbarLyricWord> words = {}, std::int64_t revision = 0) {
    return lyrics.Set(true, std::move(text), 0xff62bbdf, L"DanPingFangSC", font,
        animate, playing, std::move(words), std::move(next), position, 1,
        L"qa-source", std::move(line), revision, 0, 4000);
  };
  CHECK(frame(L"第一句 · First line", L"下一句 · Next line", L"0", 0));
  CHECK(WaitVisible());
  Pump(210);
  const HWND surface = OwnedSurface(); CHECK(surface);
  CHECK(GetWindowLongPtrW(surface, GWL_STYLE) & WS_CHILD);
  const auto style = GetWindowLongPtrW(surface, GWL_EXSTYLE);
  CHECK((style & WS_EX_LAYERED) && (style & WS_EX_TRANSPARENT) && (style & WS_EX_NOACTIVATE));
  CHECK(GetParent(surface) == FindWindowW(L"Shell_TrayWnd", nullptr));
  CHECK(SendMessageW(surface, WM_NCHITTEST, 0, 0) == HTTRANSPARENT);
  CHECK(GetForegroundWindow() == foreground);
  RECT bounds{}, bar{};
  CHECK(GetWindowRect(surface, &bounds) && GetWindowRect(FindWindowW(L"Shell_TrayWnd", nullptr), &bar));
  CHECK(bounds.left >= bar.left && bounds.right <= bar.right && bounds.top == bar.top && bounds.bottom == bar.bottom);
  using WindowBand = BOOL (WINAPI*)(HWND, DWORD*);
  const auto band_api = reinterpret_cast<WindowBand>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetWindowBand"));
  if (band_api) {
    DWORD surface_band = 0, taskbar_band = 0;
    band_api(surface, &surface_band); band_api(FindWindowW(L"Shell_TrayWnd", nullptr), &taskbar_band);
    std::cout << "readonly bands surface=" << surface_band << " taskbar=" << taskbar_band << '\n';
  }
  bool tray_above = false;
  for (HWND above = GetWindow(surface, GW_HWNDPREV); above; above = GetWindow(above, GW_HWNDPREV))
    if (above == FindWindowW(L"Shell_TrayWnd", nullptr)) tray_above = true;
  std::cout << "taskbar before surface in zorder=" << tray_above << '\n';
  CHECK(SaveSurface(surface, output + L"/double-before.png"));
  CHECK(frame(L"下一句 · Next line", L"再下一句 · Following line", L"1", 300));
  CHECK(SaveSurface(surface, output + L"/double-start.png"));
  Pump(280);
  CHECK(SaveSurface(surface, output + L"/double-middle.png"));
  Pump(300);
  CHECK(SaveSurface(surface, output + L"/double-end.png"));
  CHECK(frame(L"真实词高亮", L"下一句预览", L"2", 150, false, false,
      {{-1000, 1100, L"真"}, {100, 300, L"实词"}, {400, 500, L"高亮"}}, 1));
  CHECK(SaveSurface(surface, output + L"/word-partial.png"));
  CHECK(frame(L"真实词高亮", L"下一句预览", L"2", 900, false, false,
      {{-1000, 1100, L"真"}, {100, 300, L"实词"}, {400, 500, L"高亮"}}, 2));
  CHECK(SaveSurface(surface, output + L"/word-complete.png"));
  for (const auto& pair : std::vector<std::pair<std::wstring, std::wstring>>{
      {L"zh", L"原文歌词首尾完整"}, {L"en", L"Complete first and final glyphs"},
      {L"ja", L"日本語の歌詞を表示"}, {L"ko", L"한국어 가사를 표시합니다"}}) {
    CHECK(frame(pair.second, pair.second, pair.first, 1000, false, false));
    CHECK(SaveSurface(surface, output + L"/" + pair.first + L"-two-rows.png"));
  }
  const auto legal = std::wstring(2 * 1024 * 1024, L'W');
  CHECK(frame(legal, L"Complete text uses bounded pages", L"legal", 0, false, false));
  CHECK(SaveSurface(surface, output + L"/legal-text-first.png"));
  CHECK(frame(legal, L"Complete text uses bounded pages", L"legal", 4000, false, false));
  CHECK(SaveSurface(surface, output + L"/legal-text-final.png"));
  lyrics.EnvironmentChanged();
  CHECK(WaitVisible());
  CHECK(GetForegroundWindow() == foreground);
  lyrics.Close(); Pump(700);
  CHECK(!IsWindow(surface) && !OwnedSurface());
  CHECK(SaveRegion(bounds, output + L"/surface-disabled.png", false));
  const auto baseline = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
  for (int iteration = 0; iteration < 8; ++iteration) {
    CHECK(frame(L"Transient QA line", L"", std::to_wstring(iteration), 0, false, false));
    lyrics.Close();
  }
  Pump(1200);
  CHECK(!OwnedSurface());
  CHECK(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == baseline);
  CHECK(GetForegroundWindow() == foreground);
  Gdiplus::GdiplusShutdown(gdiplus);
  std::cout << "taskbar lyrics actual surface: " << checks << " checks PASS\n";
  return 0;
}
